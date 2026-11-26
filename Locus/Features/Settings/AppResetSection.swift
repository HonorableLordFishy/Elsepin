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
                if scope.wipesData {
                    Section {
                        Text("Saved pins, routes, named areas, recent history and Recently Deleted.")
                        Text("Recovery copies, diagnostics, widget data and notifications.")
                        Text("Saved cloud and Windows helper connections. You’ll need to reconnect them.")
                        if scope == .full {
                            Text("Device pairing, tunnel address and setup progress. You’ll need to set up Elsepin again.")
                        }
                    } header: {
                        Text("Permanently erased")
                    } footer: {
                        Text("Export a backup before wiping if you want a copy of your library.")
                    }.shiftSettingsRows()
                }
                Section("Restored to defaults") {
                    Text("The Home Screen icon, appearance, movement, privacy, reminders, widget choices and experimental settings.")
                    if scope == .settings {
                        Text("Cloud and Windows helper checks turn off. Saved connections are kept.")
                    }
                }.shiftSettingsRows()
                Section {
                    if scope == .settings {
                        Text("Library, recent history, Recently Deleted, recovery copies and diagnostics.")
                    }
                    if scope != .full {
                        Text("Device pairing, tunnel address and setup progress.")
                    }
                    Text("Exported files, helper server accounts, installed widgets and iOS settings.")
                } header: {
                    Text("What you keep")
                } footer: {
                    if preferences.appLockEnabled {
                        Text("Open drafts close. Confirm with device authentication to turn off App Lock.")
                    } else {
                        Text("Open drafts close.")
                    }
                }.shiftSettingsRows()
                Section {
                    Button(scope.title, role: .destructive) {
                        dismiss()
                        Task {
                            await reset.perform(scope, session: session, pairing: pairing,
                                preferences: preferences, library: library, privacy: privacy, updates: updates)
                        }
                    }.frame(minHeight: 44).disabled(reset.isResetting || session.hasSession || session.isBusy || AppDataWorkspace.shared.isDemo)
                        .accessibilityIdentifier("reset.confirm")
                }.shiftSettingsRows()
            }.shiftSettingsScreen().loggedNavigationTitle("Confirm reset").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
