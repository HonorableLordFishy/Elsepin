#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Validation fixtures must never compile into a device app")
#endif
import Combine
import CoreFoundation
import SwiftUI
import MapKit
import Network
import UIKit

enum ValidationFixture {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--elsepin-ui-test")
    static var scenario: String { ProcessInfo.processInfo.environment["ELSEPIN_TEST_SCENARIO"] ?? "idle" }
    static var largeText: Bool { ProcessInfo.processInfo.arguments.contains("--large-text") }
    static var dark: Bool { ProcessInfo.processInfo.arguments.contains("--dark") }
    static var fallback: Bool { ProcessInfo.processInfo.arguments.contains("--accessibility-fallback") }
    static var routeIdentityScenario: Bool { scenario.hasPrefix("route-identity-") }
    static var nativeGPXRoundTrip: Bool { scenario == "home-solid-gpx-round-trip" }
    static var nativeGPXFiles: ValidationNativeGPX.FileSet? {
        switch scenario {
        case "home-solid-gpx-sizes": .sizes
        case "home-solid-gpx-malformed": .malformed
        case "home-solid-gpx-generic-data": .genericData
        default: nil
        }
    }
    static var firstLaunch: Bool { scenario == "first-launch" }
    static var drawnRoute: Bool { scenario == "drawn-route" }
    static var routeReconnect: Bool { scenario == "route-reconnect" }
    static var routePace: Bool { scenario == "route-pace" }
    static var stopNetworkPath: StopNetworkPath? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--stop-cellular") {
            return StopNetworkPath(status: .satisfied, usesCellular: true, usesWiFi: false, usesEthernet: false)
        }
        if arguments.contains("--stop-wifi") {
            return StopNetworkPath(status: .satisfied, usesCellular: false, usesWiFi: true, usesEthernet: false)
        }
        return nil
    }
    static let reconnectTripName = "Test park loop"
    static let paceTripName = "Test straight drive"
    static let routeReplacementRequest = Notification.Name("com.n3mostudio.elsepin.validation.replace-route")
    static let unreadableTrips = Data("corrupt disposable trips".utf8)
    static let longName = "Test botanical garden walking route beside the riverside observatory and community orchard"
    static let updatedPinAddress = "12 Main Street, New York, NY 10019"
    static let shortPinLayoutAddress = "12 Oak Street"
    static let longPinLayoutAddress = "1842 North Observatory Promenade, Riverside Botanical Garden, West Conservatory Entrance, Lower Hudson River Waterfront, New York, NY 10019"
    static let addressOnlyPinLayoutPoint = CLLocationCoordinate2D(latitude: 40.761, longitude: -73.990)
    static let addressOnlyPinLayoutAddress = "940 North Observatory Promenade, Riverside Botanical Garden, Lower Hudson Waterfront, Reservoir Service Trail, North Arboretum Conservatory, Garden Education Annex, North River Research Campus, Manhattan Waterfront District, New York, NY 10019, Wren Gate"
    static let points = [CLLocationCoordinate2D(latitude: 40.768, longitude: -73.981),
                         CLLocationCoordinate2D(latitude: 40.770, longitude: -73.975),
                         CLLocationCoordinate2D(latitude: 40.779, longitude: -73.970)]
    static let searchCorridorPoints = [-73.981, -73.791, -73.601].map {
        CLLocationCoordinate2D(latitude: 40.770, longitude: $0)
    }
    static var route: PlannedRoute {
        if scenario == "route-search-coverage" {
            return makeRoute(searchCorridorPoints, start: "Test search start", end: "Test search destination")
        }
        return makeRoute(points, start: "Test garden entrance", end: longName)
    }
    static var replacementRoute: PlannedRoute {
        makeRoute(Array(points.reversed()), start: longName, end: "Test replacement destination")
    }
    private static func makeRoute(_ points: [CLLocationCoordinate2D], start: String, end: String) -> PlannedRoute {
        let track = RouteTrack(points.map { RoutePoint($0) })!
        return PlannedRoute(name: end,
            origin: RoutePlace(name: start, coordinate: points[0]),
            destination: RoutePlace(name: end, coordinate: points[2]),
            coordinates: points, track: track, source: .drawn, distance: track.length,
            notices: ["Synthetic test path only. These are not verified walking directions."],
            appleTravelTime: nil, instructions: [], calculatedAt: Date())
    }
    @MainActor static func prepare() {
        guard enabled, Bundle.main.bundleIdentifier == "com.n3mostudio.elsepin.validation" else {
            preconditionFailure("Disposable validation app must be launched explicitly by UI tests")
        }
        if scenario == "route-search-replacement" {
            // The test runner requests the transition while the native dialog is on screen.
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
                Task { @MainActor in
                    NotificationCenter.default.post(name: ValidationFixture.routeReplacementRequest, object: nil)
                }
            }, routeReplacementRequest.rawValue as CFString, nil, .deliverImmediately)
        }
        if scenario == "backup-settings", ProcessInfo.processInfo.arguments.contains("--preserve-backup-test-data") { return }
        if let files = nativeGPXFiles {
            if ProcessInfo.processInfo.arguments.contains("--preserve-gpx-test-data") { return }
            do { try ValidationNativeGPX.prepare(files) }
            catch { preconditionFailure("Could not seed disposable Files GPX: \(error)") }
        }
        if firstLaunch || drawnRoute, ProcessInfo.processInfo.arguments.contains("--preserve-everyday-test-data") { return }
        // The validation bundle has its own sandbox and no App Group entitlement.
        // Every launch clears only that disposable sandbox, never the shipping app.
        if scenario == "backup-settings" {
            let manager = FileManager.default
            let observation = ValidationBackupHarness.observedExportURL
            if manager.fileExists(atPath: observation.path) {
                do { try manager.removeItem(at: observation) }
                catch { preconditionFailure("Could not clear the old export observation: \(error)") }
            }
            do { try ValidationBackupHarness.prepareMalformedBackup() }
            catch { preconditionFailure("Could not stage malformed backup: \(error)") }
        }
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appendingPathComponent("Locus"))
        UserDefaults.standard.set(false, forKey: "locus.liveActivities")
        UserDefaults.standard.set(false, forKey: "locus.connectionAlerts")
        if scenario == "deleted-selection" {
            for index in (1...40).reversed() {
                _ = RecentlyDeletedStore.shared.keep(.place(BackupPlace(name: String(format: "Test deleted pin %02d", index),
                    latitude: points[1].latitude, longitude: points[1].longitude)))
            }
        }
        if nativeGPXRoundTrip {
            do { guard try ValidationNativeGPX.seedRoundTrip() else { preconditionFailure("Could not save disposable GPX export route") } }
            catch { preconditionFailure("Could not seed disposable GPX export route: \(error)") }
        } else if routeReconnect {
            guard TripLibrary().save(route: route, name: reconnectTripName, mode: .walk,
                                     speed: 1.4, smooth: false, favorite: true) else {
                preconditionFailure("Could not seed the disposable reconnect route")
            }
        } else if routePace {
            let straightPoints = [40.770, 40.785, 40.800].map {
                CLLocationCoordinate2D(latitude: $0, longitude: -73.981)
            }
            let straight = makeRoute(straightPoints, start: "Test drive start", end: "Test drive destination")
            guard TripLibrary().save(route: straight, name: paceTripName, mode: .drive,
                                     speed: 60, smooth: false, favorite: true) else {
                preconditionFailure("Could not seed the disposable pace route")
            }
        } else if scenario != "empty" && !firstLaunch && !drawnRoute {
            SavedPlace.save([SavedPlace(name: longName, latitude: points[1].latitude,
                longitude: points[1].longitude, favorite: true)], key: "locus.favorites")
            _ = TripLibrary().save(route: route, name: longName, mode: .walk,
                speed: 1.4, smooth: false, favorite: true)
        }
        if scenario == "pin-address-refresh" {
            SavedPlace.save([
                SavedPlace(name: "Neighboring pin", latitude: points[0].latitude + 0.00001, longitude: points[0].longitude,
                           address: "Neighbor's address"),
                SavedPlace(name: "My saved destination", latitude: points[0].latitude, longitude: points[0].longitude,
                           folder: "Trips", icon: SavedPlaceSymbol.star.rawValue, color: "mint", favorite: true, address: "Outdated address")
            ], key: "locus.favorites")
        }
        if scenario == "import-review" { AppDataWorkspace.defaults.set(Data("corrupt disposable pins".utf8),forKey:"locus.favorites") }
        if scenario == "import-review", ProcessInfo.processInfo.arguments.contains("--validated-recovery") {
            let current = SavedPlace(name: "Current saved place", latitude: 41, longitude: -72)
            let invalid = SavedPlace(name: "Duplicate saved place", latitude: 42, longitude: -72)
            let valid = SavedPlace(name: "Validated recovery place", latitude: 43, longitude: -72)
            do {
                let defaults = AppDataWorkspace.defaults
                let encoder = JSONEncoder()
                defaults.set(try encoder.encode([current]), forKey: "locus.favorites")
                defaults.set(try encoder.encode([invalid, invalid]), forKey: "locus.favorites.recovery")
                defaults.set(try encoder.encode([encoder.encode([valid])]), forKey: "locus.favorites.recovery.history")
            } catch { preconditionFailure("Could not seed recovery fixtures: \(error)") }
        }
        if scenario == "backup-unreadable-trips" {
            do { try unreadableTrips.write(to: AppDataWorkspace.file("Trips.json")) }
            catch { preconditionFailure("Could not seed unreadable trips: \(error)") }
        }
        if scenario == "home-solid-backup" {
            let backup = LibraryBackup(places: [
                BackupPlace(name: "Incoming duplicate pin", latitude: points[1].latitude, longitude: points[1].longitude),
                BackupPlace(name: "New backup pin", latitude: points[2].latitude, longitude: points[2].longitude)
            ], trips: [], preferences: nil).selecting([.places])
            do { UIPasteboard.general.string = try String(decoding: backup.encoded(), as: UTF8.self) }
            catch { preconditionFailure("Could not encode disposable clipboard backup: \(error)") }
        }
        if routeIdentityScenario {
            let library = TripLibrary()
            guard let saved = library.trips.first else { preconditionFailure("Missing disposable route") }
            library.move(saved, folder: "Route QA")
            if scenario == "route-identity-full" {
                let fillers = (1...49).map { index in
                    var trip = saved
                    trip.id = UUID(); trip.name = "Untouched route \(index)"
                    trip.favorite = index.isMultiple(of: 2); trip.folder = "Other routes"
                    return trip
                }
                do { guard try library.merge(fillers) else { preconditionFailure("Could not seed routes") } }
                catch { preconditionFailure("Invalid disposable routes: \(error)") }
            }
        }
    }
}

