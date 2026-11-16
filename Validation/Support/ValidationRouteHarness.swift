#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Route fixtures are simulator tests only")
#endif
import SwiftUI
import MapKit

/// Exercise the production planner with deterministic directions. No pairing,
/// location write or Apple routing response is claimed by these checks.
@MainActor
private final class ValidationRouteDriver: ObservableObject {
    struct Request {
        let start: RoutePlace; let end: RoutePlace; let stops: [TripWaypoint]
        let mode: TravelMode; let choices: [UUID: RouteLegChoice]; let speed: Double
    }
    @Published var report = "Running"
    var requests: [Request] = []
    var fail = false
    lazy var planner = RoutePlanner { [weak self] start, end, stops, mode, _, choices, speed in
        guard let self else { throw CancellationError() }
        self.requests.append(.init(start: start, end: end, stops: stops, mode: mode, choices: choices, speed: speed))
        try await Task.sleep(for: .milliseconds(50))
        if self.fail { throw NSError(domain: "ValidationDirections", code: 1) }
        var result = ValidationFixture.route
        result.origin = start; result.destination = end
        result.storedMode = mode
        result.stops = stops.enumerated().map { index, stop in
            RouteStop(id: stop.id, name: stop.name, metres: result.track.length * Double(index + 1) / Double(stops.count + 1), waitSeconds: stop.waitSeconds)
        }
        let ids = stops.map(\.id) + [RouteLegChoice.destinationID]
        let boundaries = [0.0] + result.stops.map(\.metres) + [result.track.length]
        result.travelSections = ids.enumerated().map { index, id in
            let choice = choices[id] ?? .init(mode: mode, speedMPH: speed)
            return RouteTravelSection(id: id, startMetres: boundaries[index], endMetres: boundaries[index + 1], mode: choice.mode, speedMPH: choice.speedMPH)
        }
        return [result]
    }
    let trip: SavedTrip

    init() {
        var route = ValidationFixture.route
        route.stops = [RouteStop(name: "Test cafe", metres: route.track.length / 3, waitSeconds: 90),
                       RouteStop(name: "Test pond", metres: route.track.length * 2 / 3, waitSeconds: 30)]
        trip = route.savedTrip(name: "Test saved walk", mode: .walk, speed: 1.4, smooth: true, arrival: .stay)
    }

    func waitForDirections() async {
        for _ in 0..<100 where planner.isLoading { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append(message) }
    }

    func exercise(session: SpoofSession) async {
        var failures: [String] = []
        session.setSpeedMPH(1.5, for: .walk)
        session.setUsualSpeedMPH(4.5, for: .walk)
        session.setUsualSpeedMPH(85, for: .drive)
        session.setUsualSpeedMPH(31, for: .eBike)
        check(session.speedMPH(for: .walk) == 1.5, "Changing defaults changed the current speed", failures: &failures)
        session.changeTravelMode(.drive, keepCurrentPath: true)
        check(session.speedMPH(for: .drive) == 85, "Drive used a cached speed", failures: &failures)
        session.changeTravelMode(.eBike, keepCurrentPath: true)
        check(session.speedMPH(for: .eBike) == 31, "E-bike used a cached speed", failures: &failures)
        session.changeTravelMode(.walk, keepCurrentPath: true)

        planner.discardDraft()
        planner.useCustom(ValidationFixture.points, source: .drawn)
        planner.initializeDraftIfNeeded(mode: .walk, speedMPH: session.usualSpeedMPH(for: .walk), smoothMovement: false)
        check(planner.draftSpeedMPH == 4.5, "New drawn draft ignored Usual speeds", failures: &failures)
        planner.discardDraft()
        planner.initializeDraftIfNeeded(mode: .drive, speedMPH: session.usualSpeedMPH(for: .drive), smoothMovement: false)
        check(planner.draftSpeedMPH == 85, "New planned draft ignored Usual speeds", failures: &failures)

        planner.useSaved(trip)
        planner.initializeDraftIfNeeded(mode: .drive, speedMPH: 85, smoothMovement: false)
        check(planner.draftSpeedMPH == 1.4 && planner.draftMode == .walk && planner.draftSmoothMovement,
              "Saved settings were overwritten", failures: &failures)
        let originalID = planner.selectedID
        let stops = planner.waypoints
        let origin = RoutePoint(planner.origin!.coordinate), destination = RoutePoint(planner.destination!.coordinate)
        planner.setSectionChoice(.init(mode: .drive, speedMPH: 85), for: stops[0].id, defaultMode: .walk, pathChoice: .keepCurrent)
        check(requests.isEmpty && planner.selectedID == originalID, "Keeping a saved path requested directions", failures: &failures)
        planner.useSaved(trip)
        planner.setSectionChoice(.init(mode: .drive, speedMPH: 85), for: stops[0].id, defaultMode: .walk, pathChoice: .recalculate)
        await waitForDirections()
        check(requests.count == 1 && requests.last?.choices[stops[0].id]?.speedMPH == 85,
              "Saved leg did not request the chosen directions", failures: &failures)

        planner.useSaved(trip)
        planner.recalculateAllLegs(using: .init(mode: .eBike, speedMPH: 31))
        await waitForDirections()
        if let request = requests.last {
            check(request.mode == .eBike && request.speed == 31 && request.choices.count == 3 && request.choices.values.allSatisfy { $0.mode == .eBike && $0.speedMPH == 31 },
                  "Recalculation lost all-leg mode or speed", failures: &failures)
            check(request.stops == stops && RoutePoint(request.start.coordinate) == origin && RoutePoint(request.end.coordinate) == destination,
                  "Recalculation changed places, order, IDs or waits", failures: &failures)
        } else { failures.append("No recalculation request") }
        check(planner.editingTripID == trip.id && planner.selectedRoute?.name == trip.name && planner.draftSmoothMovement,
              "Recalculation lost the saved identity, name or smoothing", failures: &failures)
        check(trip.mode == .walk && trip.speedMPH == 1.4, "Library value mutated", failures: &failures)

        planner.useSaved(trip)
        let previousID = planner.selectedID
        fail = true
        planner.recalculateAllLegs(using: .init(mode: .drive, speedMPH: 85))
        await waitForDirections()
        check(planner.error != nil && planner.canRestorePreviousRoute, "Failure lost the recovery action", failures: &failures)
        planner.restorePreviousRoute()
        check(planner.selectedID == previousID && planner.editingTripID == trip.id && planner.waypoints == stops && planner.draftMode == .walk && planner.draftSpeedMPH == 1.4 && planner.usesStoredPath,
              "Failure restore lost saved path or settings", failures: &failures)
        fail = false
        planner.recalculateAllLegs(using: .init(mode: .drive, speedMPH: 85))
        planner.discardDraft()
        try? await Task.sleep(for: .milliseconds(100))
        check(planner.selectedRoute == nil && !planner.isLoading, "Canceled directions replaced the discarded draft", failures: &failures)
        planner.useSaved(trip)
        report = failures.isEmpty ? "Passed" : failures.joined(separator: "; ")
    }
}

