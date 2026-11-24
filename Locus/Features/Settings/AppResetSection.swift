import SwiftUI

struct AppResetSection: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var reset: AppResetController
    @State private var reviewing: AppResetScope?
    var body: some View {
        Section {
            Button("Restore default settings…") { reviewing = .settings }
                .frame(minHeight: 44)
            NavigationLink { AppWipeChoicesView() } label: {
                Label("Wipe everything…", systemImage: "trash").foregroundStyle(.red)
            }.frame(minHeight: 44)
        } header: { Text("Reset Elsepin") } footer: {
            Text(AppDataWorkspace.shared.isDemo ? "Turn off Dev Mode before resetting the app." : "Stop spoofing and finish pairing or connection checks before resetting.")
        }.shiftSettingsRows()
        .disabled(reset.isResetting || session.hasSession || session.isBusy || AppDataWorkspace.shared.isDemo)
        .sheet(item: $reviewing) { AppResetReview(scope: $0) }
    }
}

private struct AppWipeChoicesView: View {
    @State private var reviewing: AppResetScope?
    var body: some View {
        List {
            Section {
                choice(.full, detail: "Remove local data, settings and pairing. Start setup again.")
                choice(.keepSetup, detail: "Remove local data and settings. Keep device pairing, the tunnel address and setup progress.")
            } footer: { Text("Both wipes permanently erase your library and Recently Deleted. Files exports and iOS settings stay in place.") }.shiftSettingsRows()
        }.shiftSettingsScreen().loggedNavigationTitle("Wipe everything").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewing) { AppResetReview(scope: $0) }
    }
    private func choice(_ scope: AppResetScope, detail: String) -> some View {
        Button { reviewing = scope } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(scope.title).foregroundStyle(.red)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }
}

private struct AppResetReview: View {
    let scope: AppResetScope
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var preferences: SessionPreferences
    @EnvironmentObject private var library: TripLibrary
    @EnvironmentObject private var privacy: AppPrivacyController
    @EnvironmentObject private var updates: AppUpdateController
    @EnvironmentObject private var reset: AppResetController
    var body: some View {
        NavigationStack {
            List {
                Section(scope.wipesData ? "Permanently erased" : "Restored to defaults") {
                    if scope.wipesData {
                        Text("Pins, routes, areas, history and Recently Deleted.")
                        Text("Recovery copies, diagnostics and saved helper sign-ins.")
                        if scope == .full { Text("Device pairing and setup. You’ll need to pair again.") }
                    } else {
                        Text("Appearance, icon, speeds, controls, privacy, notifications and widgets.")
                    }
                }.shiftSettingsRows()
                Section("What you keep") {
                    Text(scope.keptSummary)
                }.shiftSettingsRows()
                Section {
                    if scope.wipesData { Text("Export a backup first. This wipe is permanent.") }
                    Text("Open drafts close. If App Lock is on, you’ll authenticate before it turns off.")
                    DisclosureGroup("More details") {
                        if scope.wipesData { Text("App preferences and experimental settings return to their defaults.") }
                        else { Text("Experimental settings also return to their defaults.") }
                        Text("Files, server accounts, installed widgets, iOS permissions, Developer Mode, host trust and LocalDevVPN stay in place.")
                    }
                }.font(.subheadline).shiftSettingsRows()
                Section {
                    Button(scope.title, role: .destructive) {
                        dismiss()
                        Task {
                            await reset.perform(scope, session: session, pairing: pairing,
                                preferences: preferences, library: library, privacy: privacy, updates: updates)
                        }
                    }.frame(minHeight: 44).disabled(reset.isResetting || session.hasSession || session.isBusy || AppDataWorkspace.shared.isDemo)
                }.shiftSettingsRows()
            }.shiftSettingsScreen().loggedNavigationTitle("Confirm reset").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
