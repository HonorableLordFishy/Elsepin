import SwiftUI

struct DevModeSection: View {
    @ObservedObject private var demo = DevModeController.shared
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var reset: AppResetController
    @State private var confirm = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { demo.enabled }, set: { enabled in
                if enabled { confirm = true } else { switchMode(false) }
            })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dev Mode")
                    Text("Use a demo dataset instead of your own data.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(demo.switching)
            .accessibilityIdentifier("settings.devMode")
        } header: { Text("Testing tools") } footer: {
            Text("Turn off Dev Mode to return to your library and preferences. Each new demo starts fresh. Pairing, accounts, security and the app icon are shared.")
        }.shiftSettingsRows()
        .loggedAlert("Use demo data?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) { }
            Button("Enable Dev Mode") { switchMode(true) }
        } message: {
            Text("Explore sample pins, routes and areas. Movement starts only when you choose. Cloud checks use your configured helper.")
        }
        .loggedAlert("Dev Mode", isPresented: Binding(get: { demo.error != nil }, set: { if !$0 { demo.error = nil } })) {
            Button("OK", role: .cancel) { demo.error = nil }
        } message: { Text(demo.error ?? "") }
    }

    private func switchMode(_ enabled: Bool) {
        Task { await demo.setEnabled(enabled, session: session, reset: reset) }
    }
}
