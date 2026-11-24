import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LibraryBackupInput: ObservableObject {
    @Published private(set) var isChoosingFile = false
    @Published private(set) var state = BackupImportState()
    private var clipboardLoad: Progress?
    private var preparation: Task<Void, Never>?

    func chooseFile() {
        guard !isChoosingFile, !state.isLoading else { return }
        state.notice(nil)
        isChoosingFile = true
    }

    func picked(_ url: URL) {
        guard isChoosingFile else { return }
        let access = BackupFileAccess(url)
        isChoosingFile = false
        guard let id = state.begin() else { return }
        prepare(id) {
            defer { withExtendedLifetime(access) {} }
            return try BackupImportReader.file(access.url)
        }
    }

    func cancelledFileSelection() {
        endFileSelection(notice: "No file selected. Your previous preview is unchanged.")
    }

    func filePickerUnavailable() {
        endFileSelection(notice: "Files couldn’t open. Tap Choose backup file to try again.")
    }

    private func endFileSelection(notice: String) {
        guard isChoosingFile else { return }
        isChoosingFile = false
        state.notice(notice)
    }

    func paste(_ provider: NSItemProvider) {
        guard !isChoosingFile, let id = state.begin() else { return }
        clipboardLoad = provider.loadObject(ofClass: NSString.self) { [weak self] object, error in
            let text = object as? String
            let failure = error ?? BackupImportError.invalidContent
            Task { @MainActor [weak self] in
                guard let self, self.state.operation == id else { return }
                self.clipboardLoad = nil
                if let text {
                    self.prepare(id) { try BackupImportReader.text(text) }
                } else {
                    self.state.finish(id, result: .failure(failure))
                }
            }
        }
    }

    func clearPreview() { state.clearPreview() }

    func cancelPreparation() {
        clipboardLoad?.cancel()
        clipboardLoad = nil
        preparation?.cancel()
        preparation = nil
        state.cancel()
    }

    private func prepare(_ id: UUID, _ load: @escaping @Sendable () throws -> BackupImportPreview) {
        let worker = Task.detached(priority: .userInitiated) { Result { try load() } }
        preparation = Task {
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            state.finish(id, result: result)
            preparation = nil
        }
    }
}

struct BackupDocumentPicker: UIViewControllerRepresentable {
    let isPresented: Bool
    let onPick: (URL) -> Void
    let onCancel: () -> Void
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel, onUnavailable: onUnavailable)
    }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ presenter: UIViewController, context: Context) {
        if isPresented { context.coordinator.present(from: presenter) }
    }

    static func dismantleUIViewController(_ presenter: UIViewController, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        let onUnavailable: () -> Void
        private var picker: UIDocumentPickerViewController?
        private var presentationAttempt: Task<Void, Never>?
        private var finishing = false

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void, onUnavailable: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
            self.onUnavailable = onUnavailable
        }

        func present(from presenter: UIViewController) {
            guard picker == nil, presentationAttempt == nil else { return }
            presentationAttempt = Task { @MainActor [weak self, weak presenter] in
                guard let self else { return }
                defer { presentationAttempt = nil }
                // SwiftUI can update the anchor during attachment or while a
                // previous presentation finishes. Allow that transition to settle.
                for _ in 0..<6 {
                    guard !Task.isCancelled else { return }
                    if let presenter, presenter.viewIfLoaded?.window != nil,
                       presenter.presentedViewController == nil, presenter.transitionCoordinator == nil {
                        await showPicker(from: presenter)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if !Task.isCancelled { onUnavailable() }
            }
        }

        private func showPicker(from presenter: UIViewController) async {
            // Ask for JSON explicitly and accept providers that identify the same
            // bytes as generic text/data. Import mode returns a temporary copy.
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data, .item], asCopy: true)
            self.picker = picker
            picker.delegate = self
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            presenter.present(picker, animated: true)
            picker.presentationController?.delegate = self

            // UIKit does not call a present completion if it refuses the
            // presentation. Check that it actually installed this controller.
            await Task.yield()
            guard !Task.isCancelled, self.picker === picker, !finishing else { return }
            if picker.presentingViewController == nil {
                self.picker = nil
                onUnavailable()
            }
        }

        func dismantle() {
            let wasChoosingFile = presentationAttempt != nil || picker != nil
            presentationAttempt?.cancel()
            presentationAttempt = nil
            let activePicker = picker
            picker = nil
            activePicker?.delegate = nil
            activePicker?.presentationController?.delegate = nil
            if let activePicker, activePicker.presentingViewController != nil, !activePicker.isBeingDismissed {
                activePicker.dismiss(animated: false)
            }
            // Representable teardown may occur inside a SwiftUI update.
            if wasChoosingFile { Task { @MainActor in onCancel() } }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(controller, selection: urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(controller, selection: nil)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard let picker, picker === presentationController.presentedViewController else { return }
            finish(picker, selection: nil)
        }

        private func finish(_ controller: UIDocumentPickerViewController, selection: URL?) {
            guard picker === controller, !finishing else { return }
            finishing = true
            let complete = { [self] in
                guard picker === controller else { return }
                if let selection { onPick(selection) } else { onCancel() }
                picker = nil
                finishing = false
            }
            // The picker may already be closing itself. Deliver its result
            // after the actual UIKit transition so the Settings stack can push.
            if controller.isBeingDismissed, let transition = controller.transitionCoordinator,
               transition.animate(alongsideTransition: nil, completion: { _ in complete() }) {
                return
            }
            if controller.presentingViewController != nil, !controller.isBeingDismissed {
                controller.dismiss(animated: true, completion: complete)
            } else {
                complete()
            }
        }
    }
}

/// A UIKit paste target receives only the item handed over by the system when
/// the user taps the control. Nothing reads the general pasteboard directly.
struct BackupPasteControl: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let onPaste: (NSItemProvider) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPaste: onPaste) }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.cornerStyle = .capsule
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.accessibilityLabel = "Paste backup text"
        control.accessibilityHint = "Analyze copied JSON and review individual changes before importing."
        control.accessibilityIdentifier = "backup.paste"
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
        control.isUserInteractionEnabled = isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPasteControl, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return CGSize(width: max(64, size.width), height: max(44, size.height))
    }

    @MainActor
    final class Coordinator: NSObject, UIPasteConfigurationSupporting {
        var pasteConfiguration: UIPasteConfiguration? = UIPasteConfiguration(forAccepting: NSString.self)
        var onPaste: (NSItemProvider) -> Void

        init(onPaste: @escaping (NSItemProvider) -> Void) { self.onPaste = onPaste }

        func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
        }

        func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
            onPaste(provider)
        }
    }
}

/// Immutable access lease, released after the worker (also on failure/cancellation).
private final class BackupFileAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}
