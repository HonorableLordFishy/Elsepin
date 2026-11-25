#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Files fixture export is simulator-only")
#endif
import SwiftUI
import UniformTypeIdentifiers

/// Gives native import journeys disposable provider files without depending on
/// whether the document picker exposes the validation app's Documents folder.
struct ValidationFixtureExporter: View {
    let files: [URL]
    var onExported: (URL) -> Void = { _ in }
    @State private var document = FixtureDocument()
    @State private var filename = ""
    @State private var contentType = UTType.data
    @State private var exporting = false
    @State private var status = ""

    var body: some View {
        HStack {
            Menu("Stage test file") {
                ForEach(files, id: \.self) { file in
                    Button(file.lastPathComponent) { stage(file) }
                        .accessibilityIdentifier("validation.exportFixture.\(file.lastPathComponent)")
                }
            }
            .accessibilityIdentifier("validation.exportFixture")

            if !status.isEmpty {
                Text(status).font(.caption).lineLimit(1)
                    .accessibilityIdentifier("validation.fixtureExportStatus")
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: filename) { result in
            switch result {
            case .success(let url):
                onExported(url)
                status = "Staged \(url.lastPathComponent)"
            case .failure(let error):
                status = "Could not stage \(filename): \(error.localizedDescription)"
            }
        }
    }

    private func stage(_ file: URL) {
        filename = file.lastPathComponent
        status = ""
        do {
            document = FixtureDocument(data: try Data(contentsOf: file))
            switch file.pathExtension {
            case "gpx": contentType = ImportFileTypes.gpx
            case "json": contentType = .json
            default: contentType = .data
            }
            exporting = true
        } catch {
            status = "Could not stage \(filename): \(error.localizedDescription)"
        }
    }

    private struct FixtureDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.data, .json, ImportFileTypes.gpx] }
        var data = Data()

        init(data: Data = Data()) { self.data = data }
        init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
    }
}
