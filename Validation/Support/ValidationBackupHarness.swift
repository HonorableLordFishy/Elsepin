#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Backup fixtures are simulator tests only")
#endif
import SwiftUI
import UIKit

/// The real exporter and importer own all backup writes/restores. This fixture
/// supplies disposable settings, changes them on request, and observes disk data.
struct ValidationBackupHarness: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var preferences: SessionPreferences
    @EnvironmentObject private var library: TripLibrary
    @StateObject private var planner = RoutePlanner()
    @State private var showing = false
    @State private var started = false
    @State private var snapshot = "{}"

    static var observedExportURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ValidationSettingsExport.json")
    }

    static func stageMalformedBackup() throws {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let file = documents.appendingPathComponent("Malformed-Validation-Backup.json")
        try Data("{\"format\":\"Shift library\",\"version\":".utf8).write(to: file, options: .atomic)
    }

    private struct ObservedExport: Decodable {
        let filename: String
        let text: String
    }

    private func observedExport() throws -> ObservedExport? {
        let url = Self.observedExportURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ObservedExport.self, from: Data(contentsOf: url))
    }

    private func refresh() {
        do {
            let reloaded = TripLibrary()
            var result: [String: Any] = [
                "settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(session.backupPreferences)),
                "tripCount": reloaded.trips.count, "pinCount": session.savedPins.count
            ]
            if reloaded.error == nil { result["readableTripCount"] = reloaded.trips.count }
            if ["backup-unreadable-trips", "backup-late-trip-corruption"].contains(ValidationFixture.scenario) {
                result["originalKept"] = try Data(contentsOf: AppDataWorkspace.file("Trips.json")) == ValidationFixture.unreadableTrips
            }
            if let export = try observedExport() {
                let data = Data(export.text.utf8)
                let backup = try LibraryBackup.decode(data)
                result["export"] = try JSONSerialization.jsonObject(with: data)
                result["valid"] = backup.isValid
                result["file"] = export.filename
            }
            snapshot = String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self)
        } catch { snapshot = "ERROR: \(error.localizedDescription)" }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("Import and export") { showing = true }
                if ValidationFixture.scenario == "backup-late-trip-corruption" {
                    Button("Corrupt trips after opening library") {
                        guard library.trips.count == 1 else { snapshot = "ERROR: The initial route did not load"; return }
                        do {
                            try ValidationFixture.unreadableTrips.write(to: AppDataWorkspace.file("Trips.json"), options: .atomic)
                            refresh()
                        } catch { snapshot = "ERROR: \(error.localizedDescription)" }
                    }
                }
                Button("Change disposable settings") {
                    session.setUsualSpeedMPH(6, for: .walk)
                    session.setUsualSpeedMPH(1, for: .drive)
                    session.smoothMovement = false
                    preferences.mapPinSize = 22
                    preferences.mapPinVisibilityMiles = 1
                    preferences.showSavedPinsOnMap = false
                    refresh()
                }
                Button("Read settings and export") { refresh() }
                Button("Copy exported backup text") {
                    do {
                        guard let export = try observedExport() else { snapshot = "ERROR: No actual export to copy"; return }
                        UIPasteboard.general.string = export.text
                    } catch { snapshot = "ERROR: \(error.localizedDescription)" }
                }
                Text(snapshot).font(.system(size: 7)).lineLimit(1)
                    .accessibilityIdentifier("validation.backupSnapshot")
            }.navigationTitle("Backup validation")
            .navigationDestination(isPresented: $showing) {
                // Match Settings' real navigation. A second modal shell around
                // the system document UI is not part of the production flow.
                LibraryBackupView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Close backup test") { showing = false }
                    } }
            }
        }
        // Navigation destinations share the stack's environment. Installing
        // this only on its first screen leaves the pushed review without it.
        // Production RootView supplies its planner above navigation as well.
        .environmentObject(planner)
        .task {
            guard !started else { return }; started = true
            if !ProcessInfo.processInfo.arguments.contains("--preserve-backup-test-data") {
                session.setUsualSpeedMPH(4.5, for: .walk)
                session.setUsualSpeedMPH(85, for: .drive)
                session.smoothMovement = true
                preferences.mapPinSize = 52
                preferences.mapPinVisibilityMiles = 7
                preferences.showSavedPinsOnMap = true
                preferences.speedUnit = .mph
            }
            refresh()
        }
    }
}
