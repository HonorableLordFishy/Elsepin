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
        XCTFail("Unreachable import/export control: \(element)"); return element
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
    private func prepareFilesProvider(returningTo ready: XCUIElement? = nil) {
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
        XCTAssertTrue((ready ?? app.buttons["Read settings and export"]).waitForExistence(timeout: 20))
    }
    private func openImport(named filename: String) {
        app.buttons["Import and export"].tap()
        app.buttons["Choose backup file"].tap()
        selectFile(named: filename, captureName: "33b-original-settings-file", until: app.navigationBars["Review import"])
    }
    private func selectFile(named filename: String, captureName: String, until result: XCUIElement) {
        openLocalFilesStorage()
        _ = selectVisibleFile(named: filename, captureName: captureName, until: result)
    }

    private func filesItem(named filename: String) -> XCUIElement {
        let stem = (filename as NSString).deletingPathExtension
        return app.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label == %@ OR label BEGINSWITH %@",
            filename, "\(filename),",
            stem, "\(stem),")).firstMatch
    }

    private func selectVisibleFile(named filename: String, captureName: String, until result: XCUIElement) -> TimeInterval {
        let file = filesItem(named: filename)
        capture(captureName)
        XCTAssertTrue(file.waitForExistence(timeout: 20), "\(filename) is missing from Files")
        XCTAssertTrue(file.isEnabled, "\(filename) is disabled in Files")
        let open = app.navigationBars.buttons["Open"]
        var startedAt: TimeInterval?
        func selectVisibleFile() -> Bool {
            // Prefer the thumbnail in grid mode, where the filename can sit
            // below the visible hit target.
            let thumbnail = file.images.firstMatch
            let tapThumbnail = thumbnail.exists && thumbnail.isHittable
            if startedAt == nil { startedAt = ProcessInfo.processInfo.systemUptime }
            if tapThumbnail { thumbnail.tap() }
            else { file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap() }
            // Some Files builds deliver the selection immediately. Others first
            // select the row and add an asynchronously enabled Open button.
            let next = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                result.exists || (open.exists && open.isEnabled)
            }, object: nil)
            guard XCTWaiter.wait(for: [next], timeout: 25) == .completed else { return false }
            if result.exists { return true }
            open.tap()
            return result.waitForExistence(timeout: 25)
        }
        var opened = selectVisibleFile()
        // Retry only while the picker and its live row are still present. Never
        // tap a stale file element after Files has already dismissed itself.
        if !opened, file.exists && file.isHittable { opened = selectVisibleFile() }
        if !opened {
            capture("\(captureName)-selection-failure")
            XCTFail("Selecting \(filename) did not show the expected import result. \(app.debugDescription)")
        }
        return ProcessInfo.processInfo.systemUptime - (startedAt ?? ProcessInfo.processInfo.systemUptime)
    }
    private func saveToLocalFiles() {
        let export = app.navigationBars.buttons["Export"].firstMatch
        if export.exists { export.tap() }
        else { app.navigationBars.buttons["Save"].tap() }
        let replace = app.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 2) { replace.tap() }
    }

    @discardableResult
    private func exportValidationFixture(named filename: String, allowProviderExtension: Bool = false) -> String {
        let item = app.buttons["validation.exportFixture.\(filename)"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Missing export fixture \(filename)")
        item.tap()
        openLocalFilesStorage()
        saveToLocalFiles()
        let status = app.staticTexts["validation.fixtureExportStatus"]
        if !status.waitForExistence(timeout: 20) { capture("fixture-export-\(filename)-failure") }
        XCTAssertTrue(status.exists, "Files did not confirm \(filename)")
        let label = status.label
        XCTAssertTrue(label.hasPrefix("Staged "), label)
        let exportedFilename = String(label.dropFirst("Staged ".count))
        if allowProviderExtension && (exportedFilename as NSString).deletingPathExtension == filename {
            return exportedFilename
        }
        XCTAssertEqual(exportedFilename, filename)
        return exportedFilename
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

    func testGPXExportAndImportThroughNativeFiles() throws {
        let exportedName = "Harbor switchback"
        launchNativeGPX("home-solid-gpx-round-trip")
        openGPXLibraryRoute(named: exportedName, subtitle: "Harbor entrance → Harbor overlook")

        XCTAssertTrue(visible(app.buttons["Save changes"]).isHittable)
        visible(app.buttons["Options"]).tap()
        visible(app.buttons["Export route"]).tap()
        openLocalFilesStorage()
        saveToLocalFiles()
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForNonExistence(timeout: 10))

        visible(app.buttons["Import GPX"]).tap()
        let review = app.navigationBars["Import GPX"]
        selectFile(named: "Elsepin-Route.gpx", captureName: "native-gpx-files", until: review)
        XCTAssertTrue(app.staticTexts["3 points"].waitForExistence(timeout: 10))
        let path = app.descendants(matching: .any)["gpx.path"].firstMatch
        XCTAssertTrue((path.exists && (path.label.contains(exportedName) || (path.value as? String)?.contains(exportedName) == true))
            || app.staticTexts[exportedName].exists || app.buttons[exportedName].exists,
            "The GPX review should show the exported track name")
        let apply = app.buttons["gpx.apply"]
        XCTAssertTrue(apply.isEnabled)
        capture("native-gpx-review")
        apply.tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 10))
        XCTAssertTrue(gpxPlanner.exists)
        // Applying a GPX creates a new draft on the planner, separate from the
        // saved Library entry used to export these coordinates.
        let saveNew = app.buttons["Save route"]
        for _ in 0..<5 where !saveNew.exists { app.swipeDown() }
        XCTAssertTrue(saveNew.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Save changes"].exists)
        visible(saveNew).tap()
        let save = app.alerts["Save trip"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        capture("native-gpx-round-trip-default-name")
        XCTAssertEqual(save.textFields.firstMatch.value as? String, exportedName,
                       "Use this path discarded the exported track name before saving")
        save.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Trip saved with its place names and stops."].waitForExistence(timeout: 10))
        closeGPXPlanner()
        openGPXLibraryRoute(named: exportedName, subtitle: "Path start → Path end")
        visible(app.buttons["Save changes"]).tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.textFields.firstMatch.value as? String, exportedName)
        save.buttons["Cancel"].tap()
        closeGPXPlanner()
        app.buttons["validation.readGPXDiskReport"].tap()
        let text = app.staticTexts["validation.gpxDiskReport"].label
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(report["originalCount"] as? Int, 1)
        XCTAssertEqual(report["importCount"] as? Int, 1)
        XCTAssertEqual(report["originalID"] as? String, "5E1E4E2B-DC57-4571-BA48-947E26A5E111")
        XCTAssertEqual(report["newCopyHasDistinctID"] as? Bool, true)
        XCTAssertEqual(report["originalHasExactGeometry"] as? Bool, true)
        XCTAssertEqual(report["importHasExactEndpoints"] as? Bool, true)
        XCTAssertEqual(report["importHasExactTurn"] as? Bool, true)
        capture("native-gpx-round-trip-reopened-geometry")
    }

    private var gpxPlanner: XCUIElement { app.navigationBars["Plan a route"] }

    private func launchNativeGPX(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = scenario
        app.launch()
        let libraryTab = app.buttons["navigation.library"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 20))
        prepareFilesProvider(returningTo: libraryTab)
    }

    private func openGPXLibraryRoute(named name: String, subtitle: String? = nil) {
        app.buttons["navigation.library"].tap()
        let routes = app.buttons["Routes"]
        XCTAssertTrue(routes.waitForExistence(timeout: 10))
        routes.tap()
        let rowLabel = subtitle.map { NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", name, $0) }
            ?? NSPredicate(format: "label BEGINSWITH %@", name)
        let row = app.buttons.matching(rowLabel).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Missing Library route \(name)")
        row.tap()
        XCTAssertTrue(gpxPlanner.waitForExistence(timeout: 10))
    }

    private func openGPXImportPicker() {
        let options = visible(app.buttons["Options"])
        if options.value as? String != "Expanded" { options.tap() }
        visible(app.buttons["Import GPX"]).tap()
        openLocalFilesStorage()
    }

    private func closeGPXPlanner() {
        gpxPlanner.buttons["Cancel"].tap()
        XCTAssertTrue(gpxPlanner.waitForNonExistence(timeout: 10))
    }

    private func verifyReopenedGPXName(_ name: String) {
        openGPXLibraryRoute(named: name)
        visible(app.buttons["Save changes"]).tap()
        let save = app.alerts["Save trip"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.textFields.firstMatch.value as? String, name)
        save.buttons["Cancel"].tap()
        closeGPXPlanner()
    }

    private func gpxDiskMeasurement(for filename: String) throws -> [String: Any] {
        app.buttons["validation.readGPXDiskReport"].tap()
        let text = app.staticTexts["validation.gpxDiskReport"].label
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        return try XCTUnwrap(report.first { $0["filename"] as? String == filename })
    }

    private func evidenceAttachment(_ measurement: [String: Any], named name: String) throws -> XCTAttachment {
        let data = try JSONSerialization.data(withJSONObject: measurement, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    func testMalformedGPXThroughNativeFilesRetriesWithoutReplacingRoute() {
        launchNativeGPX("home-solid-gpx-malformed")
        exportValidationFixture(named: "QA-GPX-malformed.gpx")
        exportValidationFixture(named: "QA-GPX-small.gpx")
        openGPXLibraryRoute(named: "Test botanical garden walking route")
        openGPXImportPicker()
        let error = app.staticTexts["gpx.error"]
        _ = selectVisibleFile(named: "QA-GPX-malformed.gpx", captureName: "native-gpx-malformed-files", until: error)
        let message = error.label
        XCTAssertTrue(message.contains("GPX"))
        XCTAssertFalse(app.buttons["gpx.apply"].exists)
        let retry = app.buttons["gpx.retry"]
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertEqual(error.label, message)
        XCTAssertFalse(app.buttons["gpx.apply"].exists)
        capture("native-gpx-malformed-retry")
        app.buttons["gpx.cancel"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 10))
        visible(app.buttons["Save changes"]).tap()
        let save = app.alerts["Save trip"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.textFields.firstMatch.value as? String,
                       "Test botanical garden walking route beside the riverside observatory and community orchard")
        save.buttons["Cancel"].tap()

        openGPXImportPicker()
        let apply = app.buttons["gpx.apply"]
        _ = selectVisibleFile(named: "QA-GPX-small.gpx", captureName: "native-gpx-valid-after-malformed", until: apply)
        XCTAssertTrue(app.staticTexts["64 points"].exists)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(app.navigationBars["Import GPX"].waitForNonExistence(timeout: 15))
        let saveRoute = app.buttons["Save route"]
        for _ in 0..<5 where !saveRoute.exists { app.swipeDown() }
        visible(saveRoute).tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 30))
        closeGPXPlanner()
        openGPXLibraryRoute(named: "Test botanical garden walking route")
        XCTAssertTrue(visible(app.buttons["Save changes"]).isEnabled)
        closeGPXPlanner()
        openGPXLibraryRoute(named: "QA small source", subtitle: "Path start → Path end")
        visible(app.buttons["Save changes"]).tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.textFields.firstMatch.value as? String, "QA small source")
        capture("native-gpx-valid-after-malformed-saved")
    }

    func testExtensionlessGPXThroughNativeFilesSavesAndReopens() throws {
        let sourceFilename = "QA-GPX-extensionless"
        let routeName = "QA generic data source"
        launchNativeGPX("home-solid-gpx-generic-data")
        let selectedFilename = exportValidationFixture(named: sourceFilename, allowProviderExtension: true)
        openGPXLibraryRoute(named: "Test botanical garden walking route")
        openGPXImportPicker()
        let apply = app.buttons["gpx.apply"]
        _ = selectVisibleFile(named: selectedFilename, captureName: "native-gpx-extensionless-files", until: apply)
        XCTAssertTrue(app.staticTexts["64 points"].exists)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(app.navigationBars["Import GPX"].waitForNonExistence(timeout: 15))
        let saveRoute = app.buttons["Save route"]
        for _ in 0..<5 where !saveRoute.exists { app.swipeDown() }
        visible(saveRoute).tap()
        let save = app.alerts["Save trip"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.textFields.firstMatch.value as? String, routeName)
        save.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 30))
        closeGPXPlanner()
        verifyReopenedGPXName(routeName)

        var measurement = try gpxDiskMeasurement(for: sourceFilename)
        let provider = measurement["providerExport"] as? [String: Any]
        measurement["requestedExportType"] = "public.data"
        measurement["selectedFilename"] = selectedFilename
        if provider?["contentType"] == nil || provider?["bytes"] == nil {
            measurement["providerObservationLimit"] = "The native export destination did not expose all resource metadata."
        }
        add(try evidenceAttachment(measurement, named: "native-gpx-extensionless-type-and-bytes"))
        XCTAssertEqual(measurement["name"] as? String, routeName)
        XCTAssertEqual(measurement["fromGPX"] as? Bool, true)
        XCTAssertEqual(measurement["matches"] as? Int, 1)
        XCTAssertEqual(measurement["verticesRetainedInOrder"] as? Int, 5)
        XCTAssertEqual(measurement["endpointsRetained"] as? Bool, true)
        if let observedFile = provider?["filename"] as? String { XCTAssertEqual(observedFile, selectedFilename) }
        if let size = provider?["bytes"] as? Int { XCTAssertEqual(size, measurement["sourceBytes"] as? Int) }
        if let identical = provider?["matchesSourceBytes"] as? Bool { XCTAssertTrue(identical) }
    }

    func testNativeGPXImportSizesSaveAndReopen() throws {
        let samples = [
            (filename: "QA-GPX-small.gpx", name: "QA small", points: 64),
            (filename: "QA-GPX-medium.bin", name: "QA medium", points: 4_096),
            (filename: "QA-GPX-large.gpx", name: "QA large", points: 90_000)
        ]
        launchNativeGPX("home-solid-gpx-sizes")
        var previousBytes = 0
        for (index, sample) in samples.enumerated() {
            try XCTContext.runActivity(named: "Import, save and reopen \(sample.filename)") { activity in
                exportValidationFixture(named: sample.filename)
                openGPXLibraryRoute(named: "Test botanical garden walking route")
                openGPXImportPicker()
                let apply = app.buttons["gpx.apply"]
                let reviewTime = selectVisibleFile(named: sample.filename,
                    captureName: "\(sample.filename)-files", until: apply)
                XCTAssertTrue(app.staticTexts["\(sample.points.formatted()) points"].exists)
                XCTAssertTrue(apply.isEnabled)
                capture("\(sample.filename)-review")
                apply.tap()
                XCTAssertTrue(app.navigationBars["Import GPX"].waitForNonExistence(timeout: 15))
                XCTAssertTrue(gpxPlanner.exists)
                let saveRoute = app.buttons["Save route"]
                for _ in 0..<5 where !saveRoute.exists { app.swipeDown() }
                visible(saveRoute).tap()
                let save = app.alerts["Save trip"]
                XCTAssertTrue(save.waitForExistence(timeout: 10))
                let field = save.textFields.firstMatch
                let previous = try XCTUnwrap(field.value as? String)
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + sample.name)
                XCTAssertEqual(field.value as? String, sample.name)
                let startedAt = ProcessInfo.processInfo.systemUptime
                save.buttons["Save"].tap()
                XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 30))
                let saveTime = ProcessInfo.processInfo.systemUptime - startedAt
                closeGPXPlanner()

                let relaunched = index == samples.count - 1
                if relaunched {
                    app.terminate()
                    app.launchArguments.append("--preserve-gpx-test-data")
                    app.launch()
                    XCTAssertTrue(app.buttons["navigation.library"].waitForExistence(timeout: 20))
                }
                verifyReopenedGPXName(sample.name)
                var measurement = try gpxDiskMeasurement(for: sample.filename)
                XCTAssertEqual(measurement["name"] as? String, sample.name)
                XCTAssertEqual(measurement["sourcePoints"] as? Int, sample.points)
                XCTAssertGreaterThanOrEqual(measurement["persistedPoints"] as? Int ?? 0, sample.points)
                XCTAssertEqual(measurement["matches"] as? Int, 1)
                XCTAssertEqual(measurement["fromGPX"] as? Bool, true)
                XCTAssertEqual(measurement["verticesRetainedInOrder"] as? Int, 5)
                XCTAssertEqual(measurement["endpointsRetained"] as? Bool, true)
                let bytes = try XCTUnwrap(measurement["sourceBytes"] as? Int)
                XCTAssertGreaterThan(bytes, previousBytes)
                if let providerExport = measurement["providerExport"] as? [String: Any] {
                    if let providerBytes = providerExport["bytes"] as? Int { XCTAssertEqual(providerBytes, bytes) }
                    if let identical = providerExport["matchesSourceBytes"] as? Bool { XCTAssertTrue(identical) }
                }
                previousBytes = bytes
                measurement["reopenedAfterAppRelaunch"] = relaunched
                measurement["uiTimings"] = ["filesSelectionToReviewSeconds": reviewTime, "saveConfirmationToSavedSeconds": saveTime]
                activity.add(try evidenceAttachment(measurement, named: "\(sample.filename)-measurement"))
            }
        }
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
        let malformedFilename = "Malformed-Validation-Backup.json"
        exportValidationFixture(named: malformedFilename)
        let baseline = try snapshot()
        XCTAssertEqual(baseline["readableTripCount"] as? Int, 1)
        XCTAssertEqual(baseline["pinCount"] as? Int, 1)
        let original = try settings(baseline)
        app.buttons["Import and export"].tap()
        visible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Backup contents'")).firstMatch).tap()
        app.buttons["Settings"].tap()
        app.buttons["Export backup"].tap()
        app.buttons["Export settings"].tap()
        capture("32-native-settings-export-picker")
        openLocalFilesStorage()
        capture("33-local-export-destination")
        saveToLocalFiles()
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
        // Back retains the valid preview. Canceling Files while choosing a
        // replacement must keep that preview available and release the picker.
        let review = app.navigationBars["Review import"]
        review.buttons["BackButton"].tap()
        let chooseFile = app.buttons["Choose backup file"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.tap()
        let cancelFiles = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons["Cancel"]
        XCTAssertTrue(cancelFiles.waitForExistence(timeout: 25))
        cancelFiles.tap()
        XCTAssertTrue(app.staticTexts["No file selected. Your previous preview is unchanged."].waitForExistence(timeout: 10))
        XCTAssertTrue(chooseFile.isEnabled)
        app.buttons["Review selected backup"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertFalse(visible(app.buttons["backup.review.apply"]).isEnabled)

        // Replace through the real picker with truncated JSON. The rejection
        // must leave the previous preview available and let Files open again.
        review.buttons["BackButton"].tap()
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.tap()
        let invalidBackup = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
            "This isn't a complete Elsepin backup.")).firstMatch
        selectFile(named: malformedFilename, captureName: "34a-malformed-json-in-files", until: invalidBackup)
        XCTAssertFalse(review.exists)
        XCTAssertTrue(chooseFile.isEnabled)
        capture("34b-malformed-json-rejected")
        app.buttons["Review selected backup"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertFalse(visible(app.buttons["backup.review.apply"]).isEnabled)
        review.buttons["BackButton"].tap()
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.tap()
        selectFile(named: filename, captureName: "34c-valid-json-retry-in-files", until: review)
        XCTAssertFalse(visible(app.buttons["backup.review.apply"]).isEnabled)
        visible(app.buttons["Cancel import"]).tap()
        app.buttons["Close backup test"].tap()
        let afterCancel = try snapshot()
        XCTAssertTrue(NSDictionary(dictionary: try settings(afterCancel)).isEqual(to: changed),
            "Canceling the picker or review, or rejecting malformed JSON, changed settings")
        XCTAssertEqual(afterCancel["tripCount"] as? Int, baseline["tripCount"] as? Int)
        XCTAssertEqual(afterCancel["pinCount"] as? Int, baseline["pinCount"] as? Int)

        openImport(named: filename)
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        let drive = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Drive preset'")).firstMatch
        visible(drive).tap()
        XCTAssertEqual(drive.value as? String, "Not selected")
        capture("35-import-leaves-drive-unchecked")
        applyImport()
        let beforeRelaunch = try snapshot()
        add(try evidenceAttachment(beforeRelaunch, named: "selective-backup-before-relaunch"))
        let partial = try settings(beforeRelaunch)
        var expectedPartial = original
        var speeds = try XCTUnwrap(original["usualSpeeds"] as? [String: Any])
        speeds["drive"] = 1
        expectedPartial["usualSpeeds"] = speeds
        XCTAssertTrue(NSDictionary(dictionary: partial).isEqual(to: expectedPartial), "Selective import changed an unchecked value or missed a selected value")

        app.terminate()
        app.launchArguments.append("--preserve-backup-test-data")
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        let partialAfterRelaunch = try snapshot()
        add(try evidenceAttachment(partialAfterRelaunch, named: "selective-backup-after-relaunch"))
        XCTAssertTrue(NSDictionary(dictionary: try settings(partialAfterRelaunch)).isEqual(to: expectedPartial),
            "Selected settings or the unchecked Drive preset did not persist through relaunch")
        XCTAssertEqual(partialAfterRelaunch["tripCount"] as? Int, baseline["tripCount"] as? Int)
        XCTAssertEqual(partialAfterRelaunch["pinCount"] as? Int, baseline["pinCount"] as? Int)
        capture("35a-selective-settings-after-relaunch")

        openImport(named: filename)
        expandSettings()
        XCTAssertEqual(visible(drive).value as? String, "Not selected")
        visible(app.buttons["Select all settings"]).tap()
        XCTAssertEqual(visible(drive).value as? String, "Selected for import")
        XCTAssertTrue(visible(app.buttons["Settings · 1 selected"]).exists)
        applyImport()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: original))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        let reopened = try snapshot()
        XCTAssertTrue(NSDictionary(dictionary: try settings(reopened)).isEqual(to: original), "Restored settings did not persist through relaunch")
        XCTAssertEqual(reopened["tripCount"] as? Int, baseline["tripCount"] as? Int)
        XCTAssertEqual(reopened["pinCount"] as? Int, baseline["pinCount"] as? Int)
        openImport(named: filename)
        XCTAssertFalse(visible(app.buttons["backup.review.apply"]).isEnabled, "Reimport should have no settings left to change")
        expandSettings()
        let selectAll = app.buttons["Select all settings"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        XCTAssertFalse(selectAll.isEnabled, "All settings should match the restored backup")
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
