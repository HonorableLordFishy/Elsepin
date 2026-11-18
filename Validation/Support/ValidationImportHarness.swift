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
                Button("Open broken GPX") { load("broken.gpx", "<gpx><trk>") }
                Button("Open slow GPX") { load("slow.gpx", Self.valid) }
                NavigationLink("Recovery copies") { SavedPlaceRecoveryView() }
                Button("Check recovery persisted") {
                    _ = SavedPlace.load(key:"locus.favorites")
                    recoveryResult = SavedPlace.hasRecovery(key:"locus.favorites") ? "Recovery remains" : "Recovery discarded after reload"
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
                        original = "Imported \(points.count) points into planner"
                    } else { original = "Planner import failed" }
                }
            }) {
                GPXImportReviewView(model:model) { pending = $0 }
            }
        }
    }
    private func load(_ name:String,_ text:String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try Data(text.utf8).write(to:url); model.start(url) }
        catch { original = error.localizedDescription }
    }
}
