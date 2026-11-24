import XCTest

final class ElsepinBackupUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }
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
    private func openLocalFilesStorage() {
        // DocumentManager loads out of process. Wait for its navigation before
        // querying locations or choosing the provider root as the destination.
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 25), "Native Files did not finish presenting")
        // In a subfolder the Back button can say On My iPhone too. Require
        // the provider's current title, separately exposed as text or a menu.
        let title = localStorageTitle(in: picker)
        if !title.waitForExistence(timeout: 5) {
            // Export can reopen at Elsepin's app folder and omit the tabs.
            let backToLocal = picker.buttons.matching(NSPredicate(format: "identifier == 'BackButton' AND label == 'On My iPhone'")).firstMatch
            if backToLocal.exists && backToLocal.isHittable { backToLocal.tap() }
        }
        if !title.waitForExistence(timeout: 5) {
            let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
            if browse.exists && browse.isHittable {
                browse.tap()
                browse.tap()
            } else {
                let back = picker.buttons["BackButton"]
                XCTAssertTrue(back.waitForExistence(timeout: 10))
                back.tap()
            }
            let location = app.staticTexts["On My iPhone"].firstMatch
            XCTAssertTrue(location.waitForExistence(timeout: 10))
            let row = app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
            if row.exists { row.tap() } else { location.tap() }
        }
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Native Files did not open On My iPhone")
    }
    private func localStorageTitle(in navigation: XCUIElement) -> XCUIElement {
        navigation.descendants(matching: .any).matching(NSPredicate(format: "identifier != 'BackButton' AND (label == %@ OR label BEGINSWITH %@)",
            "On My iPhone", "On My iPhone,")).firstMatch
    }
    private func snapshot() throws -> [String: Any] {
        app.buttons["Read settings and export"].tap()
        let text = app.staticTexts["validation.backupSnapshot"].label
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    private func settings(_ snapshot: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(snapshot["settings"] as? [String: Any])
    }
    private func prepareFilesProvider() {
        // A successful simctl launch does not mean Files' provider has finished
        // its first-run indexing. Verify actual enumeration before opening an
        // export sheet; a blank system sheet is not a backup interaction result.
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        let browse = files.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 60), "Simulator Files did not become ready")
        browse.tap()
        browse.tap()
        let location = files.staticTexts["On My iPhone"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 30))
        let row = files.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if row.exists { row.tap() } else { location.tap() }
        XCTAssertTrue(localStorageTitle(in: files.navigationBars.firstMatch).waitForExistence(timeout: 60),
            "Simulator Files did not open On My iPhone")
        app.activate()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
    }
    private func openImport(named filename: String) {
        app.buttons["Import and export"].tap()
        app.buttons["Choose backup file"].tap()
        openLocalFilesStorage()
        let stem = (filename as NSString).deletingPathExtension
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR label == %@ OR label BEGINSWITH %@",
            filename, stem, "\(stem),")).firstMatch
        capture("33b-original-settings-file")
        XCTAssertTrue(file.waitForExistence(timeout: 20), "Exported settings file not listed")
        XCTAssertTrue(file.isEnabled, "Valid settings backup is disabled in Files")
        let review = app.navigationBars["Review import"]
        let open = app.navigationBars.buttons["Open"]
        func selectVisibleFile() -> Bool {
            // Prefer the thumbnail in grid mode, where the filename can sit
            // below the visible hit target.
            let thumbnail = file.images.firstMatch
            if thumbnail.exists && thumbnail.isHittable { thumbnail.tap() }
            else { file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap() }
            // Some Files builds deliver the selection immediately. Others first
            // select the row and add an asynchronously enabled Open button.
            if review.waitForExistence(timeout: 3) { return true }
            if open.waitForExistence(timeout: 5) {
                let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: open)
                if XCTWaiter.wait(for: [enabled], timeout: 5) == .completed { open.tap() }
            }
            return review.waitForExistence(timeout: 10)
        }
        var opened = selectVisibleFile()
        // Retry only while the picker and its live row are still present. Never
        // tap a stale file element after Files has already dismissed itself.
        if !opened, file.exists && file.isHittable { opened = selectVisibleFile() }
        if !opened {
            capture("backup-file-selection-failure")
            XCTFail("Selecting the original export did not open import review. \(app.debugDescription)")
        }
    }
    private func expandSettings() {
        let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings ·'")).firstMatch
        visible(group).tap()
    }
    private func applyImport() {
        visible(app.buttons["backup.review.apply"]).tap()
        let confirm = importConfirmation
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Import complete.'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close backup test"].tap()
    }

    private var importConfirmation: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
            "Import selected changes", "backup.review.apply")).firstMatch
    }

    func testSolidTabsLeaveSettingsAndPastedBackupReviewReachable() {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "home-solid-backup"
        app.launch()
        let settingsTab = app.buttons["navigation.settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20))
        settingsTab.tap()

        func bottomControl(_ label: String) -> XCUIElement {
            let button = app.buttons[label]
            for _ in 0..<8 {
                if button.exists && button.isHittable && button.frame.maxY <= settingsTab.frame.minY { return button }
                app.swipeUp()
            }
            XCTFail("\(label) must scroll fully above solid navigation")
            return button
        }

        bottomControl("About Elsepin").tap()
        XCTAssertTrue(app.navigationBars["About Elsepin"].waitForExistence(timeout: 10))
        _ = bottomControl("Licenses & acknowledgments")
        app.navigationBars.buttons.firstMatch.tap()

        bottomControl("Advanced & experimental").tap()
        XCTAssertTrue(app.navigationBars["Advanced & experimental"].waitForExistence(timeout: 10))
        _ = bottomControl("Wipe everything…")
        app.navigationBars.buttons.firstMatch.tap()

        app.swipeDown()
        visible(app.buttons["Import & export"]).tap()
        let paste = app.buttons["backup.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        let review = app.navigationBars["Review import"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Added"].exists)
        _ = bottomControl("Cancel import")
        bottomControl("backup.review.apply").tap()
        XCTAssertTrue(importConfirmation.waitForExistence(timeout: 5))
        capture("backup-confirmation-above-solid-tabs")
        importConfirmation.tap()
        XCTAssertTrue(app.staticTexts["Import complete. 1 pin."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Import & export"].exists)

        paste.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["backup.review.apply"].isEnabled)
        bottomControl("Cancel import").tap()
        XCTAssertTrue(app.navigationBars["Import & export"].exists)

        app.buttons["navigation.library"].tap()
        XCTAssertTrue(app.buttons["Options for New backup pin"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Options for Test botanical garden walking route beside the riverside observatory and community orchard"].exists)
        XCTAssertFalse(app.buttons["Options for Incoming duplicate pin"].exists)
    }

    func testUnreadableTripsBlockBothTripExportsButAllowSettings() throws {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "backup-unreadable-trips"
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Export stopped. Saved trips couldn’t be read.")).firstMatch
        let contents = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Backup contents'")).firstMatch
        let nativePicker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        app.buttons["Import and export"].tap()

        func assertExportBlocked(_ confirmation: String) {
            visible(app.buttons["Export backup"]).tap()
            app.buttons[confirmation].tap()
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            XCTAssertFalse(nativePicker.waitForExistence(timeout: 2))
        }
        assertExportBlocked("Export everything")
        visible(contents).tap()
        app.buttons["Saved routes & areas"].tap()
        assertExportBlocked("Export saved routes & areas")
        capture("unreadable-trips-export-blocked")

        app.buttons["Close backup test"].tap()
        let after = try snapshot()
        XCTAssertEqual(after["originalKept"] as? Bool, true)
        XCTAssertNil(after["readableTripCount"])

        prepareFilesProvider()
        app.buttons["Import and export"].tap()
        visible(contents).tap()
        app.buttons["Settings"].tap()
        visible(app.buttons["Export backup"]).tap()
        app.buttons["Export settings"].tap()
        XCTAssertTrue(nativePicker.waitForExistence(timeout: 25))
        capture("unreadable-trips-settings-export-available")
    }

    func testCorruptionAfterLibraryOpenedBlocksTripExport() throws {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "backup-late-trip-corruption"
        app.launch()
        let corrupt = app.buttons["Corrupt trips after opening library"]
        XCTAssertTrue(corrupt.waitForExistence(timeout: 20))
        corrupt.tap()
        XCTAssertEqual(try snapshot()["originalKept"] as? Bool, true)

        app.buttons["Import and export"].tap()
        visible(app.buttons["Export backup"]).tap()
        app.buttons["Export everything"].tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Export stopped. Saved trips couldn’t be read.")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].exists)
        app.buttons["Close backup test"].tap()
        XCTAssertEqual(try snapshot()["originalKept"] as? Bool, true)
    }

    func testSettingsExportFileSelectiveImportAndRelaunch() throws {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "backup-settings"
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        prepareFilesProvider()
        let baseline = try snapshot()
        XCTAssertEqual(baseline["readableTripCount"] as? Int, 1)
        let original = try settings(baseline)
        app.buttons["Import and export"].tap()
        visible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Backup contents'")).firstMatch).tap()
        app.buttons["Settings"].tap()
        app.buttons["Export backup"].tap()
        app.buttons["Export settings"].tap()
        capture("32-native-settings-export-picker")
        openLocalFilesStorage()
        capture("33-local-export-destination")
        let exportButton = app.navigationBars.buttons["Export"].firstMatch
        if exportButton.exists { exportButton.tap() }
        else { app.navigationBars.buttons["Save"].tap() }
        let replace = app.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 2) { replace.tap() }
        XCTAssertTrue(app.staticTexts["Backup exported."].waitForExistence(timeout: 10))
        app.buttons["Close backup test"].tap()
        var exported = try snapshot()
        for _ in 0..<20 where exported["export"] == nil {
            Thread.sleep(forTimeInterval: 0.5)
            exported = try snapshot()
        }
        XCTAssertEqual(exported["valid"] as? Bool, true)
        let backup = try XCTUnwrap(exported["export"] as? [String: Any])
        XCTAssertEqual(backup["categories"] as? [String], ["settings"])
        XCTAssertEqual((backup["trips"] as? [Any])?.count, 0)
        XCTAssertEqual((backup["places"] as? [Any])?.count, 0)
        let exportedSettings = try XCTUnwrap(backup["preferences"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: exportedSettings))
        let filename = try XCTUnwrap(exported["file"] as? String)

        app.buttons["Change disposable settings"].tap()
        let changed = try settings(snapshot())
        XCTAssertFalse(NSDictionary(dictionary: original).isEqual(to: changed))
        openImport(named: filename)
        XCTAssertFalse(visible(app.buttons["backup.review.apply"]).isEnabled, "Settings must start unchecked")
        capture("34-import-starts-unchecked")
        visible(app.buttons["Cancel import"]).tap()
        app.buttons["Close backup test"].tap()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: changed), "Cancel changed settings")

        openImport(named: filename)
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

        openImport(named: filename)
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
        openImport(named: filename)
        XCTAssertFalse(visible(app.buttons["backup.review.apply"]).isEnabled, "Reimport should have no settings left to change")
        capture("36-reimport-after-relaunch-no-changes")
        visible(app.buttons["Cancel import"]).tap()
        app.buttons["Close backup test"].tap()

        // Keep the existing paste alternative working, using bytes from the
        // real export above rather than constructing an artificial backup.
        app.buttons["Change disposable settings"].tap()
        app.buttons["Copy exported backup text"].tap()
        app.buttons["Import and export"].tap()
        let paste = app.buttons["backup.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        XCTAssertTrue(app.navigationBars["Review import"].waitForExistence(timeout: 10))
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        capture("37-paste-import-retained")
        applyImport()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: original))
    }
}
