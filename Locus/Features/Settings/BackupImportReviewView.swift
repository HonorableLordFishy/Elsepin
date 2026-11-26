import SwiftUI

struct BackupImportReviewView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var library: TripLibrary
    @EnvironmentObject private var planner: RoutePlanner
    @EnvironmentObject private var preferences: SessionPreferences
    let backup: LibraryBackup
    let finished: (String) -> Void
    @Binding var selection: BackupImportSelection
    @State private var confirmation = false
    @State private var confirmedContext: BackupImportContext?
    @State private var message: String?

    private var current: BackupImportContext {
        BackupImportContext(preferences: session.backupPreferences,
            places: session.savedPins.map(\.backupPlace), trips: library.trips, areas: session.namedAreas)
    }

    var body: some View {
        let review = BackupImportReview(backup: backup, current: current)
        let result = Result { try review.plan(selection) }
        let plan = try? result.get()
        let settings = review.changes
        let changedSettings = Set(settings.filter(\.changesValue).map(\.key))
        let available = review.defaultSelection
        let appliedSettings = Dictionary(uniqueKeysWithValues: (plan.map { review.settingChanges(in: $0) } ?? [])
            .map { ($0.key, $0.after) })
        List {
            Section {
                if let plan {
                    Text(plan.summary)
                        .accessibilityIdentifier("backup.review.summary")
                } else if case .failure(let error) = result {
                    Text(error.localizedDescription).font(.footnote)
                }
            } header: {
                Text("Selected for import")
            }.shiftSettingsRows()

            if !settings.isEmpty {
                let count = selection.settings.intersection(changedSettings).count
                let status = count == 0 ? "Keep current" : "\(count) selected"
                Section {
                    DisclosureGroup("Settings · \(status)") {
                        selectionButtons(all: changedSettings, values: $selection.settings, name: "settings")
                        ForEach(BackupSettingGroup.allCases) { group in
                            let changes = settings.filter { $0.changesValue && $0.key.group == group }
                            if !changes.isEmpty {
                                Text(group.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(changes) { change in
                                    let after = appliedSettings[change.key] ?? change.after
                                    BackupImportCheckRow(title: change.key.title, detail: "\(change.before) → \(after)",
                                        isSelected: selected(change.key, in: $selection.settings))
                                }
                            }
                        }
                        let unchanged = settings.filter { !$0.changesValue }
                        if !unchanged.isEmpty {
                            DisclosureGroup("Already the same · \(unchanged.count)") {
                                ForEach(unchanged) { change in
                                    BackupImportCheckRow(title: change.key.title, detail: change.before,
                                        isSelected: .constant(false), enabled: false)
                                }
                            }
                        }
                    }
                }.shiftSettingsRows()
            }
            if !backup.trips.isEmpty || !backup.places.isEmpty || !(backup.areas ?? []).isEmpty {
                Section {
                    if !backup.trips.isEmpty {
                        DisclosureGroup("Routes") {
                            selectionButtons(all: available.trips, values: $selection.trips, name: "routes")
                            ForEach(backup.trips) { trip in
                                let exists = review.existingTrips.contains(trip.id)
                                BackupImportCheckRow(title: trip.name,
                                    detail: exists ? "Already saved — keep current version" : "Add route · \(trip.points.count) points · \(trip.stops.count) stops\n\(trip.originName) → \(trip.destinationName)",
                                    isSelected: selected(trip.id, in: $selection.trips), enabled: !exists)
                            }
                        }.badge(selection.trips.intersection(available.trips).count)
                    }
                    if !backup.places.isEmpty {
                        DisclosureGroup("Pins") {
                            selectionButtons(all: available.places, values: $selection.places, name: "pins")
                            ForEach(backup.places, id: \.id) { place in
                                let exists = review.existingPlaces.contains(place.id)
                                BackupImportCheckRow(title: place.name,
                                    detail: exists ? "Already saved — keep current version" : "\(place.latitude.formatted(.number.precision(.fractionLength(5)))), \(place.longitude.formatted(.number.precision(.fractionLength(5))))",
                                    isSelected: selected(place.id, in: $selection.places), enabled: !exists)
                            }
                        }.badge(selection.places.intersection(available.places).count)
                    }
                    if let areas = backup.areas, !areas.isEmpty {
                        DisclosureGroup("Named areas") {
                            selectionButtons(all: available.areas, values: $selection.areas, name: "areas")
                            ForEach(areas) { area in
                                let exists = review.existingAreas.contains(area.id)
                                BackupImportCheckRow(title: area.name,
                                    detail: exists ? "Already saved — keep current boundary" : "Add named area · \(area.points.count) boundary points",
                                    isSelected: selected(area.id, in: $selection.areas), enabled: !exists)
                            }
                        }.badge(selection.areas.intersection(available.areas).count)
                    }
                }.shiftSettingsRows()
            }
            Section {
                if let plan, plan.settingKeys.contains(.recentHistoryRetention),
                   let retention = plan.preferences?.display?.recentHistoryRetention, retention != .forever {
                    Text("Recent locations older than the selected limit (\(retention.title)) will be removed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Import selected changes") {
                    confirmedContext = current
                    confirmation = true
                }
                .frame(minHeight: 44)
                .disabled((plan?.count ?? 0) == 0 || plan?.needsStoppedSession(hasSession: session.hasSession, isBusy: session.isBusy) == true)
                .accessibilityIdentifier("backup.review.apply")
                .loggedConfirmationDialog("Apply selected changes?", isPresented: $confirmation, titleVisibility: .visible) {
                    Button("Import selected changes") { apply() }
                        .accessibilityIdentifier("backup.review.confirmApply")
                    Button("Keep reviewing", role: .cancel) { }
                } message: {
                    Text(plan?.summary ?? "No changes selected")
                }
                Button("Cancel import", role: .cancel) { finished("Import canceled. Nothing was changed.") }
                    .frame(minHeight: 44)
            } footer: {
                if plan?.needsStoppedSession(hasSession: session.hasSession, isBusy: session.isBusy) == true {
                    Text("Stop spoofing before applying settings, or import library items only.")
                }
            }.shiftSettingsRows()
            if let message { Section { Text(message).font(.footnote) }.shiftSettingsRows() }
        }
        .shiftSettingsScreen().loggedNavigationTitle("Review import").navigationBarTitleDisplayMode(.inline)
    }

    private func selected<ID: Hashable>(_ id: ID, in values: Binding<Set<ID>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { flag in
            if flag { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }
    private func selectionButtons<ID: Hashable>(all: Set<ID>, values: Binding<Set<ID>>, name: String) -> some View {
        let selectAll = Button {
            values.wrappedValue = all
        } label: {
            Text("Select all \(name)").frame(minHeight: 44)
        }.disabled(all.isEmpty)
        let selectNone = Button {
            values.wrappedValue = []
        } label: {
            Text("Select none").frame(minHeight: 44)
        }.disabled(values.wrappedValue.isEmpty)
        return ViewThatFits(in: .horizontal) {
            HStack {
                selectAll
                Spacer()
                selectNone
            }
            VStack(alignment: .leading, spacing: 8) {
                selectAll
                selectNone
            }
        }.buttonStyle(.borderless)
    }
    private func apply() {
        guard library.isCurrentWorkspace, !DevModeController.shared.switching else {
            message = "The data workspace changed. Reopen the backup and review it again."; return
        }
        let context = current
        guard context == confirmedContext else {
            message = "Your library or settings changed while reviewing. Check the updated preview and confirm again."
            return
        }
        do {
            let plan = try BackupImportReview(backup: backup, current: context).plan(selection)
            guard !plan.needsStoppedSession(hasSession: session.hasSession, isBusy: session.isBusy) else {
                message = "Stop spoofing before applying changed settings, or uncheck Settings to import only library items."
                return
            }
            guard plan.count > 0 else { return }
            let places = try LibraryMerge.places(local: context.places, incoming: plan.places)
            let areas = plan.areas.isEmpty ? context.areas : try LibraryMerge.areas(local: context.areas, incoming: plan.areas)
            if !plan.trips.isEmpty {
                guard try library.merge(plan.trips) else { message = library.error; return }
            }
            if !plan.areas.isEmpty, !session.replaceNamedAreas(areas) {
                message = "Areas could not be saved. Your settings are unchanged. Any routes already added will be kept on retry."
                return
            }
            if !plan.places.isEmpty || plan.preferences != nil {
                session.importLibraryPlaces(places, settings: plan.preferences, updatePlaces: !plan.places.isEmpty)
            }
            if let settings = plan.preferences { planner.preferWalkingPaths = settings.preferWalkingPaths }
            finished("Import complete. \(plan.summary).")
        } catch { message = error.localizedDescription }
    }
}

private struct BackupImportCheckRow: View {
    let title: String
    let detail: String
    @Binding var isSelected: Bool
    var enabled = true
    var body: some View {
        Button { isSelected.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: enabled && isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(enabled && isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityValue(enabled ? (isSelected ? "Selected for import" : "Not selected") : "No change")
        .accessibilityHint(enabled ? "Double tap to include or exclude this change." : "Your current item is kept.")
    }
}
