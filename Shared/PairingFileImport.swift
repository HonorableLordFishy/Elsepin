import Foundation

enum PairingFileImport {
    static let maximumBytes = 1024 * 1024

    enum StagingSource: String, CaseIterable {
        case imported = ".pairing-"
        case onDevice = ".on-device-"

        func stagedURL(in directory: URL) -> URL {
            directory.appendingPathComponent(rawValue + UUID().uuidString + ".plist")
        }

        func owns(_ filename: String) -> Bool {
            let suffix = ".plist"
            guard filename.hasPrefix(rawValue), filename.hasSuffix(suffix) else { return false }
            let id = filename.dropFirst(rawValue.count).dropLast(suffix.count)
            return UUID(uuidString: String(id)) != nil
        }
    }

    /// Call only while no native worker can be writing a staged pairing.
    static func removeAbandonedStagingFiles(in directory: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        let contents = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        for item in contents where StagingSource.allCases.contains(where: { $0.owns(item.lastPathComponent) }) {
            guard try item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try manager.removeItem(at: item)
        }
    }

    enum Failure: LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: return "This isn't a valid RPPairing file. Your existing pairing has not changed."
            case .tooLarge: return "Pairing files must be smaller than 1 MB. Your existing pairing has not changed."
            }
        }
    }

    /// A vendor decoder must accept the staged file before the live file changes.
    static func install(_ data: Data, at destination: URL, validate: (URL) throws -> Void) throws {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard !data.isEmpty,
              let contents = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              contents is [String: Any] else {
            throw Failure.invalid
        }
        let manager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = StagingSource.imported.stagedURL(in: directory)
        defer { try? manager.removeItem(at: staged) }
        #if os(iOS)
        try data.write(to: staged, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: staged, options: .atomic)
        #endif
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        try validate(staged)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staged, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: staged, to: destination)
        }
    }
}
