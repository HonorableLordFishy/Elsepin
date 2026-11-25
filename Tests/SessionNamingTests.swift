import XCTest
@testable import SessionPresentation

final class SessionNamingTests: XCTestCase {
    let spot = RoutePoint(latitude: 37, longitude: -122)

    func testNameStaysAtItsSpotAndChangesWhenMovingAway() throws {
        let name = try XCTUnwrap(SessionSpotName("Home", at: spot))
        XCTAssertEqual(name.display(at: spot), "Home")
        XCTAssertNil(name.display(at: RoutePoint(latitude: 37.001, longitude: -122)))
        // Returning to the same place restores its actual label.
        XCTAssertEqual(name.display(at: spot), "Home")
    }

    func testSmallCoordinateChangesDoNotImmediatelyLoseName() throws {
        let name = try XCTUnwrap(SessionSpotName("Coffee shop", at: spot))
        XCTAssertEqual(name.display(at: RoutePoint(latitude: 37.00004, longitude: -122)), "Coffee shop")
        XCTAssertNil(name.display(at: RoutePoint(latitude: 37.00005, longitude: -122)))
        XCTAssertNil(name.display(at: RoutePoint(latitude: .nan, longitude: -122)))
    }

    func testExactSavedNameWinsOverAdjacentExplicitAndRouteNames() throws {
        let adjacent = RoutePoint(latitude: 37.00001, longitude: -122)
        let explicit = try XCTUnwrap(SessionSpotName("Adjacent explicit label", at: adjacent))
        let route = [(point: adjacent, name: "Adjacent route stop")]
        XCTAssertEqual(SessionSpotName.preferredPlaceLabel(at: spot, explicit: [explicit], route: route,
                                                            exactSaved: "Exact saved pin"), "Exact saved pin")
        XCTAssertEqual(SessionSpotName.preferredPlaceLabel(at: spot, explicit: [explicit], route: route,
                                                            exactSaved: nil), explicit.name)
    }

    func testExactRouteAndExplicitNamesKeepTheirPriority() throws {
        let adjacent = RoutePoint(latitude: 37.00001, longitude: -122)
        let nearbyLabel = try XCTUnwrap(SessionSpotName("Adjacent explicit label", at: adjacent))
        let exactLabel = try XCTUnwrap(SessionSpotName("Exact explicit label", at: spot))
        let route = [(point: adjacent, name: "Adjacent route stop"), (point: spot, name: "Exact route stop")]
        XCTAssertEqual(SessionSpotName.preferredPlaceLabel(at: spot, explicit: [nearbyLabel], route: route,
                                                            exactSaved: "Exact saved pin"), "Exact route stop")
        XCTAssertEqual(SessionSpotName.preferredPlaceLabel(at: spot, explicit: [nearbyLabel, exactLabel], route: route,
                                                            exactSaved: "Exact saved pin"), exactLabel.name)
    }

    func testSelectedPinUsesExactNamesWithoutInheritingAdjacentLabels() throws {
        let adjacent = RoutePoint(latitude: 37.00001, longitude: -122)
        let explicit = try XCTUnwrap(SessionSpotName("Adjacent explicit label", at: adjacent))
        let route = [(point: adjacent, name: "Adjacent route stop")]

        XCTAssertNil(SessionSpotName.preferredPlaceLabel(at: spot, explicit: [explicit], route: route,
                                                         exactSaved: nil, allowsNearby: false))
        XCTAssertEqual(SessionSpotName.preferredPlaceLabel(at: spot, explicit: [explicit], route: route,
                                                            exactSaved: nil, exactRemembered: "Selected result",
                                                            allowsNearby: false), "Selected result")
    }

    func testWhitespaceEmptyNamesAndLengthAreHandled() throws {
        XCTAssertNil(SessionSpotName(" \n\t ", at: spot))
        XCTAssertNil(SessionSpotName("Home", at: RoutePoint(latitude: 99, longitude: 0)))
        XCTAssertEqual(SessionSpotName("  My\n coffee   shop  ", at: spot)?.name, "My coffee shop")
        let name = try XCTUnwrap(SessionSpotName(String(repeating: "🏡", count: 100), at: spot))
        XCTAssertEqual(name.name.count, 60)
    }

    func testActivityPrivacyCanOmitNameAndNeverNeedsAnchorCoordinates() throws {
        let now = Date()
        let name = try XCTUnwrap(SessionSpotName("Home", at: spot))
        var state = SessionSnapshot(phase: .active, startedAt: now, lastConfirmedAt: now,
                                    expiresAt: now.addingTimeInterval(12), place: nil, lowPower: true)
        state.islandPlace = name.display(at: spot)
        let data = try JSONEncoder().encode(state)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["place"])
        XCTAssertEqual(object["islandPlace"] as? String, "Home")
        XCTAssertFalse(text.contains("latitude"))
        XCTAssertFalse(text.contains("longitude"))
        XCTAssertLessThan(data.count, 4096)
        state.islandPlace = nil
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(state), as: UTF8.self).contains("Home"))
    }

    func testNewInstallDefaultsToSmoothMovementOff() throws {
        let suite = "Shift.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(MovementDefaults.loadSmoothMovement(from: defaults))
        XCTAssertTrue(defaults.bool(forKey: MovementDefaults.migrationKey))
    }

    func testUpgradeResetsOldDefaultOnceAndThenHonorsExplicitChoice() throws {
        let suite = "Shift.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: MovementDefaults.smoothKey)
        XCTAssertFalse(MovementDefaults.loadSmoothMovement(from: defaults))
        defaults.set(true, forKey: MovementDefaults.smoothKey)
        XCTAssertTrue(MovementDefaults.loadSmoothMovement(from: defaults))
        defaults.set(false, forKey: MovementDefaults.smoothKey)
        XCTAssertFalse(MovementDefaults.loadSmoothMovement(from: defaults))
    }
}
