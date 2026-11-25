import Foundation

/// Route history can contain 100,000 points. Keep the payload out of preferences.
final class RecentRouteStore {
    static let relativePath = "RecentRouteHistory/RecentRoutes.json"
    private static let legacyKey = "locus.recentRoutes"
    private static let legacyAvailableKey = "locus.recentRoutesAvailable"
    private static let queue = DispatchQueue(label: "locus.recent-routes", qos: .utility)
    private let workspace: AppDataWorkspace

    init(workspace: AppDataWorkspace = .shared) {
        self.workspace = workspace
    }

    func load() -> [RecentRoute] {
        let context = workspace.context
        return Self.queue.sync {
            let file = context.file(Self.relativePath)
            if FileManager.default.fileExists(atPath: file.path) {
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= LibraryBackup.maximumBytes,
                      let data = try? Data(contentsOf: file), let routes = Self.decode(data) else { return [] }
                Self.removeLegacyKeys(from: context.defaults)
                return routes
            }
            let defaults = context.defaults
            let legacy = defaults.data(forKey: Self.legacyKey)
            guard defaults.object(forKey: Self.legacyAvailableKey) != nil || legacy != nil else { return [] }
            // Keep a readable legacy copy if the migration cannot write its replacement.
            if defaults.bool(forKey: Self.legacyAvailableKey), let legacy, let routes = Self.decode(legacy) {
                try? Self.write(legacy, to: context)
                return routes
            }
            try? Self.write(Data("[]".utf8), to: context)
            return []
        }
    }

    func save(_ routes: [RecentRoute]) {
        if routes.isEmpty {
            try? clear()
            return
        }
        let context = workspace.context
        Self.queue.async { try? Self.write(Self.encode(routes), to: context) }
    }

    func clear() throws {
        let context = workspace.context
        // Wait out earlier saves and atomically replace their payload. The empty
        // file also prevents legacy fallback if the app exits during cleanup.
        try Self.queue.sync { try Self.write(Data("[]".utf8), to: context) }
    }

    func finishPendingWrites() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.queue.async { continuation.resume() }
        }
    }

    /// Dev Mode seeds its unpublished workspace before activating it.
    static func seed(_ routes: [RecentRoute], in context: AppDataWorkspace.Context) throws {
        try write(encode(routes), to: context)
    }

    private static func encode(_ routes: [RecentRoute]) throws -> Data {
        let data = try JSONEncoder().encode(routes)
        guard data.count <= LibraryBackup.maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    private static func decode(_ data: Data) -> [RecentRoute]? {
        guard data.count <= LibraryBackup.maximumBytes else { return nil }
        return try? JSONDecoder().decode([RecentRoute].self, from: data)
    }

    private static func write(_ data: Data, to context: AppDataWorkspace.Context) throws {
        let file = context.file(relativePath)
        var folder = file.deletingLastPathComponent()
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if !manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            // Demo activation creates its workspace. A queued stale write must
            // never recreate that workspace after Dev Mode removes it.
            try manager.createDirectory(at: folder, withIntermediateDirectories: context.id == nil)
        }
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        try folder.setResourceValues(resource)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        removeLegacyKeys(from: context.defaults)
    }

    private static func removeLegacyKeys(from defaults: UserDefaults) {
        for key in [legacyKey, legacyAvailableKey] where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }
}
