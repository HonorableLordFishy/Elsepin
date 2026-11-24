import SwiftUI
import UIKit

@MainActor
final class LibraryBackupInput: ObservableObject {
    @Published var isChoosingFile = false
    @Published private(set) var state = BackupImportState()
    private var clipboardLoad: Progress?
    private var preparation: Task<Void, Never>?

    func chooseFile() {
        guard !isChoosingFile, !state.isLoading else { return }
        state.notice(nil)
        isChoosingFile = true
    }

    func picked(_ result: Result<[URL], Error>) {
        // The importer clears isChoosingFile before delivering its result.
        switch result {
        case .success(let urls):
            guard let url = urls.first else { cancelledFileSelection(); return }
            guard let id = state.begin() else { return }
            let access = BackupFileAccess(url)
            prepare(id) {
                defer { withExtendedLifetime(access) {} }
                return try BackupImportReader.file(access.url)
            }
        case .failure(let error):
            state.notice(error.localizedDescription)
        }
    }

    func cancelledFileSelection() {
        state.notice(state.preview == nil ? "No file selected." : "No file selected. Your previous preview is unchanged.")
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
