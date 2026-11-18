import Foundation

/// UserDefaults and test doubles share this small boundary so the recovery
/// policy can be exercised without touching the app's real preferences.
protocol PersistedDataStore: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: PersistedDataStore {}

/// A JSON array that never turns "couldn't decode" into "there was no data".
/// The first unreadable original is copied to a .recovery key and is not
/// replaced by later unreadable reads. Explicit restore or discard removes it.
struct RecoverableJSONList<Element: Codable> {
    enum LoadResult {
        case missing
        case loaded([Element])
        case unreadable
    }

    let key: String
    let recoveryKey: String
    private let store: PersistedDataStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String, store: PersistedDataStore) {
        self.key = key
        self.recoveryKey = key + ".recovery"
        self.store = store
    }

    private var historyKey: String { recoveryKey + ".history" }
    var recoveryCopies: [Data] {
        var copies = store.data(forKey: recoveryKey).map { [$0] } ?? []
        if let data = store.data(forKey: historyKey), let history = try? decoder.decode([Data].self, from: data) {
            copies += history.filter { !copies.contains($0) }
        }
        return copies
    }
    var hasRecovery: Bool { !recoveryCopies.isEmpty }

    func load() -> LoadResult {
        guard let data = store.data(forKey: key) else { return .missing }
        if let values = try? decoder.decode([Element].self, from: data) {
            return .loaded(values)
        }
        preserve(data)
        return .unreadable
    }

    @discardableResult
    func save(_ values: [Element]) -> Bool {
        guard let data = try? encoder.encode(values) else { return false }
        // Save callers need not have loaded first. Preserve every distinct bad
        // original before replacing the live key, including repeated corruption.
        if let original = store.data(forKey: key), (try? decoder.decode([Element].self, from: original)) == nil {
            guard preserve(original) else { return false }
        }
        store.set(data, forKey: key)
        return true
    }

    func recovery() -> [Element]? {
        recoveryCopies.compactMap { try? decoder.decode([Element].self, from: $0) }.first
    }

    /// Write the preserved array back to the live key, then remove the
    /// recovery copy only after the save succeeds.
    func restoreRecovery() -> [Element]? {
        guard let values = recovery(), save(values) else { return nil }
        discardRecovery()
        return values
    }

    func discardRecovery() {
        // An explicit discard resolves unreadable live data too; otherwise the
        // next launch would recreate the discarded copy. Never clear valid data.
        if let data = store.data(forKey: key), (try? decoder.decode([Element].self, from: data)) == nil {
            store.removeObject(forKey: key)
        }
        store.removeObject(forKey: recoveryKey)
        store.removeObject(forKey: historyKey)
    }

    func exportRecovery() -> Data? {
        guard hasRecovery else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["format": "Elsepin saved-place recovery", "key": key,
            "copiesBase64": recoveryCopies.map { $0.base64EncodedString() }], options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult private func preserve(_ data: Data) -> Bool {
        if store.data(forKey: recoveryKey) == nil { store.set(data, forKey: recoveryKey); return true }
        var copies = recoveryCopies
        if copies.contains(data) { return true }
        // Preserve a damaged history envelope itself before replacing it.
        if let history = store.data(forKey: historyKey), (try? decoder.decode([Data].self, from: history)) == nil { copies.append(history) }
        copies.append(data)
        guard let encoded = try? encoder.encode(Array(copies.dropFirst())) else { return false }
        store.set(encoded, forKey: historyKey)
        return true
    }
}
