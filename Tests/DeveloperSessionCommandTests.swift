import Foundation
import XCTest
@testable import SessionPresentation

final class DeveloperSessionCommandTests: XCTestCase {
    private enum Failure: Error, Equatable {
        case bootstrap, nativeCommand
    }

    func testMatchingSessionCanSetAndClearWhileBootstrapIsUnavailable() throws {
        let (pairing, session) = try makePairing()
        defer { try? FileManager.default.removeItem(at: pairing.deletingLastPathComponent()) }
        for command in ["set", "clear"] {
            var attempts = 0
            let result: Result<Void, Failure> = DeveloperSessionCommand.run(
                requested: session, connected: session,
                discard: { XCTFail("Keep the working service for \(command)") },
                open: {
                    XCTFail("\(command) should not need bootstrap")
                    return .failure(.bootstrap)
                },
                perform: {
                    attempts += 1
                    return .success(())
                })
            XCTAssertNoThrow(try result.get())
            XCTAssertEqual(attempts, 1)
        }
    }

    func testMatchingSessionReturnsNativeFailureWithoutRetryingCommand() throws {
        let (pairing, session) = try makePairing()
        defer { try? FileManager.default.removeItem(at: pairing.deletingLastPathComponent()) }
        var attempts = 0
        let result: Result<Void, Failure> = DeveloperSessionCommand.run(
            requested: session, connected: session, discard: { XCTFail("Unexpected preflight discard") },
            open: {
                XCTFail("Do not retry an ambiguous write through a new connection")
                return .failure(.bootstrap)
            },
            perform: {
                attempts += 1
                return .failure(.nativeCommand)
            })
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? Failure, .nativeCommand) }
        XCTAssertEqual(attempts, 1)
    }

    func testFreshEndpointOrPairingRequiresBootstrapBeforeWriting() throws {
        let (pairing, session) = try makePairing()
        defer { try? FileManager.default.removeItem(at: pairing.deletingLastPathComponent()) }
        let otherEndpoint = try XCTUnwrap(DeveloperSessionContext(endpoint: "10.7.0.2", pairingPath: pairing.path))
        try Data([1, 2]).write(to: pairing, options: .atomic)
        let replacedPairing = try XCTUnwrap(DeveloperSessionContext(endpoint: session.endpoint, pairingPath: pairing.path))
        XCTAssertNotEqual(replacedPairing, session)
        let contexts: [(DeveloperSessionContext?, DeveloperSessionContext?)] =
            [(session, nil), (otherEndpoint, session), (replacedPairing, session), (nil, session)]
        for (requested, connected) in contexts {
            var steps: [String] = []
            let result: Result<Void, Failure> = DeveloperSessionCommand.run(
                requested: requested, connected: connected,
                discard: { steps.append("discard") },
                open: {
                    steps.append("open")
                    return .failure(.bootstrap)
                },
                perform: {
                    steps.append("perform")
                    return .success(())
                })
            XCTAssertEqual(steps, ["discard", "open"])
            XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? Failure, .bootstrap) }
        }
    }

    func testCommandRunsAfterFreshBootstrapSucceeds() throws {
        let (pairing, session) = try makePairing()
        defer { try? FileManager.default.removeItem(at: pairing.deletingLastPathComponent()) }
        var steps: [String] = []
        let result: Result<Void, Failure> = DeveloperSessionCommand.run(
            requested: session, connected: nil,
            discard: { steps.append("discard") },
            open: {
                steps.append("open")
                return .success(())
            },
            perform: {
                steps.append("perform")
                return .success(())
            })
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(steps, ["discard", "open", "perform"])
    }

    private func makePairing() throws -> (URL, DeveloperSessionContext) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("pairing.plist")
        try Data([0]).write(to: file)
        let session = try XCTUnwrap(DeveloperSessionContext(endpoint: "10.7.0.1", pairingPath: file.path))
        return (file, session)
    }
}