@main struct ValidationApp: App {
    init() { ValidationFixture.prepare() }
    var body: some Scene { WindowGroup { ValidationHost() } }
}

private struct ValidationHost: View {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @StateObject private var preferences = SessionPreferences.shared
    @StateObject private var privacy = AppPrivacyController()
    @StateObject private var updates = AppUpdateController()
    @StateObject private var reset = AppResetController()
    @StateObject private var library = TripLibrary()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false
    @AppStorage(SetupGate.deferredKey) private var setupDeferred = false
    @State private var shortcut: LocusShortcut?
    @State private var details = false
    @State private var showSearch = false
    @State private var started = false
    @State private var runSession = false
    @State private var permissionsReady = false
    @State private var routeLibrarySnapshot = ""
    @State private var routePlaybackTrace = "[]"
    @State private var nativeGPXDiskReport = ""
    @State private var pinAddressReport = ""
    @State private var stalePinDraft: PinDraft?

    private func checkSavedAddressRefresh() {
        let coordinate = ValidationFixture.points[0]
        let address = ValidationFixture.updatedPinAddress
        let saved = SavedPlace.load(key: "locus.favorites")
        let recents = SavedPlace.load(key: "locus.recents")
        let expected = SavedPlace(name: "My saved destination", latitude: coordinate.latitude, longitude: coordinate.longitude,
                                  folder: "Trips", icon: SavedPlaceSymbol.star.rawValue, color: "mint", favorite: true, address: address)
        guard session.previewSpotName == nil else { pinAddressReport = "The previous explicit label was retained"; return }
        guard saved.count == 2, saved.contains(expected) else { pinAddressReport = "Saved pin metadata changed"; return }
        guard saved.first(where: { $0.id != expected.id })?.address == "Neighbor's address" else {
            pinAddressReport = "Nearby pin address changed"; return
        }
        guard recents.first?.id == expected.id, recents.first?.address == address else { pinAddressReport = "Recent address is stale"; return }
        pinAddressReport = "Saved and recent addresses refreshed"
    }
    private var sessionScenario: Bool { ValidationFixture.routeIdentityScenario || ["moving", "paused", "connecting", "failed", "map-pins", "route-search-replacement", "route-search-coverage", "route-camera"].contains(ValidationFixture.scenario) }

