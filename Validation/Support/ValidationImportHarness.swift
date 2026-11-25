#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Test-only import fixtures")
#endif
import SwiftUI

struct ValidationImportHarness: View {
    @StateObject private var model = GPXImportReviewModel(loader: { url in
        if url.lastPathComponent == "slow.gpx" { try await Task.sleep(for: .seconds(3)) }
        return try await GPXImporter.load(from:url)
    })
    @StateObject private var planner = RoutePlanner()
    @State private var original: String = "Existing route preserved"
    @State private var pending: [RoutePoint]?
    @State private var recoveryResult = ""
    static let valid = "<gpx><trk><name>Garden path</name><trkseg><trkpt lat='40.768' lon='-73.981'/><trkpt lat='40.770' lon='-73.975'/></trkseg></trk><rte><name>Second path</name><rtept lat='40.770' lon='-73.975'/><rtept lat='40.779' lon='-73.970'/></rte></gpx>"
    var body: some View {
        NavigationStack {
            List {
                Text(original).accessibilityIdentifier("import.result")
                Button("Open GPX") { load("valid.gpx", Self.valid) }
                Button("Open large GPX") {
                    let points = (0..<90_000).map { RoutePoint(latitude:40 + Double($0)*0.00001,longitude:-73) }
                        + [RoutePoint(latitude:45,longitude:-73)]
                    load("large.gpx", GPXDocument.export(points))
                }
                Button("Check recovery edge cases") { checkRecoveryEdges() }
                Button("Open broken GPX") { load("broken.gpx", "<gpx><trk>") }
                Button("Open slow GPX") { load("slow.gpx", Self.valid) }
                NavigationLink("Recovery copies") { SavedPlaceRecoveryView() }
                Button("Check recovery persisted") {
                    let live = SavedPlace.load(key: "locus.favorites")
                    if live.map(\.name) == ["Validated recovery place"], SavedPlace.recoveryCopyCount(key: "locus.favorites") == 1 {
                        recoveryResult = "Validated place restored and other copy kept"
                    } else {
                        recoveryResult = SavedPlace.hasRecovery(key: "locus.favorites") ? "Recovery remains" : "Recovery discarded after reload"
                    }
                }
                Text(recoveryResult)
            }.navigationTitle("Import validation")
            .sheet(isPresented: $model.isPresented, onDismiss: {
                model.cancel()
                if let points = pending {
                    pending = nil
                    planner.useCustom(points.map(\.coordinate),source:.gpx)
                    if let route = planner.alternatives.first,
                       RoutePoint(route.origin.coordinate) == points.first,
                       RoutePoint(route.destination.coordinate) == points.last, route.source == .gpx {
                        if points.count > 80_000 {
                            let library = TripLibrary()
                            let saved = library.save(route:route,name:"Large GPX QA",mode:.walk,speed:3,smooth:false)
                            let reopened = TripLibrary().trips.first { $0.name == "Large GPX QA" }
                            var vertex = 0
                            for point in route.coordinates where vertex < points.count {
                                if RoutePoint(point) == points[vertex] { vertex += 1 }
                            }
                            original = saved && reopened?.points.count == route.track.points.count
                                && route.track.points.count <= 100_000 && vertex == points.count
                                ? "Large GPX saved and reopened; all corners preserved" : "Large GPX persistence failed"
                        } else { original = "Imported \(points.count) points into planner" }
                    } else { original = "Planner import failed" }
                }
            }) {
                GPXImportReviewView(model:model) { pending = $0.points }
                    .environment(\.dynamicTypeSize, ValidationFixture.largeText ? .accessibility5 : .large)
                    .frame(maxWidth: ProcessInfo.processInfo.arguments.contains("--narrow") ? 320 : .infinity)
            }
        }
    }
    private func checkRecoveryEdges() {
        let defaults = AppDataWorkspace.defaults
        let key = "validation.recovery.edges"
        do {
            let tooMany = (0..<1_001).map { SavedPlace(name:"Place \($0)",latitude:40+Double($0)*0.00001,longitude:-73) }
            let original = try JSONEncoder().encode(tooMany)
            defaults.set(original,forKey:key+".recovery")
            let refused = SavedPlace.recovery(key: key) == nil
                && defaults.data(forKey:key+".recovery") == original && defaults.data(forKey:key) == nil
            let good = Array(tooMany.prefix(1))
            defaults.set(try JSONEncoder().encode(good),forKey:key+".recovery")
            let broken = Data("damaged history container".utf8)
            defaults.set(broken,forKey:key+".recovery.history")
            let exported = SavedPlace.exportRecovery(key:key)
            let json = try JSONSerialization.jsonObject(with: exported ?? Data()) as? [String:Any]
            let raw = (json?["copiesBase64"] as? [String]) ?? []
            let restored = SavedPlace.recovery(key: key).flatMap { SavedPlace.restoreRecovery($0, key: key) } == good
            let kept = SavedPlace.recoveryCopyCount(key:key) == 1
                && SavedPlace.exportRecovery(key:key) != nil
            let now = Date()
            let recent = tooMany.prefix(30).map { value -> SavedPlace in
                var copy = value
                copy.visitedAt = now.addingTimeInterval(-2 * 86_400)
                return copy
            }
            let recentRaw = try JSONEncoder().encode(recent)
            defaults.set(recentRaw, forKey: "locus.recents.recovery")
            let preview = SavedPlace.recentRecovery(retention: .oneWeek, now: now)
            let stricterLimitRefused = preview.flatMap {
                SavedPlace.restoreRecentRecovery($0, retention: .oneDay, now: now)
            } == nil && defaults.data(forKey: "locus.recents") == nil
            let capped = preview?.places.count == 20
                && preview.flatMap { SavedPlace.restoreRecentRecovery($0, retention: .oneWeek, now: now) } == preview?.places
                && defaults.data(forKey: "locus.recents.recovery") == recentRaw

            defaults.set(try JSONEncoder().encode(good), forKey: key + ".recovery")
            let selected = SavedPlace.recovery(key: key)
            let replacement = try JSONEncoder().encode(Array(tooMany.dropFirst().prefix(1)))
            defaults.set(replacement, forKey: key + ".recovery")
            let replacementRefused = selected != nil
                && selected.flatMap { SavedPlace.restoreRecovery($0, key: key) } == nil
                && SavedPlace.load(key: key) == good && defaults.data(forKey: key + ".recovery") == replacement
            recoveryResult = refused && restored && kept && capped && stricterLimitRefused && replacementRefused
                && raw.contains(broken.base64EncodedString())
                ? "Recovery limits and raw copies preserved" : "Recovery edge validation failed"
        } catch { recoveryResult=error.localizedDescription }
    }
    private func load(_ name:String,_ text:String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try Data(text.utf8).write(to:url); model.start(url) }
        catch { original = error.localizedDescription }
    }
}
