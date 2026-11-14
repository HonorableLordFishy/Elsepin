import XCTest

final class ElsepinFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
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
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.exists { button.tap() }
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
        launch("paused", large: true, dark: true, fallback: true)
        reachable("session.stop"); reachable("session.pause")
        capture("06-dark-reduced-motion-transparency-contrast")
    }
    func testConnectingIsNotPresentedAsMoving() {
        launch("connecting")
        XCTAssertTrue(app.staticTexts["Starting route…"].waitForExistence(timeout: 10))
        reachable("session.stop")
        capture("07-connecting-test-only")
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
    func testLibraryEmptyState() {
        launch("empty")
        app.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Star a pin to find it here."].waitForExistence(timeout: 10))
        capture("13-library-empty")
    }
    func testLibraryLongNamesLargeDark() {
        launch("idle", large: true, dark: true, fallback: true)
        app.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch.waitForExistence(timeout: 10))
        capture("14-library-long-names-largest-text")
    }
}
