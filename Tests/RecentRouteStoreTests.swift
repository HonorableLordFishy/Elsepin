import XCTest
@testable import SessionPresentation

final class RecentRouteStoreTests: XCTestCase {
    private let legacyKey = "locus.recentRoutes"
    private let legacyAvailableKey = "locus.recentRoutesAvailable"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMigratesLegacyHistoryOnlyAfterWritingItsReplacement() throws {
        try withWorkspace { workspace in
            let context = workspace.context
            let routes = DevModeDataset.make(at: now).recentRoutes
            let legacy = try JSONEncoder().encode(routes)
            context.defaults.set(legacy, forKey: legacyKey)
            context.defaults.set(true, forKey: legacyAvailableKey)

            let file = context.file(RecentRouteStore.relativePath)
            let folder = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: context.directory, withIntermediateDirectories: true)
            try Data("blocked".utf8).write(to: folder)

            let store = RecentRouteStore(workspace: workspace)
            XCTAssertEqual(store.load(), routes)
            XCTAssertEqual(context.defaults.data(forKey: legacyKey), legacy)
            XCTAssertTrue(context.defaults.bool(forKey: legacyAvailableKey))

            try FileManager.default.removeItem(at: folder)
            XCTAssertEqual(store.load(), routes)
            XCTAssertEqual(try Data(contentsOf: file), legacy)
            XCTAssertNil(context.defaults.object(forKey: legacyKey))
            XCTAssertNil(context.defaults.object(forKey: legacyAvailableKey))
            XCTAssertEqual(RecentRouteStore(workspace: workspace).load(), routes)
        }
    }

    func testClearDrainsEarlierWritesAndPreventsLegacyFallback() throws {
        try withWorkspace { workspace in
            let context = workspace.context
            let routes = DevModeDataset.make(at: now).recentRoutes
            let store = RecentRouteStore(workspace: workspace)
            store.save(routes)
            try store.clear()

            // Simulate legacy defaults surviving until after a successful clear.
            context.defaults.set(try JSONEncoder().encode(routes), forKey: legacyKey)
            context.defaults.set(true, forKey: legacyAvailableKey)

            XCTAssertEqual(RecentRouteStore(workspace: workspace).load(), [])
            XCTAssertEqual(try Data(contentsOf: context.file(RecentRouteStore.relativePath)), Data("[]".utf8))
            XCTAssertNil(context.defaults.object(forKey: legacyKey))
            XCTAssertNil(context.defaults.object(forKey: legacyAvailableKey))
        }
    }

    func testUnavailableLegacyHistoryStaysCleared() throws {
        try withWorkspace { workspace in
            let defaults = workspace.context.defaults
            defaults.set(try JSONEncoder().encode(DevModeDataset.make(at: now).recentRoutes), forKey: legacyKey)
            defaults.set(false, forKey: legacyAvailableKey)

            let store = RecentRouteStore(workspace: workspace)
            XCTAssertEqual(store.load(), [])
            XCTAssertNil(defaults.object(forKey: legacyKey))
            XCTAssertNil(defaults.object(forKey: legacyAvailableKey))
        }
    }

    func testFullSizeHistorySurvivesRelaunchAndDemoClear() throws {
        try withWorkspace { workspace in
            let personal = workspace.context
            let demoRoutes = DevModeDataset.make(at: now).recentRoutes
            var imported = try XCTUnwrap(demoRoutes.first)
            imported.trip.source = .gpx
            imported.trip.instructions = []
            imported.trip.stops = []
            imported.trip.travelSections = nil
            imported.trip.points = (0..<100_000).map {
                RoutePoint(latitude: 40, longitude: -74 + Double($0) / 100_000)
            }
            let routes = RecentRoute.kept([imported], retention: .forever, enabled: true, now: now)
            XCTAssertEqual(routes.first?.trip.points.count, 100_000)
            let store = RecentRouteStore(workspace: workspace)
            store.save(routes)

            try workspace.activateDemo { try RecentRouteStore.seed(demoRoutes, in: $0) }
            let demo = workspace.context
            XCTAssertEqual(store.load(), demoRoutes)
            XCTAssertNil(demo.defaults.object(forKey: legacyKey))
            try store.clear()
            XCTAssertEqual(store.load(), [])
            workspace.deactivateDemo()

            let reopened = AppDataWorkspace(personal: personal.defaults, directory: personal.directory)
            XCTAssertEqual(RecentRouteStore(workspace: reopened).load(), routes)
            XCTAssertNil(personal.defaults.object(forKey: legacyKey))
            XCTAssertNil(personal.defaults.object(forKey: legacyAvailableKey))
        }
    }

    private func withWorkspace(_ test: (AppDataWorkspace) throws -> Void) throws {
        let suite = "recent-route-store." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let workspace = AppDataWorkspace(personal: defaults, directory: directory, suitePrefix: suite)
        defer {
            workspace.deactivateDemo()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try test(workspace)
    }
}
