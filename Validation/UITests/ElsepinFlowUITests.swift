import XCTest

final class ElsepinFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground {
            capture("final-" + name)
            app.terminate()
        }
    }
    private func launch(_ scenario: String, large: Bool = false, dark: Bool = false, fallback: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test", "--narrow"]
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
        if ["moving", "paused", "connecting", "failed"].contains(scenario) {
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
    private func reachable(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 12), id)
        XCTAssertTrue(button.isHittable, id)
        XCTAssertGreaterThanOrEqual(button.frame.height, 43, id)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), id)
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
    func testLargestTextLongRouteAndWrappedControls() {
        launch("moving", large: true)
        reachable("session.pause"); reachable("session.stop")
        reachable("map.routeSearch"); reachable("map.follow")
        capture("04-largest-text-long-route")
        app.buttons["session.pause"].tap()
        reachable("session.stop")
        capture("05-largest-text-paused")
    }
    func testDarkAccessibilityFallbackPaused() {
        defer { configureAccessibility(false) }
        configureAccessibility(true)
        launch("paused", large: true, dark: true, fallback: true)
        reachable("session.stop"); reachable("session.pause")
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
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch.frame.width, 180)
        capture("14-library-long-names-largest-text")
        app.descendants(matching: .any).matching(identifier: "library.category").firstMatch.tap()
        app.buttons["Routes"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch.frame.width, 180)
        capture("14b-library-long-route-largest-text")
    }
    private func openLibrary() {
        let solid = app.buttons["navigation.library"]
        if solid.exists && solid.isHittable { solid.tap() }
        else { app.tabBars.buttons["Library"].tap() }
    }
}
