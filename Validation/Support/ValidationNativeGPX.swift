#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Test-only native GPX fixtures")
#endif
import Foundation
import UniformTypeIdentifiers

enum ValidationNativeGPX {
    struct Sample {
        let filename: String
        let name: String
        let pointCount: Int
        let vertices: [RoutePoint]

        init(filename: String, name: String, pointCount: Int, latitude: Double) {
            self.filename = filename
            self.name = name
            self.pointCount = pointCount
            vertices = [
                RoutePoint(latitude: latitude, longitude: -73.980),
                RoutePoint(latitude: latitude, longitude: -73.977),
                RoutePoint(latitude: latitude + 0.003, longitude: -73.977),
                RoutePoint(latitude: latitude + 0.003, longitude: -73.974),
                RoutePoint(latitude: latitude + 0.006, longitude: -73.974)
            ].map { point in
                RoutePoint(latitude: (point.latitude * 1_000).rounded() / 1_000, longitude: point.longitude)
            }
        }

        func encoded() -> Data {
            let locale = Locale(identifier: "en_US_POSIX")
            func trackPoint(_ point: RoutePoint) -> String {
                String(format: "<trkpt lat=\"%.8f\" lon=\"%.8f\"/>\n", locale: locale, point.latitude, point.longitude)
            }
            var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            xml += "<gpx version=\"1.1\" creator=\"Elsepin Validation\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
            xml += "<trk><name>\(name) source</name><trkseg>\n\(trackPoint(vertices[0]))"
            xml.reserveCapacity(pointCount * 45)
            let legs = vertices.count - 1
            for leg in 0..<legs {
                let start = vertices[leg]
                let end = vertices[leg + 1]
                let steps = (pointCount - 1) / legs + (leg < (pointCount - 1) % legs ? 1 : 0)
                for step in 1...steps {
                    let fraction = Double(step) / Double(steps)
                    let point = RoutePoint(latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                                           longitude: start.longitude + (end.longitude - start.longitude) * fraction)
                    xml += trackPoint(point)
                }
            }
            xml += "</trkseg></trk></gpx>\n"
            return Data(xml.utf8)
        }
    }

    static let samples = [
        Sample(filename: "QA-GPX-small.gpx", name: "QA small", pointCount: 64, latitude: 40.770),
        Sample(filename: "QA-GPX-medium.bin", name: "QA medium", pointCount: 4_096, latitude: 40.790),
        Sample(filename: "QA-GPX-large.gpx", name: "QA large", pointCount: 90_000, latitude: 40.810)
    ]
    static let malformedFile = "QA-GPX-malformed.gpx"
    static let roundTripName = "Harbor switchback"
    private static let roundTripOriginalID = UUID(uuidString: "5E1E4E2B-DC57-4571-BA48-947E26A5E111")!
    private static let roundTripPoints = [
        RoutePoint(latitude: 40.768, longitude: -73.981),
        RoutePoint(latitude: 40.768, longitude: -73.975),
        RoutePoint(latitude: 40.779, longitude: -73.975)
    ]
    private static let fixtures = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NativeGPXFixtures", isDirectory: true)

    private static func fixtureURL(_ filename: String) -> URL {
        fixtures.appendingPathComponent(filename)
    }

    private static func exportReceipt(for filename: String) -> URL {
        fixtureURL(filename).appendingPathExtension("export-receipt.json")
    }

    static func exportableFiles(includeSamples: Bool) -> [URL] {
        let names = includeSamples ? samples.map(\.filename) : [malformedFile, samples[0].filename]
        return names.map(fixtureURL)
    }

    static func prepare(includeSamples: Bool) throws {
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        for sample in samples.prefix(includeSamples ? samples.count : 1) {
            let receipt = exportReceipt(for: sample.filename)
            if FileManager.default.fileExists(atPath: receipt.path) {
                try FileManager.default.removeItem(at: receipt)
            }
            try sample.encoded().write(to: fixtureURL(sample.filename), options: .atomic)
        }
        if !includeSamples {
            try Data("<gpx><trk>".utf8).write(to: fixtureURL(malformedFile), options: .atomic)
        }
    }

    static func observeExport(_ url: URL) {
        let filename = url.lastPathComponent
        guard samples.contains(where: { $0.filename == filename }) else { return }
        let source = fixtureURL(filename)
        guard source.standardizedFileURL != url.standardizedFileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var receipt: [String: Any] = ["filename": filename]
        if let attributes = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]) {
            receipt["bytes"] = attributes.fileSize
            receipt["contentType"] = attributes.contentType?.identifier
        }
        if let sourceData = try? Data(contentsOf: source), let exportedData = try? Data(contentsOf: url) {
            receipt["matchesSourceBytes"] = exportedData == sourceData
            receipt["bytes"] = exportedData.count
        }
        if let data = try? JSONSerialization.data(withJSONObject: receipt) {
            try? data.write(to: exportReceipt(for: filename), options: .atomic)
        }
    }

    @MainActor static func seedRoundTrip() throws -> Bool {
        let trip = SavedTrip(id: roundTripOriginalID, name: roundTripName, mode: .walk, speedMPH: 1.4, smoothMovement: false,
            originName: "Harbor entrance", destinationName: "Harbor overlook", points: roundTripPoints,
            source: .drawn, instructions: [], stops: [], calculatedAt: .now, favorite: true)
        return try TripLibrary().merge([trip])
    }

    @MainActor static func roundTripDiskReport() throws -> String {
        let disk = TripLibrary()
        if let error = disk.error { return "Library reload failed: \(error)" }
        let matching = disk.trips.filter { $0.name == roundTripName }
        let originals = matching.filter { $0.source == .drawn }
        let imports = matching.filter { $0.source == .gpx }
        let recoveredPoints = imports.first?.points ?? []
        let report: [String: Any] = ["originalCount": originals.count, "importCount": imports.count,
            "originalID": originals.first?.id.uuidString ?? "",
            "newCopyHasDistinctID": imports.first?.id != originals.first?.id,
            "originalHasExactGeometry": originals.first?.points == roundTripPoints,
            "importHasExactEndpoints": recoveredPoints.first == roundTripPoints.first && recoveredPoints.last == roundTripPoints.last,
            "importHasExactTurn": recoveredPoints.dropFirst().dropLast().contains(roundTripPoints[1])]
        return String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self)
    }

    @MainActor static func diskReport() throws -> String {
        let disk = TripLibrary()
        if let error = disk.error { return "Library reload failed: \(error)" }
        let report: [[String: Any]] = try samples.map { sample in
            let matches = disk.trips.filter { $0.name == sample.name }
            let trip = matches.first
            let points = trip?.points ?? []
            var retained = 0
            for point in points where retained < sample.vertices.count {
                if point == sample.vertices[retained] { retained += 1 }
            }
            let url = fixtureURL(sample.filename)
            let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            var entry: [String: Any] = ["filename": sample.filename, "name": trip?.name ?? "", "sourceBytes": attributes.fileSize ?? 0,
                "sourceContentType": attributes.contentType?.identifier ?? "unknown",
                "sourcePoints": sample.pointCount, "persistedPoints": points.count,
                "matches": matches.count, "fromGPX": trip?.source == .gpx,
                "verticesRetainedInOrder": retained,
                "endpointsRetained": points.first == sample.vertices.first && points.last == sample.vertices.last]
            if let data = try? Data(contentsOf: exportReceipt(for: sample.filename)) {
                entry["providerExport"] = try JSONSerialization.jsonObject(with: data)
            }
            return entry
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self)
    }
}
