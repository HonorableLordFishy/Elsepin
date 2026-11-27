import XCTest
@testable import SessionPresentation

final class PairingFileImportTests: XCTestCase {
    private func destination() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("pairing.plist")
    }
    private func plist(_ value: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["fixture": value], format: .xml, options: 0)
    }
    func testRejectedCandidateNeverReplacesExistingPairingAndIsRemoved() throws {
        let url = try destination(), old = try plist("old"), candidate = try plist("candidate")
        try old.write(to: url)
        XCTAssertThrowsError(try PairingFileImport.install(candidate, at: url) { staged in
            XCTAssertEqual(try Data(contentsOf: staged), candidate)
            XCTAssertEqual(try Data(contentsOf: url), old)
            throw PairingFileImport.Failure.invalid
        })
        XCTAssertEqual(try Data(contentsOf: url), old)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path), ["pairing.plist"])
    }
    func testValidatedCandidateInstallsAndReplaces() throws {
        let url = try destination()
        for content in ["first", "second"] {
            let data = try plist(content)
            try PairingFileImport.install(data, at: url) { XCTAssertEqual(try Data(contentsOf: $0), data) }
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
    func testMalformedArrayAndOversizeInputCannotReachVendorDecoder() throws {
        let url = try destination(), old = try plist("old")
        try old.write(to: url)
        let array = try PropertyListSerialization.data(fromPropertyList: ["not a pairing"], format: .xml, options: 0)
        for data in [Data(), Data("<?xml <plist broken".utf8), array, Data(repeating: 0, count: PairingFileImport.maximumBytes + 1)] {
            XCTAssertThrowsError(try PairingFileImport.install(data, at: url) { _ in XCTFail("Invalid input reached vendor decoder") })
            XCTAssertEqual(try Data(contentsOf: url), old)
        }
    }

    func testSweepRemovesOnlyAbandonedPairingStages() throws {
        let livePairing = try destination()
        let directory = livePairing.deletingLastPathComponent()
        let importedStage = PairingFileImport.StagingSource.imported.stagedURL(in: directory)
        let onDeviceStage = PairingFileImport.StagingSource.onDevice.stagedURL(in: directory)
        let unrelatedFile = directory.appendingPathComponent(".pairing-note.plist")
        let unrelatedDirectory = PairingFileImport.StagingSource.imported.stagedURL(in: directory)
        let data = try plist("pairing")
        for file in [livePairing, importedStage, onDeviceStage, unrelatedFile] {
            try data.write(to: file)
        }
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: false)

        try PairingFileImport.removeAbandonedStagingFiles(in: directory)
        try PairingFileImport.removeAbandonedStagingFiles(in: directory)

        XCTAssertEqual(try Data(contentsOf: livePairing), data)
        XCTAssertEqual(try Data(contentsOf: unrelatedFile), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedStage.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: onDeviceStage.path))
    }
}