    private func replaceRoute() async {
        guard session.routeActive else { return }
        session.stopRoute()
        if session.journey != nil {
            // Let the production worker settle any pending location write.
            for await journey in session.$journey.values where journey == nil { break }
        }
        guard !Task.isCancelled else { return }
        session.followRoute(ValidationFixture.replacementRoute, pairing: pairing, smoothing: false)
    }

    var body: some View {
        Group {
            if ValidationFixture.scenario == "reset-review" { NavigationStack { List { AppResetSection() } } }
            else if ValidationFixture.scenario == "joystick-presets" { ValidationJoystickPresets() }
            else if ["route-editing", "route-editing-mixed"].contains(ValidationFixture.scenario) { ValidationRouteHarness() }
            else if ValidationFixture.scenario == "import-review" { ValidationImportHarness() }
            else if ValidationFixture.scenario.hasPrefix("backup-") { ValidationBackupHarness() }
            else if ValidationFixture.scenario == "deleted-selection" { NavigationStack { RecentlyDeletedView() } }
            else if ValidationFixture.firstLaunch && !setupComplete && !setupDeferred {
                SetupFlowView(initialStep: SetupGate.initialStep(hasPairingFile: pairing.hasPairingFile), onFinished: {
                    SetupGate.markComplete()
                    setupComplete = true
                    setupDeferred = false
                }, onSkip: {
                    SetupGate.markDeferred()
                    setupDeferred = true
                })
            }
            else { RootView(incomingShortcut: $shortcut, incomingSessionDetails: $details) }
        }
            .modifier(AppearancePresentation())
            .frame(maxWidth: ProcessInfo.processInfo.arguments.contains("--narrow") ? 320 : .infinity)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                Text("SIMULATOR TEST DATA")
                    .accessibilityIdentifier("validation.banner")
                if ValidationFixture.routeIdentityScenario {
                    Button("Read route library") {
                        let reloaded = TripLibrary()
                        if let error = reloaded.error { routeLibrarySnapshot = "Library reload failed: \(error)" }
                        else if let data = try? JSONEncoder().encode(reloaded.trips) {
                            routeLibrarySnapshot = String(decoding: data, as: UTF8.self)
                        }
                    }.accessibilityIdentifier("validation.readRouteLibrary")
                    Text(routeLibrarySnapshot).lineLimit(1)
                        .accessibilityIdentifier("validation.routeLibrarySnapshot")
                }
                if ValidationFixture.routePace {
                    Button {
                        routePlaybackTrace = LocationEngine.playbackTrace()
                    } label: {
                        Text("Read playback trace").frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("validation.readPlaybackTrace")
                    Text("Adapter confirmations")
                        .accessibilityLabel(routePlaybackTrace)
                        .accessibilityIdentifier("validation.playbackTrace")
                }
                if ValidationFixture.scenario == "import-root" {
                    Button("Open validation GPX") {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("root-flow.gpx")
                        try? Data(ValidationImportHarness.valid.utf8).write(to:url)
                        NotificationCenter.default.post(name:.locusImportGPX,object:url)
                    }.accessibilityIdentifier("validation.openGPX")
                }
                if let files = ValidationFixture.nativeGPXFiles {
                    ValidationFixtureExporter(files: ValidationNativeGPX.exportableFiles(for: files),
                        onExported: ValidationNativeGPX.observeExport)
                }
                if ValidationFixture.nativeGPXRoundTrip || ValidationFixture.nativeGPXFiles == .sizes
                    || ValidationFixture.nativeGPXFiles == .genericData {
                    Button("Read GPX routes from disk") {
                        do {
                            if ValidationFixture.nativeGPXRoundTrip {
                                nativeGPXDiskReport = try ValidationNativeGPX.roundTripDiskReport()
                            } else if let files = ValidationFixture.nativeGPXFiles {
                                nativeGPXDiskReport = try ValidationNativeGPX.diskReport(for: files)
                            }
                        }
                        catch { nativeGPXDiskReport = error.localizedDescription }
                    }.accessibilityIdentifier("validation.readGPXDiskReport")
                    Text(nativeGPXDiskReport).lineLimit(1)
                        .accessibilityIdentifier("validation.gpxDiskReport")
                }
                if ValidationFixture.scenario == "held-location" {
                    Text("\(session.commandGeneration)")
                        .accessibilityIdentifier("validation.commandGeneration")
                }
                if ValidationFixture.scenario == "home-solid-pin-layout" {
                    HStack {
                        Button("Select short address") { session.selectPin(ValidationFixture.points[0]) }
                        Button("Select long address") { session.selectPin(ValidationFixture.points[2]) }
                        if ValidationFixture.largeText {
                            Button("Select address only") { session.selectPin(ValidationFixture.addressOnlyPinLayoutPoint) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                if ValidationFixture.scenario == "pin-address-refresh" {
                    HStack {
                        Button(action: checkSavedAddressRefresh) {
                            Text("Check saved address refresh").frame(minHeight: 44).contentShape(Rectangle())
                        }
                        Button {
                            guard var snapshot = session.savedPin(at: ValidationFixture.points[0]) else { return }
                            snapshot.address = "Outdated address"
                            pinAddressReport = ""
                            stalePinDraft = PinDraft(place: snapshot, center: snapshot.coordinate)
                        } label: {
                            Text("Edit pin from old snapshot").frame(minHeight: 44).contentShape(Rectangle())
                        }
                    }
                    Text(pinAddressReport).accessibilityIdentifier("validation.pinAddressReport")
                }
                if ValidationFixture.scenario == "route-camera", let simulated = session.simulated {
                    Text(simulated.latitude < 40 ? "Previous location held" : "Route location accepted")
                        .accessibilityIdentifier("validation.routeCameraLocation")
                    if simulated.latitude < 40, session.activeRoute == nil {
                        Button("Start route fixture") {
                            _ = session.followRoute(ValidationFixture.route, pairing: pairing, smoothing: false)
                        }.accessibilityIdentifier("validation.startCameraRoute").frame(minHeight: 44)
                    }
                }
                if sessionScenario && !runSession {
                    Button("Start validation session") { runSession = true }
                        .accessibilityIdentifier("validation.start")
                        .disabled(!permissionsReady)
                        .frame(minHeight: 44)
                }
                }.font(.system(size: 9, weight: .bold))
                    .padding(2).background(.yellow).foregroundStyle(.black)
            }
            .sheet(isPresented: $showSearch) {
                RoutePlaceSearchSheet(title: "Test search", onChoose: { _ in showSearch = false })
                    .environmentObject(library)
            }
            .sheet(item: $stalePinDraft) { draft in PinEditor(draft: draft) }
            .environmentObject(session).environmentObject(session.recovery)
            .environmentObject(session.reliability).environmentObject(pairing)
            .environmentObject(preferences).environmentObject(privacy)
            .environmentObject(updates).environmentObject(reset)
            .environmentObject(library)
            .environment(\.shiftVisualStyle, preferences.visualStyle)
            .environment(\.shiftIconDesign, preferences.iconSelection.design)
            .environment(\.stopNetworkPathOverride, ValidationFixture.stopNetworkPath)
            .environment(\.dynamicTypeSize, ValidationFixture.largeText ? .accessibility5 : .large)
            .preferredColorScheme(ValidationFixture.dark ? .dark : .light)
            .tint(ShiftPalette.color(.accent, style: preferences.visualStyle))
            .onReceive(NotificationCenter.default.publisher(for: ValidationFixture.routeReplacementRequest)) { _ in
                Task { await replaceRoute() }
            }
            .task {
                guard !started else { return }; started = true
                preferences.liveActivities = false; preferences.connectionAlerts = false
                // XCTest changes the simulator's real Accessibility settings.
                // Keep glass requested so Reduce Transparency must supply the fallback.
                preferences.glassPanel = !ValidationFixture.scenario.hasPrefix("home-solid")
                // Settle the real system permission before timing the synthetic
                // connecting state. This never changes production permission flow.
                if sessionScenario || ValidationFixture.routeReconnect || ValidationFixture.routePace {
                    _ = await SessionNotifications.shared.requestPermission()
                    permissionsReady = true
                }
                if ValidationFixture.scenario == "pin-address-refresh" {
                    let destination = ValidationFixture.points[0]
                    let adjacent = CLLocationCoordinate2D(latitude: destination.latitude + 0.00001, longitude: destination.longitude)
                    session.pushNamedRecent(name: "My saved destination", coordinate: destination)
                    session.selectPin(adjacent)
                    let namedNeighbor = session.nameSpot("Explicit neighboring label", at: RoutePoint(adjacent),
                        preview: true, context: session.namingContext)
                    precondition(namedNeighbor)
                    session.selectPin(destination)
                } else if !sessionScenario && !ValidationFixture.firstLaunch && !ValidationFixture.routeReconnect
                            && !ValidationFixture.routePace && !ValidationFixture.scenario.hasPrefix("home-") {
                    session.selectPin(ValidationFixture.points[0], name: "Test garden entrance")
                }
                if ValidationFixture.scenario == "pin-adjustment" {
                    preferences.mapPinSize = 48
                    preferences.mapPinVisibilityMiles = 20
                    session.selectPin(ValidationFixture.points[1], name: ValidationFixture.longName)
                }
                if ValidationFixture.scenario == "search" { showSearch = true }
            }
            .task(id: runSession) {
                guard runSession else { return }
                    if ValidationFixture.scenario == "route-camera" {
                        _ = session.teleport(to: CLLocationCoordinate2D(latitude: 37.779, longitude: -122.419), pairing: pairing)
                        return
                    }
                    if ValidationFixture.routeIdentityScenario,
                       ValidationFixture.scenario != "route-identity-unsaved",
                       let trip = library.trips.first(where: { $0.name == ValidationFixture.longName }),
                       let route = trip.plannedRoute {
                        if session.followRoute(route, pairing: pairing, smoothing: trip.smoothMovement) {
                            session.rememberSavedTrip(trip.id, routeID: route.id)
                        }
                    } else {
                        _ = session.followRoute(ValidationFixture.route, pairing: pairing, smoothing: false)
                    }
                    if ValidationFixture.scenario == "paused" {
                        for _ in 0..<50 where session.effectivePhase != .active {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        session.toggleRoutePause()
                    }
            }
    }
}
