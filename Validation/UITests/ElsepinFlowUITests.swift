import CoreFoundation
import XCTest

final class ElsepinFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var restoreAccessibility = false
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground {
            capture("final-" + name)
            app.terminate()
        }
        // XCTest can abort through Objective-C when continueAfterFailure is false;
        // a Swift defer in the test method is not a reliable cleanup boundary.
        if restoreAccessibility {
            configureAccessibility(false)
            restoreAccessibility = false
        }
    }
    private func launch(_ scenario: String, large: Bool = false, dark: Bool = false, fallback: Bool = false, narrow: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        if narrow { app.launchArguments.append("--narrow") }
        if large { app.launchArguments.append("--large-text") }
        if dark { app.launchArguments.append("--dark") }
        if fallback { app.launchArguments.append("--accessibility-fallback") }
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts["validation.banner"].waitForExistence(timeout: 20))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "Keep Only While Using", "Change to Always Allow"] {
            let button = springboard.buttons[label]
            if button.exists { button.tap() }
        }
        if scenario.hasPrefix("route-identity-") || ["moving", "paused", "connecting", "failed", "map-pins", "route-search-replacement", "route-camera"].contains(scenario) {
            let start = app.buttons["validation.start"]
            if !start.isEnabled, springboard.buttons["Allow"].waitForExistence(timeout: 5) {
                springboard.buttons["Allow"].tap()
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            start.tap()
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testResetReviewShowsLossAndRetentionBeforeConfirming() {
        launch("reset-review", dark: true, narrow: false)
        app.buttons["Wipe everything…"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wipe data, keep setup")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pins, routes, areas, history and Recently Deleted."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pairing, tunnel address and setup progress."].exists)
        capture("reset-review-keep-setup")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Wipe everything"].waitForExistence(timeout: 5))
    }

    func testJoystickUsesUsualSpeedsBetweenEditsAndRestarts() {
        launch("joystick-presets")
        XCTAssertTrue(app.staticTexts["Joystick presets passed"].waitForExistence(timeout: 20),
                      app.debugDescription)
    }

    private func launchRoutes(large: Bool = false, mixedLeg: Bool = false) {
        launch(mixedLeg ? "route-editing-mixed" : "route-editing", large: large, narrow: false)
        let report = app.staticTexts["validation.routeRules"]
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Passed'"), object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 20), .completed, report.label)
    }

    private func routeControl(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<9 {
            var bottom = app.frame.maxY - 60
            for label in ["Show route", "Save route & preview"] {
                let action = app.buttons[label]
                if action.exists && action.isHittable { bottom = min(bottom, action.frame.minY - 24) }
            }
            let top = app.frame.minY + 150
            // XCTest can call a partially covered row hittable even though
            // its center lies beneath the sticky Show route button.
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return element }
            let isAbove = element.exists && element.frame.minY < top
            if app.launchArguments.contains("--large-text") {
                // The fixed Show route footer can reach the usual swipe start.
                // Stay in the exposed scroll band and outside the preview map.
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let x = app.frame.width - 8
                let upper = origin.withOffset(CGVector(dx: x, dy: top - app.frame.minY + 24))
                let lower = origin.withOffset(CGVector(dx: x, dy: bottom - app.frame.minY - 12))
                (isAbove ? upper : lower).press(forDuration: 0.05, thenDragTo: isAbove ? lower : upper)
                continue
            }
            // Start on the list below the map, not inside the pannable preview.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: isAbove ? 0.35 : 0.77))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: isAbove ? 0.77 : 0.35)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Unreachable route control: \(element)")
        return element
    }

    private func savedSnapshot() throws -> [String: Any] {
        app.buttons["Read saved data"].tap()
        let text = app.staticTexts["validation.savedSnapshot"].label
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(value["loadError"] as? String, "")
        return value
    }

    private func savedTrip() throws -> [String: Any] {
        try XCTUnwrap(savedSnapshot()["saved"] as? [String: Any])
    }

    private func closeRoute() {
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Read saved data"].waitForExistence(timeout: 5))
    }

    private func saveRouteChanges() {
        routeControl(app.buttons["Save changes"]).tap()
        XCTAssertTrue(app.alerts["Save trip"].waitForExistence(timeout: 5))
        app.alerts["Save trip"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Trip saved with its place names and stops."].waitForExistence(timeout: 5))
    }

    @discardableResult private func setVisibleSpeed(_ mode: String, position: CGFloat) throws -> Double {
        let slider = routeControl(app.sliders["\(mode) speed in miles per hour"])
        slider.adjust(toNormalizedSliderPosition: position)
        let text = try XCTUnwrap(slider.value as? String)
        return try XCTUnwrap(Double(text.components(separatedBy: " ")[0]))
    }

    func testUsualSpeedsApplyToNewRoutesAndPersist() throws {
        launchRoutes()
        app.buttons["Usual speeds"].tap()
        // XCUITest's normalized slider drag stops short of the track ends, so this
        // check uses a mid-range usual speed; RouteInteractionTests covers the bounds.
        let walk = try setVisibleSpeed("Walk", position: 0.9)
        XCTAssertGreaterThan(walk, 1)
        XCTAssertLessThan(walk, 6)
        capture("24-settings-walk-usual-speed")
        app.buttons["Done"].tap()
        XCTAssertEqual(try XCTUnwrap(savedSnapshot()["usualWalk"] as? Double), walk, accuracy: 0.05)
        for action in ["New drawn route", "New planned route"] {
            app.buttons[action].tap()
            let save = app.buttons["Save route & preview"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            capture("25-" + action)
            save.tap()
            XCTAssertTrue(app.buttons["Read saved data"].waitForExistence(timeout: 5))
            let saved = try savedTrip()
            XCTAssertEqual(try XCTUnwrap(saved["speedMPH"] as? Double), walk, accuracy: 0.05)
            XCTAssertEqual(saved["mode"] as? String, "walk")
            app.buttons["Reopen last saved route"].tap()
            closeRoute()
            XCTAssertEqual(try XCTUnwrap(savedSnapshot()["draftSpeed"] as? Double), walk, accuracy: 0.05)
        }
        // A previously saved route must keep its assigned speed, not take 6.
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        XCTAssertTrue(app.staticTexts["1.4 mph"].exists)
        capture("26-existing-speed-preserved")
    }

    func testSavedLegModeAndCustomSpeedsSurviveReopening() throws {
        launchRoutes()
        let snapshotBefore = try savedSnapshot()
        let before = try XCTUnwrap(snapshotBefore["saved"] as? [String: Any])
        let requestsBefore = try XCTUnwrap(snapshotBefore["directionsRequests"] as? Int)
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        app.buttons["Drive"].tap()
        XCTAssertTrue(app.staticTexts["85.0 mph"].exists)
        XCTAssertTrue(app.staticTexts["Walk → Drive"].exists)
        let keepPath = routeControl(app.buttons["Keep path"])
        XCTAssertTrue(keepPath.isSelected)
        XCTAssertTrue(app.buttons["New directions"].isHittable)
        capture("leg-walk-to-drive-inline")
        keepPath.tap()
        let drive = try setVisibleSpeed("Drive", position: 0.5)
        XCTAssertGreaterThan(drive, 1); XCTAssertLessThan(drive, 85)
        capture("27-custom-drive-leg")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Plan a route"].waitForExistence(timeout: 5))
        capture("27b-kept-path-before-second-leg")
        routeControl(app.buttons["Movement to Test pond"]).tap()
        app.buttons["E-bike"].tap()
        XCTAssertTrue(app.staticTexts["31.0 mph"].exists)
        let bike = try setVisibleSpeed("E-bike", position: 0.35)
        app.buttons["Done"].tap()
        saveRouteChanges()
        closeRoute()
        let snapshotAfter = try savedSnapshot()
        let saved = try XCTUnwrap(snapshotAfter["saved"] as? [String: Any])
        XCTAssertEqual(snapshotAfter["directionsRequests"] as? Int, requestsBefore)
        let originalPoints = try XCTUnwrap(before["points"] as? [[String: Any]])
        let keptPoints = try XCTUnwrap(saved["points"] as? [[String: Any]])
        XCTAssertEqual(keptPoints as NSArray, originalPoints as NSArray)
        XCTAssertEqual(saved["id"] as? String, before["id"] as? String)
        let sections = try XCTUnwrap(saved["travelSections"] as? [[String: Any]])
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0]["mode"] as? String, "drive")
        XCTAssertEqual(try XCTUnwrap(sections[0]["speedMPH"] as? Double), drive, accuracy: 0.11)
        XCTAssertEqual(sections[1]["mode"] as? String, "eBike")
        XCTAssertEqual(try XCTUnwrap(sections[1]["speedMPH"] as? Double), bike, accuracy: 0.11)
        app.buttons["Reopen last saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        XCTAssertEqual(try XCTUnwrap(Double((app.sliders.firstMatch.value as? String ?? "").components(separatedBy: " ")[0])), drive, accuracy: 0.11)
        capture("28-reopened-custom-drive-speed")
        app.buttons["Done"].tap()
        routeControl(app.buttons["Movement to Test pond"]).tap()
        XCTAssertEqual(try XCTUnwrap(Double((app.sliders.firstMatch.value as? String ?? "").components(separatedBy: " ")[0])), bike, accuracy: 0.11)
        capture("29-reopened-custom-ebike-speed")
    }

    func testInlineLegPathChoiceResetsAndBackDiscardsAtLargestText() throws {
        launchRoutes(large: true)
        let requestsBefore = try XCTUnwrap(savedSnapshot()["directionsRequests"] as? Int)
        app.buttons["Open saved route"].tap()
        let previewHeading = app.staticTexts["Route preview"]
        let searchAroundPreview = app.buttons["Search this area"]
        XCTAssertTrue(previewHeading.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(searchAroundPreview.frame.minY, previewHeading.frame.maxY)
        capture("route-preview-largest-text")
        let moveToCafe = app.buttons["Movement to Test cafe"]
        routeControl(moveToCafe).tap()
        let drive = app.buttons["Drive"]
        let walk = app.buttons["Walk"]
        let keepPath = app.buttons["Keep path"]
        let newDirections = app.buttons["New directions"]

        routeControl(drive).tap()
        XCTAssertTrue(routeControl(keepPath).isSelected)
        XCTAssertFalse(app.segmentedControls.buttons["Keep path"].exists)
        capture("leg-walk-to-drive-inline-largest-text")
        routeControl(newDirections).tap()
        XCTAssertTrue(newDirections.isSelected)
        XCTAssertGreaterThanOrEqual(keepPath.frame.height, 44)
        // Adjacent rows can report their shared edge with different floating-point rounding.
        XCTAssertGreaterThanOrEqual(newDirections.frame.minY + 0.001, keepPath.frame.maxY)
        let scopeNote = app.staticTexts["Recalculates the whole route through your stops."]
        XCTAssertTrue(routeControl(scopeNote).isHittable)
        capture("leg-walk-to-drive-inline-largest-text-scrolled")

        routeControl(walk).tap()
        XCTAssertTrue(newDirections.waitForNonExistence(timeout: 5))
        routeControl(drive).tap()
        XCTAssertTrue(routeControl(keepPath).isSelected)
        routeControl(newDirections).tap()
        XCTAssertTrue(newDirections.isSelected)
        let back = app.navigationBars["Leg movement"].buttons.matching(NSPredicate(format: "label != 'Done'")).firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.navigationBars["Plan a route"].waitForExistence(timeout: 5))

        routeControl(moveToCafe).tap()
        XCTAssertTrue(walk.isSelected)
        XCTAssertFalse(newDirections.exists)
        back.tap()
        closeRoute()
        XCTAssertEqual(try savedSnapshot()["directionsRequests"] as? Int, requestsBefore)
    }

    func testInlineNewLegDirectionsRecalculatesOnceAndPreservesSavedStops() throws {
        launchRoutes()
        let snapshotBefore = try savedSnapshot()
        let before = try XCTUnwrap(snapshotBefore["saved"] as? [String: Any])
        let requestsBefore = try XCTUnwrap(snapshotBefore["directionsRequests"] as? Int)
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        app.buttons["Drive"].tap()
        let newDirections = routeControl(app.buttons["New directions"])
        newDirections.tap()
        XCTAssertTrue(newDirections.isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Plan a route"].waitForExistence(timeout: 5))
        saveRouteChanges()
        closeRoute()

        let snapshotAfter = try savedSnapshot()
        let saved = try XCTUnwrap(snapshotAfter["saved"] as? [String: Any])
        XCTAssertEqual(snapshotAfter["directionsRequests"] as? Int, requestsBefore + 1)
        XCTAssertEqual(snapshotAfter["count"] as? Int, snapshotBefore["count"] as? Int)
        XCTAssertEqual(saved["id"] as? String, before["id"] as? String)
        let sections = try XCTUnwrap(saved["travelSections"] as? [[String: Any]])
        XCTAssertEqual(sections.map { $0["mode"] as? String }, ["drive", "walk", "walk"])
        let originalStops = try XCTUnwrap(before["stops"] as? [[String: Any]])
        let savedStops = try XCTUnwrap(saved["stops"] as? [[String: Any]])
        XCTAssertEqual(savedStops.count, originalStops.count)
        for (newStop, oldStop) in zip(savedStops, originalStops) {
            XCTAssertEqual(newStop["id"] as? String, oldStop["id"] as? String)
            XCTAssertEqual(newStop["name"] as? String, oldStop["name"] as? String)
            XCTAssertEqual(newStop["waitSeconds"] as? Double, oldStop["waitSeconds"] as? Double)
        }
    }

    func testMixedLegUsesIncomingSettingsAndUnchangedDonePreservesSections() throws {
        launchRoutes(mixedLeg: true)
        let snapshotBefore = try savedSnapshot()
        let before = try XCTUnwrap(snapshotBefore["saved"] as? [String: Any])
        let originalSections = try XCTUnwrap(before["travelSections"] as? [[String: Any]])
        XCTAssertEqual(originalSections.map { $0["mode"] as? String }, ["walk", "drive", "walk", "walk"])
        let requestsBefore = try XCTUnwrap(snapshotBefore["directionsRequests"] as? Int)

        app.buttons["Open saved route"].tap()
        let moveToCafe = app.buttons["Movement to Test cafe"]
        routeControl(moveToCafe).tap()
        XCTAssertTrue(app.buttons["Drive"].isSelected)
        XCTAssertEqual(app.sliders["Drive speed in miles per hour"].value as? String, "23.0 mph")
        app.buttons["Done"].tap()
        saveRouteChanges()
        closeRoute()
        let unchanged = try savedSnapshot()
        XCTAssertEqual(unchanged["directionsRequests"] as? Int, requestsBefore)
        let saved = try XCTUnwrap(unchanged["saved"] as? [String: Any])
        let savedSections = try XCTUnwrap(saved["travelSections"] as? [[String: Any]])
        XCTAssertEqual(savedSections as NSArray, originalSections as NSArray)

        app.buttons["Open saved route"].tap()
        routeControl(moveToCafe).tap()
        app.buttons["Walk"].tap()
        XCTAssertTrue(app.staticTexts["Drive → Walk"].exists)
        routeControl(app.buttons["New directions"]).tap()
        app.buttons["Done"].tap()
        saveRouteChanges()
        closeRoute()
        XCTAssertEqual(try savedSnapshot()["directionsRequests"] as? Int, requestsBefore + 1)
    }

    func testRecalculateSavedRouteRetainsStopsAndSavesNewSpeed() throws {
        launchRoutes()
        let countBefore = try XCTUnwrap(savedSnapshot()["count"] as? Int)
        let before = try savedTrip()
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Stop and route options"]).tap()
        app.buttons["Recalculate with another mode"].tap()
        app.buttons["E-bike"].tap()
        XCTAssertEqual(app.sliders["E-bike speed in miles per hour"].value as? String, "31.0 mph")
        let speed = try setVisibleSpeed("E-bike", position: 0.65)
        capture("30-recalculate-same-stops")
        routeControl(app.buttons["route.recalculate.confirm"]).tap()
        XCTAssertTrue(app.buttons["Movement to Test cafe"].waitForExistence(timeout: 5))
        saveRouteChanges()
        closeRoute()
        let saved = try savedTrip()
        XCTAssertEqual(try savedSnapshot()["count"] as? Int, countBefore,
                       "Save changes must update the existing route instead of creating a duplicate")
        for key in ["id", "name", "originName", "destinationName"] {
            XCTAssertEqual(saved[key] as? String, before[key] as? String, key)
        }
        XCTAssertEqual(saved["mode"] as? String, "eBike")
        XCTAssertEqual(try XCTUnwrap(saved["speedMPH"] as? Double), speed, accuracy: 0.11)
        XCTAssertEqual(saved["smoothMovement"] as? Bool, true)
        XCTAssertEqual(saved["arrival"] as? String, before["arrival"] as? String)
        let stops = try XCTUnwrap(saved["stops"] as? [[String: Any]])
        let originalStops = try XCTUnwrap(before["stops"] as? [[String: Any]])
        XCTAssertEqual(stops.count, 2)
        for index in stops.indices {
            for key in ["id", "name"] { XCTAssertEqual(stops[index][key] as? String, originalStops[index][key] as? String) }
            XCTAssertEqual(stops[index]["waitSeconds"] as? Double, originalStops[index]["waitSeconds"] as? Double)
        }
        let points = try XCTUnwrap(saved["points"] as? [[String: Any]])
        let oldPoints = try XCTUnwrap(before["points"] as? [[String: Any]])
        XCTAssertTrue(NSDictionary(dictionary: points.first!).isEqual(to: oldPoints.first!))
        XCTAssertTrue(NSDictionary(dictionary: points.last!).isEqual(to: oldPoints.last!))
        let sections = try XCTUnwrap(saved["travelSections"] as? [[String: Any]])
        XCTAssertEqual(sections.count, 3)
        for section in sections {
            XCTAssertEqual(section["mode"] as? String, "eBike")
            XCTAssertEqual(try XCTUnwrap(section["speedMPH"] as? Double), speed, accuracy: 0.11)
        }
        app.buttons["Reopen last saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        XCTAssertEqual(try XCTUnwrap(Double((app.sliders.firstMatch.value as? String ?? "").components(separatedBy: " ")[0])), speed, accuracy: 0.11)
        capture("31-reopened-recalculated-route")
    }

    func testSavedPinsCrossCutoffDuringPinchAndStayVisibleWhenRotated() {
        launch("map-pins", narrow: false)
        reachable("session.pause"); reachable("session.stop")
        app.buttons["Collapse route details"].tap()
        XCTAssertTrue(app.buttons["validation.pin.near"].isHittable)
        app.buttons["validation.pin.near"].tap()
        let count = app.staticTexts["validation.pinCount"]
        func expectPins(_ shown: Bool) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let number = Int(count.label) else { return false }
                return shown ? number > 0 : number == 0
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
        }
        func value(_ id: String) -> Int { Int(app.staticTexts[id].label) ?? -1 }
        expectPins(true)
        capture("18-pins-near-active-route")
        let pinchArea = app.otherElements["validation.pinchSurface"]
        XCTAssertLessThan(pinchArea.frame.maxY, app.buttons["Expand route details"].frame.minY - 16,
                          "Both pinch fingers must stay above the route tray")
        let hides = value("validation.pinLiveHides")
        pinchArea.pinch(withScale: 0.2, velocity: -0.5)
        expectPins(false)
        XCTAssertGreaterThan(Double(app.staticTexts["validation.pinWidth"].label) ?? 0, 1)
        XCTAssertGreaterThan(value("validation.pinLiveHides"), hides, "Pins must hide in a continuous callback, before camera settles")
        capture("19-pins-hidden-after-live-crossing")
        let shows = value("validation.pinLiveShows")
        pinchArea.pinch(withScale: 5, velocity: 0.5)
        expectPins(true)
        XCTAssertLessThan(Double(app.staticTexts["validation.pinWidth"].label) ?? 2, 1)
        XCTAssertGreaterThan(value("validation.pinLiveShows"), shows, "Pins must reappear in a continuous callback, before camera settles")
        app.buttons["validation.pin.edge"].tap()
        expectPins(true)
        // Wait for this camera's settled sample before comparing its heading.
        let width = app.staticTexts["validation.pinWidth"]
        let edge = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let miles = Double(width.label) ?? 0
            return miles > 0.85 && miles < 0.95
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [edge], timeout: 8), .completed)
        let before = Double(width.label)!
        let settled = value("validation.pinSettled")
        app.buttons["validation.pin.rotate"].tap()
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            value("validation.pinSettled") > settled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        expectPins(true)
        XCTAssertEqual(Double(width.label) ?? 0, before, accuracy: 0.03, "Rotation alone must not change visible-up-to width")
        reachable("session.pause"); reachable("session.stop")
        capture("20-pins-rotated-at-same-ground-scale")
    }
    private func reachable(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 12), id)
        XCTAssertTrue(button.isHittable, id)
        XCTAssertGreaterThanOrEqual(button.frame.height, 43, id)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), id)
        let solidNavigation = app.buttons["navigation.library"]
        if solidNavigation.exists && solidNavigation.isHittable {
            XCTAssertLessThanOrEqual(button.frame.maxY, solidNavigation.frame.minY - 8,
                                    "\(id) must clear the solid navigation bar")
        }
    }
    func testDeletedSelectionAfterLongListScroll() {
        launch("deleted-selection", narrow: false)
        app.buttons["Select"].tap()
        for _ in 0..<3 { app.swipeUp(velocity: .fast) }
        app.swipeDown(velocity: .slow)
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test deleted pin' AND label CONTAINS ', expires '"))
            .allElementsBoundByIndex.filter {
                $0.value != nil && $0.isHittable && $0.frame.minY > 160 && $0.frame.maxY < app.frame.maxY - 150
            }.sorted { $0.frame.minY < $1.frame.minY }
        guard rows.count >= 3 else { XCTFail("Expected three visible selection rows"); return }
        let first = rows[0], third = rows[2]
        first.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 42, dy: 0))
            .press(forDuration: 0.1, thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 42, dy: 0)))
        XCTAssertTrue(app.buttons["Delete (3)"].waitForExistence(timeout: 5))
        for row in rows.prefix(3) { XCTAssertTrue((row.value as? String ?? "").contains("Selected")) }
        capture("31-deleted-selection-after-scroll")
        app.buttons["Delete (3)"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["Cancel"].tap()
        XCTAssertTrue(first.exists)
    }
    func testSavedPinLowerEdgeHoldOnlyMovesPreview() {
        launch("pin-adjustment", narrow: false)
        let pin = app.buttons["Test botanical garden walking route beside the riverside observatory and community orchard"]
        XCTAssertTrue(pin.waitForExistence(timeout: 12))
        XCTAssertTrue(pin.isHittable)
        let coordinate = app.staticTexts["validation.adjustedPin"]
        let before = coordinate.label
        let bottom = pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        // A cold simulator can drop the first synthetic long press before the
        // pin's gesture recognizer attaches. Hold the same lower edge again
        // instead of loosening what this check is about.
        var adjusted = false
        for _ in 0..<3 where !adjusted {
            bottom.press(forDuration: 0.35, thenDragTo: bottom.withOffset(CGVector(dx: 65, dy: -35)))
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in coordinate.label != before }, object: nil)
            adjusted = XCTWaiter.wait(for: [moved], timeout: 6) == .completed
        }
        XCTAssertTrue(adjusted, "Holding the pin's lower edge must move only the preview")
        XCTAssertEqual(app.staticTexts["validation.pinCommand"].label, "No location sent")
        capture("32-pin-lower-edge-adjustment")
    }

    func testHeldLocationMarkerChangesSymbolWithoutPreparingOrSendingAnotherLocation() {
        launch("held-location", narrow: false)
        let teleport = app.buttons["Teleport"]
        XCTAssertTrue(teleport.waitForExistence(timeout: 10))
        teleport.tap()
        XCTAssertTrue(app.staticTexts["Holding location"].waitForExistence(timeout: 10))
        app.buttons["map.follow"].tap()

        let marker = app.descendants(matching: .any)["map.heldLocationMarker"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        XCTAssertTrue(marker.isHittable)
        XCTAssertEqual(marker.value as? String, "Automatic")
        let generation = app.staticTexts["validation.commandGeneration"].label
        marker.press(forDuration: 0.7)
        let star = app.buttons["Star"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()

        XCTAssertEqual(marker.value as? String, "Star")
        XCTAssertTrue(app.staticTexts["Holding location"].exists)
        XCTAssertFalse(teleport.exists)
        XCTAssertEqual(app.staticTexts["validation.commandGeneration"].label, generation)
        capture("held-location-marker-star")
    }

    func testSelectedCustomPinRefreshesItsSavedAndRecentAddresses() {
        launch("pin-address-refresh", narrow: false)
        XCTAssertTrue(app.staticTexts["12 Main Street, New York, NY 10019"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["My saved destination"].exists)
        app.buttons["Check saved address refresh"].tap()
        XCTAssertEqual(app.staticTexts["validation.pinAddressReport"].label, "Saved and recent addresses refreshed")

        app.buttons["Edit pin from old snapshot"].tap()
        let save = app.navigationBars["Edit pin"].buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let check = app.buttons["Check saved address refresh"]
        let editorDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [editorDismissed], timeout: 5), .completed)
        XCTAssertTrue(check.isHittable)
        check.tap()
        XCTAssertEqual(app.staticTexts["validation.pinAddressReport"].label, "Saved and recent addresses refreshed")
    }
    func testIdleTraySitsAboveSolidNavigation() {
        checkIdleTray(solid: true)
    }
    func testIdleTraySitsAboveGlassNavigation() {
        checkIdleTray(solid: false)
    }
    private func checkIdleTray(solid: Bool) {
        launch(solid ? "home-solid" : "home-glass", narrow: false)
        XCTAssertTrue(app.staticTexts["Where to next?"].waitForExistence(timeout: 10))
        let saved = app.buttons["Saved"]
        XCTAssertTrue(saved.isHittable)
        let navigation = solid ? app.buttons["navigation.library"] : app.tabBars.firstMatch
        XCTAssertTrue(navigation.exists)
        let gap = navigation.frame.minY - saved.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 12, "Tray actions must clear navigation")
        XCTAssertLessThanOrEqual(gap, 60, "The compact idle tray must not float above navigation")
        capture(solid ? "16-idle-solid-tray-spacing" : "17-idle-glass-tray-spacing")
    }
    func testMovingPauseResumeAndStop() {
        launch("moving")
        reachable("session.pause"); reachable("session.stop")
        reachable("map.routeSearch"); reachable("map.follow")
        reachable("Route details")
        XCTAssertGreaterThanOrEqual(app.buttons["map.follow"].frame.minY,
                                    app.buttons["Route details"].frame.maxY)
        capture("01-moving-narrow-light")
        app.buttons["session.pause"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'session.pause' AND label CONTAINS 'Resume'")).firstMatch.waitForExistence(timeout: 10))
        capture("02-paused-narrow-light")
        app.buttons["session.pause"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'session.pause' AND label CONTAINS 'Pause'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.staticTexts["Where do you want to go?"].waitForExistence(timeout: 10))
        capture("03-cleared-test-session")
    }

    func testRouteCameraStartsAtTheRouteAndRestoresDetailAfterFit() throws {
        launch("route-camera", narrow: false)
        let startRoute = app.buttons["validation.startCameraRoute"]
        XCTAssertTrue(startRoute.waitForExistence(timeout: 10))
        let camera = app.staticTexts["validation.routeCamera"]
        func cameraValues() -> [Double] { camera.label.split(separator: ",").compactMap { Double($0) } }
        func waitForCamera(_ predicate: @escaping (Double, Double) -> Bool) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let values = cameraValues()
                return values.count == 2 && predicate(values[0], values[1])
            }, object: camera)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, camera.label)
        }

        app.buttons["map.follow"].tap()
        waitForCamera { offset, _ in offset > 1_000_000 }
        startRoute.tap()
        waitForCamera { offset, _ in offset < 250 }
        XCTAssertEqual(app.staticTexts["validation.routeCameraLocation"].label, "Previous location held")
        let detailDistance = try XCTUnwrap(cameraValues().last)

        let overview = app.buttons["Route overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        overview.tap()
        let returnToDetail = app.buttons["Return to route detail"]
        XCTAssertTrue(returnToDetail.waitForExistence(timeout: 5))
        waitForCamera { offset, distance in offset > 400 && distance > detailDistance }
        returnToDetail.tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        waitForCamera { offset, distance in offset < 250 && abs(distance - detailDistance) < detailDistance * 0.1 }
        capture("route-camera-fit-round-trip")
    }

    func testRouteSearchUpdatesSavedIdentityAndMetadata() throws {
        try exerciseRouteSearchSave(scenario: "route-identity-saved", expectedCount: 1, saved: true)
    }

    func testRouteSearchUpdatesSavedIdentityAtLibraryLimit() throws {
        try exerciseRouteSearchSave(scenario: "route-identity-full", expectedCount: 50, saved: true)
    }

    func testRouteSearchSavesUnsavedRouteAsOneNewTrip() throws {
        try exerciseRouteSearchSave(scenario: "route-identity-unsaved", expectedCount: 1, saved: false)
    }

    private func routeLibrarySnapshot() throws -> [[String: Any]] {
        app.buttons["validation.readRouteLibrary"].tap()
        let text = app.staticTexts["validation.routeLibrarySnapshot"].label
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    private func openAddStopConfirmation() -> XCUIElement {
        app.buttons["map.routeSearch"].tap()
        let expand = app.buttons["routeSearch.fullMap"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10)); expand.tap()
        let center = app.buttons["Map center"]
        XCTAssertTrue(center.waitForExistence(timeout: 10)); center.tap()
        app.buttons["Choose action"].tap()
        let add = app.buttons["routeSearch.addStop"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let confirm = app.buttons["Hold location and add stop"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        return confirm
    }

    private func exerciseRouteSearchSave(scenario: String, expectedCount: Int, saved: Bool) throws {
        launch(scenario, narrow: false)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 15))
        let before = try routeLibrarySnapshot()
        XCTAssertEqual(before.count, expectedCount)
        let original = try XCTUnwrap(before.first { ($0["folder"] as? String) == "Route QA" })
        let originalID = try XCTUnwrap(original["id"] as? String)
        XCTAssertEqual(original["favorite"] as? Bool, true)
        openAddStopConfirmation().tap()
        XCTAssertTrue(app.navigationBars["Plan a route"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Dropped pin"].waitForExistence(timeout: 20))
        routeControl(app.buttons[saved ? "Save changes" : "Save route"]).tap()
        XCTAssertTrue(app.alerts["Save trip"].waitForExistence(timeout: 5))
        app.alerts["Save trip"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Trip saved with its place names and stops."].waitForExistence(timeout: 10))
        capture("40-" + scenario + "-saved")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["validation.readRouteLibrary"].waitForExistence(timeout: 10))
        let after = try routeLibrarySnapshot() // Fresh TripLibrary reads the persisted file.
        XCTAssertEqual(after.count, expectedCount + (saved ? 0 : 1))
        for previous in before {
            let id = try XCTUnwrap(previous["id"] as? String)
            let current = try XCTUnwrap(after.first { $0["id"] as? String == id })
            if saved && id == originalID {
                XCTAssertEqual(current["favorite"] as? Bool, true)
                XCTAssertEqual(current["folder"] as? String, "Route QA")
                XCTAssertEqual(current["name"] as? String, original["name"] as? String)
                let stops = try XCTUnwrap(current["stops"] as? [[String: Any]])
                XCTAssertEqual(stops.count, 1, "The original saved record must contain the added stop")
                XCTAssertEqual(stops.first?["name"] as? String, "Dropped pin")
            } else {
                XCTAssertTrue(NSDictionary(dictionary: previous).isEqual(to: current),
                              "Unrelated saved trips must remain unchanged")
            }
        }
        if !saved {
            let newTrips = after.filter { current in !before.contains { $0["id"] as? String == current["id"] as? String } }
            XCTAssertEqual(newTrips.count, 1)
            XCTAssertEqual((newTrips.first?["stops"] as? [[String: Any]])?.count, 1)
        }
        XCTAssertFalse(app.buttons["session.pause"].exists, "Saving must not restart travel")
    }

    func testRouteSearchDismissesAddStopAfterRouteReplacement() {
        launch("route-search-replacement", narrow: false)
        let following = app.staticTexts["Following route"]
        XCTAssertTrue(following.waitForExistence(timeout: 15))
        let confirm = openAddStopConfirmation()

        let request = CFNotificationName(rawValue: "com.n3mostudio.elsepin.validation.replace-route" as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), request, nil, nil, true)

        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10), "The original route's confirmation must be dismissed")
        XCTAssertTrue(app.staticTexts["Test replacement destination"].waitForExistence(timeout: 10))
        XCTAssertTrue(following.waitForExistence(timeout: 10), "The replacement route must keep moving")
        XCTAssertTrue(app.buttons["session.pause"].exists)
        XCTAssertFalse(app.navigationBars["Plan a route"].exists)
        capture("41-route-search-replacement-stays-active")
    }

    func testRouteSearchSeparatesAddStopFromSavePin() {
        launch("moving")
        let search = app.buttons["map.routeSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let expand = app.buttons["routeSearch.fullMap"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        XCTAssertEqual(expand.label, "Choose stop on full-screen map")
        expand.tap()
        let center = app.buttons["Map center"]
        XCTAssertTrue(center.waitForExistence(timeout: 10))
        center.tap()
        app.buttons["Choose action"].tap()
        XCTAssertTrue(app.buttons["routeSearch.addStop"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["routeSearch.savePin"].exists)
        capture("38-route-search-place-actions")
        XCTAssertTrue(app.buttons["session.stop"].exists, "Choosing an action must not stop travel before confirmation")
        let cancelChoice = app.buttons["Cancel"]
        if cancelChoice.exists {
            cancelChoice.tap()
        } else {
            // Native popover confirmation dialogs dismiss by tapping outside;
            // iOS does not always render their cancel action as a button.
            app.navigationBars["Along your route"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.buttons["routeSearch.addStop"].waitForNonExistence(timeout: 5),
                      "Dismissing the native dialog must cancel its pending choice")
        XCTAssertTrue(app.navigationBars["Along your route"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["session.stop"].exists, "Cancelling the place action must keep the active route")

        expand.tap()
        XCTAssertTrue(center.waitForExistence(timeout: 10))
        center.tap()
        app.buttons["Choose action"].tap()
        // iOS may expose both the native popover action and its SwiftUI child.
        app.buttons["routeSearch.addStop"].firstMatch.tap()
        let confirm = app.buttons["Hold location and add stop"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["session.stop"].exists, "The live route must remain active until explicit confirmation")
        // Dismiss the final confirmation too, then open and close a fresh search.
        // The abandoned stop must not make the old confirmation appear again.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { search.tap() }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session.pause"].exists)
        search.tap()
        XCTAssertTrue(app.navigationBars["Along your route"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Along your route"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(confirm.waitForExistence(timeout: 2), "A new search must not reuse the cancelled stop")
        XCTAssertTrue(app.buttons["session.pause"].exists)
        search.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        XCTAssertTrue(center.waitForExistence(timeout: 10))
        center.tap()
        app.buttons["Choose action"].tap()
        app.buttons["routeSearch.addStop"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Plan a route"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Dropped pin"].waitForExistence(timeout: 20),
                      "The confirmed place must appear in the planner draft")
        capture("39-route-search-added-stop")
        XCTAssertFalse(app.buttons["session.pause"].exists, "Opening the planner must not automatically resume movement")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Where do you want to go?"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["session.pause"].exists, "Cancelling the planner must leave movement stopped")
    }
    func testLargestTextLongRouteAndWrappedControls() {
        launch("moving", large: true)
        reachable("session.pause"); reachable("session.stop")
        reachable("map.routeSearch"); reachable("map.follow")
        capture("04-largest-text-long-route")
        let details = app.scrollViews["route.detailsScroll"]
        XCTAssertTrue(details.exists)
        XCTAssertGreaterThanOrEqual(details.frame.height, 44, "Route details need a usable scrolling viewport")
        details.swipeUp()
        reachable("session.pause"); reachable("session.stop")
        capture("04b-largest-text-details-scrolled")
        app.buttons["session.pause"].tap()
        reachable("session.stop")
        capture("05-largest-text-paused")
    }
    func testDarkAccessibilityFallbackPaused() {
        restoreAccessibility = true
        configureAccessibility(true)
        launch("paused", large: true, dark: true, fallback: true)
        reachable("session.stop"); reachable("session.pause")
        XCTAssertFalse(app.tabBars.buttons["Library"].isHittable, "Only the solid fallback navigation should be visible")
        XCTAssertLessThan(app.buttons["session.pause"].frame.height, 85, "Resume should fit on one line")
        capture("06-dark-reduced-motion-transparency-contrast")
    }
    private func configureAccessibility(_ enabled: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        func backButton() -> XCUIElement {
            let explicit = settings.buttons["BackButton"]
            return explicit.exists ? explicit : settings.navigationBars.buttons.firstMatch
        }
        for _ in 0..<6 {
            if settings.navigationBars["Settings"].exists { break }
            let back = backButton()
            if back.exists { back.tap() } else { break }
        }
        func open(_ label: String) {
            let text = settings.staticTexts.matching(identifier: label).firstMatch
            for _ in 0..<7 {
                if text.exists && text.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(text.waitForExistence(timeout: 5), "Settings: \(label)")
            text.tap()
        }
        func toggle(_ label: String) {
            let control = settings.switches.matching(identifier: label).firstMatch
            for _ in 0..<4 {
                if control.exists && control.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Settings: \(label)")
            let expected = enabled ? "1" : "0"
            if control.value as? String != expected {
                // Settings exposes the entire row as a switch on some runtimes.
                // Hit the visible trailing toggle, then wait for its async update.
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, label)
        }
        open("Accessibility"); open("Display & Text Size")
        toggle("Reduce Transparency"); toggle("Increase Contrast")
        backButton().tap()
        open("Motion"); toggle("Reduce Motion")
        let shot = XCTAttachment(screenshot: settings.screenshot())
        shot.name = enabled ? "accessibility-settings-enabled" : "accessibility-settings-reset"
        shot.lifetime = .keepAlways; add(shot)
        settings.terminate()
    }
    func testConnectingIsNotPresentedAsMoving() {
        launch("connecting")
        XCTAssertTrue(app.staticTexts["Starting route…"].waitForExistence(timeout: 10))
        capture("07-connecting-test-only")
        reachable("session.stop")
    }
    func testFailedStateOffersRecovery() {
        launch("failed")
        if app.alerts.firstMatch.waitForExistence(timeout: 5) { app.alerts.buttons["OK"].tap() }
        XCTAssertTrue(app.buttons["Retry connection"].waitForExistence(timeout: 10))
        reachable("session.stop")
        capture("08-failed-test-only")
    }
    func testSearchSubmitFailureAndRetry() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("retry\n")
        XCTAssertTrue(app.staticTexts["You're offline. Reconnect and try again; saved pins still work."].waitForExistence(timeout: 10))
        capture("09-search-failed")
        app.buttons["Search for “retry”"].tap()
        XCTAssertTrue(app.staticTexts["Test cafe result for retry"].waitForExistence(timeout: 10))
        capture("10-search-retried")
    }
    func testSearchCancellationRejectsLateResults() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        XCTAssertTrue(app.buttons["Cancel search"].waitForExistence(timeout: 5))
        app.buttons["Cancel search"].tap()
        app.buttons["Clear search"].tap(); field.tap(); field.typeText("cafe\n")
        XCTAssertTrue(app.staticTexts["Test cafe result for cafe"].waitForExistence(timeout: 10))
        let obsolete = app.staticTexts["OBSOLETE TEST RESULT"]
        XCTAssertFalse(obsolete.waitForExistence(timeout: 4))
        capture("11-search-cancelled-late-response-discarded")
    }
    func testSearchDismissalAndForegroundInterruption() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(field.exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["validation.banner"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OBSOLETE TEST RESULT"].waitForExistence(timeout: 4))
        capture("12-search-dismissed-and-resumed")
    }
    func testSearchInterruptedWhilePendingThenReplaced() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        XCTAssertTrue(app.buttons["Cancel search"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["Clear search"].tap(); field.tap(); field.typeText("cafe\n")
        XCTAssertTrue(app.staticTexts["Test cafe result for cafe"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OBSOLETE TEST RESULT"].waitForExistence(timeout: 4))
        capture("15-search-background-interruption-replaced")
    }
    func testLibraryEmptyState() {
        launch("empty")
        openLibrary()
        XCTAssertTrue(app.staticTexts["Star a pin to find it here."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Star a saved route to find it here."].exists)
        capture("13-library-empty")
    }
    func testLibraryLongNamesLargeDark() {
        launch("idle", large: true, dark: true, fallback: true)
        openLibrary()
        let longItem = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch
        XCTAssertTrue(longItem.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(longItem.frame.width, 180)
        capture("14-library-long-names-largest-text")
        app.descendants(matching: .any).matching(identifier: "library.category").firstMatch.tap()
        app.buttons["Routes"].tap()
        XCTAssertTrue(longItem.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(longItem.frame.width, 180)
        // The Create route row can fill the initial viewport at maximum text.
        // Bring the saved route itself into view before accepting its screenshot.
        for _ in 0..<4 {
            if longItem.isHittable && longItem.frame.minY < 300 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(longItem.isHittable)
        capture("14b-library-long-route-largest-text")
    }
    private func openLibrary() {
        let solid = app.buttons["navigation.library"]
        if solid.exists && solid.isHittable { solid.tap() }
        else { app.tabBars.buttons["Library"].tap() }
    }
}
