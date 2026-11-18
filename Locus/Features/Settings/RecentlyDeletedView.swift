import SwiftUI

struct RecentlyDeletedView: View {
    @ObservedObject private var bin = RecentlyDeletedStore.shared
    @EnvironmentObject private var library: TripLibrary
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selecting = false
    @State private var selection = DeletedItemsSelection()
    @State private var deleting: DeletedItemsDeletion?
    @State private var message: String?
    @State private var messageTitle = "Couldn't restore"
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var sweep: DeletedItemsSelectionSweep?
    private var visibleItems: [DeletedLibraryItem] { bin.items.filter { $0.isRetained(at: Date()) } }
    var body: some View {
        List {
            Section {
                if visibleItems.isEmpty { Text("Nothing recently deleted").foregroundStyle(.secondary) }
                ForEach(visibleItems) { item in
                    if selecting {
                        selectionRow(item)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            itemLabel(item)
                            let layout = typeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout())
                            layout {
                                Button("Restore") { restore(item) }.frame(minHeight: 44)
                                if !typeSize.isAccessibilitySize { Spacer() }
                                Button("Delete permanently", role: .destructive) { deleting = DeletedItemsDeletion(items: [item]) }.frame(minHeight: 44)
                            }.buttonStyle(.borderless).disabled(!bin.canEdit)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash") { deleting = DeletedItemsDeletion(items: [item]) }
                                .tint(.red).disabled(!bin.canEdit)
                            Button("Restore", systemImage: "arrow.uturn.backward") { restore(item) }
                                .tint(LocusTheme.accent).disabled(!bin.canEdit)
                        }
                    }
                }
                if let error = bin.error { Text(error).foregroundStyle(LocusTheme.statusWarn) }
            } footer: { Text(selecting ? "Drag down the circles to select several items. Kept for 30 days." : "Kept for 30 days.") }
        }
        .onPreferenceChange(DeletedSelectionFrames.self) { rowFrames = $0 }
        .overlay(alignment: .top) {
#if ELSEPIN_UI_TESTING
            ValidationGestureTraceView()
#endif
        }
        .onDisappear { sweep = nil; rowFrames = [:] }
        .shiftScreen().loggedNavigationTitle("Recently Deleted").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    sweep = nil; selecting.toggle(); selection.ids = []; rowFrames = [:]
                }.disabled(!selecting && visibleItems.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting, !visibleItems.isEmpty {
                HStack {
                    Button(selection.ids.count == visibleItems.count ? "Deselect All" : "Select All") {
                        sweep = nil
                        if selection.ids.count == visibleItems.count { selection.ids = [] }
                        else { selection.selectAll(visibleItems, now: Date()) }
                    }.frame(minHeight: 44)
                    Spacer()
                    Button(selection.ids.isEmpty ? "Delete All" : "Delete (\(selection.ids.count))", role: .destructive) {
                        sweep = nil
                        deleting = selection.ids.isEmpty ? DeletedItemsDeletion(items: visibleItems)
                            : selection.review(bin.items, now: Date())
                    }.frame(minHeight: 44).disabled(!bin.canEdit)
                }.font(.subheadline.weight(.semibold)).padding(.horizontal, 20)
                    .background(ShiftCanvas())
            }
        }
        .onAppear { bin.prune() }
        .onChange(of: bin.items) { _, items in
            sweep = nil
            selection.reconcile(with: items, now: Date())
        }
        .loggedAlert("Permanently delete \(deleting?.items.count ?? 0) \(deleting?.items.count == 1 ? "item" : "items")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            if let plan = deleting {
                Button("Permanently delete", role: .destructive) {
                    if bin.permanentlyDelete(plan) { selection.ids.subtract(plan.items.map(\.id)) }
                    else { messageTitle = "Couldn't delete selection"; message = bin.error }
                    deleting = nil
                }
            }
        } message: { Text("From Recently Deleted: \(deleting?.summary ?? ""). This cannot be undone. Items still in your saved library and any active route are kept.") }
        .loggedAlert(messageTitle, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
    private func selectionRow(_ item: DeletedLibraryItem) -> some View {
        HStack(spacing: 4) {
            // Only this gutter claims a drag. Text and trailing whitespace keep
            // native List scrolling; taps remain ordinary accessible buttons.
            DeletedSelectionCircle(selected: selection.ids.contains(item.id),
                tint: UIColor(LocusTheme.accent), onTap: { selection.toggle(item.id) },
                gesture: selectionDrag(from: item.id))
                .frame(width: 44, height: 52)
            Button { selection.toggle(item.id) } label: {
                itemLabel(item).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: DeletedSelectionFrames.self,
                    value: [item.id: geometry.frame(in: .global)])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PlaceLabel.readable(item.payload.name)), \(item.payload.kind), expires \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityValue(selection.ids.contains(item.id) ? "Selected" : "Not selected")
        .accessibilityAddTraits(selection.ids.contains(item.id) ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { selection.toggle(item.id) }
    }

    private func selectionDrag(from anchor: UUID) -> DeletedSelectionPanGesture {
        // List cells have separate hosting roots. Match the gesture and row
        // geometry in global space, not a named space across those roots.
        DeletedSelectionPanGesture(onChanged: { point in
                guard selecting, deleting == nil, point.y.isFinite else { return }
                let items = visibleItems
                if sweep == nil {
                    sweep = DeletedItemsSelectionSweep(anchor: anchor, orderedIDs: items.map(\.id), selectedIDs: selection.ids)
                }
                // Row bounds handle variable heights; nearest edges bridge gaps.
                // The immutable ordered range also covers rows skipped by touch events.
                let available = Set(items.map(\.id))
                guard let target = SelectionRowHitTest.target(y: point.y,
                    frames: rowFrames.filter { available.contains($0.key) }) else { return }
#if ELSEPIN_UI_TESTING
                ValidationGestureTrace.record("drag y=\(point.y) rows=\(rowFrames.count) anchor=\(items.firstIndex(where: { $0.id == anchor }) ?? -1) target=\(items.firstIndex(where: { $0.id == target }) ?? -1) bounds=\(String(describing: rowFrames[anchor]))")
#endif
                if let ids = sweep?.selection(through: target), ids != selection.ids { selection.ids = ids }
            }, onEnded: { sweep = nil })
    }

    private func itemLabel(_ item: DeletedLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PlaceLabel.readable(item.payload.name)).font(.headline).foregroundStyle(.primary)
            Text("\(item.payload.kind) · Expires \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func restore(_ item: DeletedLibraryItem) {
        messageTitle = "Couldn't restore"
        guard item.isRetained(at: Date()) else { bin.prune(); return }
        do {
            switch item.payload {
            case .trip(let trip):
                guard !library.trips.contains(where: { $0.id == trip.id }) else { throw RestoreError.exists }
                guard try library.merge([trip]) else { message = library.error; return }
            case .place(let place):
                guard !session.savedPins.contains(where: { $0.id == place.id }) else { throw RestoreError.exists }
                guard session.restoreFavorite(place) else { message = session.lastError; return }
            case .area(let area):
                guard !session.namedAreas.contains(where: { $0.id == area.id }) else { throw RestoreError.exists }
                guard session.replaceNamedAreas(session.namedAreas + [area]) else { message = session.lastError; return }
            }
            if !bin.remove(item.id) { message = "Restored. The old entry couldn't be removed from Recently Deleted; it is safe to delete that entry later." }
        } catch { message = error.localizedDescription }
    }
    private enum RestoreError: LocalizedError {
        case exists
        var errorDescription: String? { "An item with this identity is already saved. Keep it, or delete it before restoring the older version." }
    }
}

/// Give the circle gutter first refusal over List's native scrolling pan.
/// Drags on the text remain ordinary scrolling; taps still use the Button.
private struct DeletedSelectionPanGesture {
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void
}

private struct DeletedSelectionCircle: UIViewRepresentable {
    var selected: Bool
    var tint: UIColor
    var onTap: () -> Void
    var gesture: DeletedSelectionPanGesture
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        button.addGestureRecognizer(pan)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.setImage(UIImage(systemName: selected ? "checkmark.circle.fill" : "circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        button.tintColor = selected ? tint : .secondaryLabel
        button.isAccessibilityElement = false // The whole row exposes its selection action.
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DeletedSelectionCircle
        init(parent: DeletedSelectionCircle) { self.parent = parent }
        @objc func tap() { parent.onTap() }
        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
#if ELSEPIN_UI_TESTING
        ValidationGestureTrace.record("pan state \(recognizer.state.rawValue)")
#endif
        switch recognizer.state {
        case .began, .changed: parent.gesture.onChanged(recognizer.location(in: nil))
        case .ended:
            parent.gesture.onChanged(recognizer.location(in: nil))
            parent.gesture.onEnded()
        case .cancelled, .failed: parent.gesture.onEnded()
        default: break
        }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
    }
}

private struct DeletedSelectionFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
