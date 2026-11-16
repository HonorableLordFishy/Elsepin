import XCTest

final class ElsepinBackupUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground { capture("backup-final"); app.terminate() }
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func visible(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY >= 145 && element.frame.maxY <= app.frame.maxY - 50 { return element }
            let above = element.exists && element.frame.minY < 145
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.35 : 0.77))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.77 : 0.35)))
        }
        XCTFail("Unreachable backup control: \(element)"); return element
    }
    private func tapFileLocationIfPresent(_ label: String) {
        for element in [app.staticTexts[label].firstMatch, app.buttons[label].firstMatch] {
            if element.exists && element.isHittable { element.tap(); return }
        }
    }
    private func localExportFolder() {
        tapFileLocationIfPresent("Browse")
        tapFileLocationIfPresent("On My iPhone")
        tapFileLocationIfPresent("Elsepin")
        tapFileLocationIfPresent("Validation exports")
    }
    private func snapshot() throws -> [String: Any] {
        app.buttons["Read settings and export"].tap()
        let text = app.staticTexts["validation.backupSnapshot"].label
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    private func settings(_ snapshot: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(snapshot["settings"] as? [String: Any])
    }
    private func openImport() {
        app.buttons["Import and export"].tap()
        app.buttons["Choose backup file"].tap()
        localExportFolder()
        let file = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Elsepin-Settings'")).firstMatch
        if !file.waitForExistence(timeout: 3) {
            // Files can retain an empty pre-export listing on a fresh simulator.
            // Re-enter the location through its native history to refresh it.
            capture("33b-import-files-before-refresh")
            let back = app.buttons["DOC.navBarButton.backInHistory"]
            if back.exists { back.tap() }
            let folder = app.staticTexts["Elsepin"].firstMatch
            if folder.waitForExistence(timeout: 5) { folder.tap() }
            tapFileLocationIfPresent("Validation exports")
            capture("33c-import-files-after-refresh")
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        file.tap()
        if app.navigationBars.buttons["Open"].exists { app.navigationBars.buttons["Open"].tap() }
        XCTAssertTrue(app.navigationBars["Review import"].waitForExistence(timeout: 10))
    }
    private func expandSettings() {
        let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings ·'")).firstMatch
        visible(group).tap()
    }
    private func applyImport() {
        visible(app.buttons["Import selected changes"]).tap()
        let confirm = app.sheets.buttons["Import selected changes"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Import complete.'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close backup test"].tap()
    }

    func testSettingsExportFileSelectiveImportAndRelaunch() throws {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "backup-settings"
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        let baseline = try snapshot()
        let original = try settings(baseline)
        app.buttons["Import and export"].tap()
        visible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Backup contents'")).firstMatch).tap()
        app.buttons["Settings"].tap()
        app.buttons["Export backup"].tap()
        app.buttons["Export settings"].tap()
        capture("32-native-settings-export-picker")
        localExportFolder()
        capture("33-local-export-destination")
        let exportButton = app.navigationBars.buttons["Export"].firstMatch
        if exportButton.exists { exportButton.tap() }
        else { app.navigationBars.buttons["Save"].tap() }
        XCTAssertTrue(app.staticTexts["Backup exported."].waitForExistence(timeout: 10))
        app.buttons["Close backup test"].tap()
        let exported = try snapshot()
        XCTAssertEqual(exported["valid"] as? Bool, true)
        let backup = try XCTUnwrap(exported["export"] as? [String: Any])
        XCTAssertEqual(backup["categories"] as? [String], ["settings"])
        XCTAssertEqual((backup["trips"] as? [Any])?.count, 0)
        XCTAssertEqual((backup["places"] as? [Any])?.count, 0)
        let exportedSettings = try XCTUnwrap(backup["preferences"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: exportedSettings))

        app.buttons["Change disposable settings"].tap()
        let changed = try settings(snapshot())
        XCTAssertFalse(NSDictionary(dictionary: original).isEqual(to: changed))
        openImport()
        XCTAssertFalse(visible(app.buttons["Import selected changes"]).isEnabled, "Settings must start unchecked")
        capture("34-import-starts-unchecked")
        visible(app.buttons["Cancel import"]).tap()
        app.buttons["Close backup test"].tap()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: changed), "Cancel changed settings")

        openImport()
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        let drive = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Drive preset'")).firstMatch
        visible(drive).tap()
        XCTAssertEqual(drive.value as? String, "Not selected")
        capture("35-import-leaves-drive-unchecked")
        applyImport()
        let partial = try settings(snapshot())
        var expectedPartial = original
        var speeds = try XCTUnwrap(original["usualSpeeds"] as? [String: Any])
        speeds["drive"] = 1
        expectedPartial["usualSpeeds"] = speeds
        XCTAssertTrue(NSDictionary(dictionary: partial).isEqual(to: expectedPartial), "Selective import changed an unchecked value or missed a selected value")

        openImport()
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        applyImport()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: original))
        app.terminate()
        app.launchArguments.append("--preserve-backup-test-data")
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        let reopened = try snapshot()
        XCTAssertTrue(NSDictionary(dictionary: try settings(reopened)).isEqual(to: original), "Restored settings did not persist through relaunch")
        XCTAssertEqual(reopened["tripCount"] as? Int, baseline["tripCount"] as? Int)
        XCTAssertEqual(reopened["pinCount"] as? Int, baseline["pinCount"] as? Int)
        openImport()
        XCTAssertFalse(visible(app.buttons["Import selected changes"]).isEnabled, "Reimport should have no settings left to change")
        capture("36-reimport-after-relaunch-no-changes")
    }
}