struct ValidationRouteHarness: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var preferences: SessionPreferences
    @EnvironmentObject private var library: TripLibrary
    @StateObject private var driver = ValidationRouteDriver()
    @State private var started = false
    @State private var showPlanner = false
    @State private var showSettings = false
    @State private var snapshot = "{}"
    @State private var lastID: UUID?

    // Read a fresh instance from disk, not the in-memory object used by Save.
    // This probe only observes the shipping persistence API; it never saves.
    private func refreshSnapshot() {
        let disk = TripLibrary()
        let id = lastID ?? driver.trip.id
        let trip = disk.trips.first { $0.id == id }
        var value: [String: Any] = ["loadError": disk.error ?? "", "count": disk.trips.count,
            "usualWalk": session.usualSpeedMPH(for: .walk), "usualDrive": session.usualSpeedMPH(for: .drive),
            "draftSpeed": driver.planner.draftSpeedMPH, "draftMode": driver.planner.draftMode.rawValue]
        if let trip, let data = try? JSONEncoder().encode(trip),
           let object = try? JSONSerialization.jsonObject(with: data) { value["saved"] = object }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { snapshot = text }
    }

    private func openSaved(_ id: UUID) {
        guard let trip = TripLibrary().trips.first(where: { $0.id == id }) else {
            driver.report = "Saved trip missing from disk"; return
        }
        lastID = id
        driver.planner.useSaved(trip)
        showPlanner = true
    }

    private func newRoute(drawn: Bool) {
        driver.planner.discardDraft()
        if drawn {
            driver.planner.useCustom(ValidationFixture.points, source: .drawn)
        } else {
            // Same initial draft inputs as the map's new-route action, with
            // deterministic places/directions instead of a remote service.
            driver.planner.initializeDraftIfNeeded(mode: session.travelMode,
                speedMPH: session.usualSpeedMPH(for: session.travelMode), smoothMovement: false)
            driver.planner.plan(to: ValidationFixture.route.destination,
                defaultOrigin: ValidationFixture.route.origin, mode: session.travelMode)
        }
        driver.planner.savesToLibraryOnCompletion = true
        showPlanner = true
    }

    var body: some View {
        NavigationStack {
            List {
                Text(driver.report).accessibilityIdentifier("validation.routeRules")
                if driver.report == "Passed" {
                    Button("Usual speeds") { showSettings = true }
                    Button("New drawn route") { newRoute(drawn: true) }
                    Button("New planned route") { newRoute(drawn: false) }
                    Button("Open saved route") { openSaved(driver.trip.id) }
                    Button("Reopen last saved route") { openSaved(lastID ?? driver.trip.id) }
                    Button("Read saved data") { refreshSnapshot() }
                    Text(snapshot).font(.system(size: 7)).lineLimit(1)
                        .accessibilityIdentifier("validation.savedSnapshot")
                }
            }
            .navigationTitle("Route validation")
        }
            .sheet(isPresented: $showSettings, onDismiss: refreshSnapshot) {
                NavigationStack {
                    UsualSpeedsSettingsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        } }
                }
            }
            .sheet(isPresented: $showPlanner, onDismiss: {
                lastID = library.lastSavedID ?? lastID
                driver.planner.isPresented = false
                refreshSnapshot()
            }) {
                RoutePlannerSheet().environmentObject(driver.planner)
                    .environment(\.shiftEditorEmbedded, true)
            }
            .task {
                guard !started else { return }; started = true
                preferences.speedUnit = .mph
                await driver.exercise(session: session)
                do { _ = try library.merge([driver.trip]) }
                catch { driver.report = "Could not seed disposable route: \(error)" }
                lastID = driver.trip.id
                refreshSnapshot()
            }
    }
}
