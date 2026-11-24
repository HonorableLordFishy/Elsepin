import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LibraryBackupInput: ObservableObject {
    @Published var isFilePickerPresented = false
    @Published private(set) var isChoosingFile = false
    @Published private(set) var state = BackupImportState()
    private var pickedFile: BackupFileAccess?
    private var clipboardLoad: Progress?
    private var preparation: Task<Void, Never>?

    func chooseFile() {
        guard !isChoosingFile, !state.isLoading else { return }
        state.notice(nil)
        isChoosingFile = true
        isFilePickerPresented = true
    }

    func picked(_ url: URL) {
        guard isChoosingFile else { return }
        pickedFile = BackupFileAccess(url)
        isFilePickerPresented = false
    }

    func dismissFilePicker() { isFilePickerPresented = false }

    func filePickerDidDismiss() {
        guard isChoosingFile else { return }
        isChoosingFile = false
        let access = pickedFile
        pickedFile = nil
        guard let access else {
            state.notice("No file selected. Your previous preview is unchanged.")
            return
        }
        // A fast read can finish immediately. Wait for the sheet to dismiss
        // before decoding so its result can push Review on the same stack.
        guard let id = state.begin() else { return }
        prepare(id) {
            defer { withExtendedLifetime(access) {} }
            return try BackupImportReader.file(access.url)
        }
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
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Ask for JSON explicitly and accept providers that identify the same
        // bytes as generic text/data. Import mode returns a temporary copy.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data, .item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) } else { onCancel() }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
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
