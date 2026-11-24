import UniformTypeIdentifiers

enum ImportFileTypes {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
    static let gpxImport = matching("gpx", fallbacks: [gpx, .xml, .text, .data, .item])
    static let backupImport = matching("json", fallbacks: [.json, .text, .data, .item])

    private static func matching(_ filenameExtension: String, fallbacks: [UTType]) -> [UTType] {
        // Providers can declare their own types for the same extension, or
        // report a generic type. The bounded content reader makes the final check.
        let specific = UTType.types(tag: filenameExtension, tagClass: .filenameExtension, conformingTo: nil)
        var seen = Set<String>()
        return (specific + fallbacks).filter { seen.insert($0.identifier).inserted }
    }
}
