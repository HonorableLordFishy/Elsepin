import CoreLocation
import Foundation

struct SavedPlace: Identifiable, Codable, Equatable {
    var id: String { "\(latitude),\(longitude)" }
    var name: String
    var displayName: String { PlaceLabel.readable(name) }
    var latitude: Double
    var longitude: Double
    var visitedAt: Date? = nil
    var folder: String? = nil
    var icon: String? = nil
    var color: String? = nil
    var favorite: Bool? = nil
    var address: String? = nil
    var emoji: String? = nil
    var isFavorite: Bool { favorite ?? true }
    var symbol: SavedPlaceSymbol { icon.flatMap(SavedPlaceSymbol.init(rawValue:)) ?? .pin }
    var tint: SavedPlaceTint { color.flatMap(SavedPlaceTint.init(rawValue:)) ?? .mint }
    var backupPlace: BackupPlace { BackupPlace(name: name, latitude: latitude, longitude: longitude, folder: folder, icon: icon, color: color, favorite: favorite, address: address, emoji: emoji) }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func load(key: String) -> [SavedPlace] {
        switch archive(key).load() {
        case .loaded(let places): return places
        case .missing, .unreadable: return []
        }
    }

    static func save(_ places: [SavedPlace], key: String) {
        _ = archive(key).save(places)
    }

    static func loadRecents(retention: RecentHistoryRetention, saveEnabled: Bool, now: Date = Date()) -> [SavedPlace] {
        guard saveEnabled else {
            AppDataWorkspace.defaults.removeObject(forKey: "locus.recents")
            discardRecovery(key: "locus.recents")
            return []
        }
        // Do not turn an unreadable archive into an empty one and delete it.
        // The original is preserved under locus.recents.recovery.
        switch archive("locus.recents").load() {
        case .missing: return []
        case .loaded(let places):
            return saveRecents(places, retention: retention, saveEnabled: saveEnabled, now: now)
        case .unreadable: return []
        }
    }

    @discardableResult
    static func saveRecents(_ places: [SavedPlace], retention: RecentHistoryRetention, saveEnabled: Bool, now: Date = Date()) -> [SavedPlace] {
        guard saveEnabled else {
            AppDataWorkspace.defaults.removeObject(forKey: "locus.recents")
            discardRecovery(key: "locus.recents")
            return []
        }
        _ = archive("locus.recents").load() // Preserve unreadable originals before retention can remove the live key.
        let kept = Array(places.filter {
            $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude)
                && (-180...180).contains($0.longitude) && retention.keeps(visitedAt: $0.visitedAt, now: now)
        }.prefix(20))
        if kept.isEmpty { AppDataWorkspace.defaults.removeObject(forKey: "locus.recents") }
        else if kept != load(key: "locus.recents") { save(kept, key: "locus.recents") }
        return kept
    }

    static func hasRecovery(key: String) -> Bool {
        archive(key).hasRecovery
    }

    struct Recovery {
        fileprivate let workspace: UUID
        fileprivate let copy: RecoverableJSONList<SavedPlace>.RecoveryCopy
        var places: [SavedPlace] { copy.values }
    }

    static func recovery(key: String) -> Recovery? {
        let workspace = AppDataWorkspace.shared.context
        let archive = RecoverableJSONList<SavedPlace>(key: key, store: workspace.defaults)
        guard let copy = archive.recoveryCopy(prepare: { places in
            guard places.count <= 1_000, Set(places.map(\.id)).count == places.count,
                  places.allSatisfy({ $0.coordinate.isValidForRecovery }) else { return nil }
            return places
        }) else { return nil }
        return Recovery(workspace: workspace.generation, copy: copy)
    }

    static func restoreRecovery(_ recovery: Recovery, key: String) -> [SavedPlace]? {
        let workspace = AppDataWorkspace.shared.context
        guard workspace.generation == recovery.workspace else { return nil }
        return RecoverableJSONList<SavedPlace>(key: key, store: workspace.defaults).restoreRecovery(recovery.copy)
    }

    static func recentRecovery(retention: RecentHistoryRetention, now: Date = Date()) -> Recovery? {
        let workspace = AppDataWorkspace.shared.context
        let archive = RecoverableJSONList<SavedPlace>(key: "locus.recents", store: workspace.defaults)
        guard let copy = archive.recoveryCopy(prepare: { keptRecoveryRecents($0, retention: retention, now: now) }) else { return nil }
        return Recovery(workspace: workspace.generation, copy: copy)
    }

    static func restoreRecentRecovery(_ recovery: Recovery, retention: RecentHistoryRetention, now: Date = Date()) -> [SavedPlace]? {
        let workspace = AppDataWorkspace.shared.context
        guard workspace.generation == recovery.workspace,
              keptRecoveryRecents(recovery.places, retention: retention, now: now) == recovery.places else { return nil }
        // Keep the full copy available for export, including expired/overflow entries.
        return RecoverableJSONList<SavedPlace>(key: "locus.recents", store: workspace.defaults)
            .restoreRecovery(recovery.copy, keepingOriginal: true)
    }

    private static func keptRecoveryRecents(_ places: [SavedPlace], retention: RecentHistoryRetention, now: Date) -> [SavedPlace] {
        var seen = Set<String>()
        return Array(places.filter {
            $0.coordinate.isValidForRecovery && retention.keeps(visitedAt: $0.visitedAt, now: now)
                && seen.insert($0.id).inserted
        }.prefix(20))
    }

    static func discardRecovery(key: String) {
        archive(key).discardRecovery()
    }

    static func exportRecovery(key: String) -> Data? { archive(key).exportRecovery() }
    static func recoveryCopyCount(key: String) -> Int { archive(key).recoveryCopies.count }

    private static func archive(_ key: String) -> RecoverableJSONList<SavedPlace> {
        RecoverableJSONList(key: key, store: AppDataWorkspace.defaults)
    }
}

private extension CLLocationCoordinate2D {
    var isValidForRecovery: Bool {
        latitude.isFinite && longitude.isFinite && CLLocationCoordinate2DIsValid(self)
    }
}
