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

    struct RecoveryCopy {
        fileprivate let source: Data
        fileprivate let key: String
        fileprivate let store: PersistedDataStore
        let values: [Element]
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
        if let data = store.data(forKey: historyKey) {
            // A damaged container is itself a recoverable original, even without
            // a subsequent save. It must remain visible and exportable.
            let history = (try? decoder.decode([Data].self, from: data)) ?? [data]
            for copy in history where !copies.contains(copy) { copies.append(copy) }
        }
        return copies
    }
    var hasRecovery: Bool { store.data(forKey: recoveryKey) != nil || store.data(forKey: historyKey) != nil }

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
        recoveryCopy()?.values
    }

    func recoveryCopy(prepare: ([Element]) -> [Element]? = { $0 }) -> RecoveryCopy? {
        for source in recoveryCopies {
            guard let decoded = try? decoder.decode([Element].self, from: source),
                  let values = prepare(decoded) else { continue }
            return RecoveryCopy(source: source, key: key, store: store, values: values)
        }
        return nil
    }

    func restoreRecovery(keepingOriginal: Bool = false,
                         prepare: ([Element]) -> [Element]? = { $0 }) -> [Element]? {
        guard let copy = recoveryCopy(prepare: prepare) else { return nil }
        return restoreRecovery(copy, keepingOriginal: keepingOriginal)
    }

    /// Apply the exact preview while it still exists in its original archive.
    /// Consume only that copy. A filtered restore keeps its full source.
    func restoreRecovery(_ copy: RecoveryCopy, keepingOriginal: Bool = false) -> [Element]? {
        guard copy.store === store, copy.key == key, recoveryCopies.contains(copy.source),
              save(copy.values) else { return nil }
        if !keepingOriginal {
            // Read again after saving, which may have preserved an unreadable live original.
            let remaining = recoveryCopies.filter { $0 != copy.source }
            guard let history = try? encoder.encode(Array(remaining.dropFirst())) else { return copy.values }
            if let first = remaining.first {
                store.set(first, forKey: recoveryKey)
                if remaining.count > 1 { store.set(history, forKey: historyKey) }
                else { store.removeObject(forKey: historyKey) }
            } else {
                store.removeObject(forKey: recoveryKey)
                store.removeObject(forKey: historyKey)
            }
        }
        return copy.values
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
        copies.append(data)
        guard let encoded = try? encoder.encode(Array(copies.dropFirst())) else { return false }
        store.set(encoded, forKey: historyKey)
        return true
    }
}
