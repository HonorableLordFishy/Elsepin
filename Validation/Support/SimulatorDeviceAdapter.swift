#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Validation adapters must never compile into a device app")
#endif
import Foundation
import UniformTypeIdentifiers

/// No sockets, pairing records, location injection, or remote account access.
/// Only the separate validation app links this adapter; normal builds fail
/// closed without an idevice implementation rather than inventing success.
enum LocationEngine {
    private static let lock = NSLock()
    private static var acceptedWrites = 0
    private static var reconnectFailureSent = false
    private struct PlaybackWrite: Encodable {
        let latitude: Double
        let longitude: Double
        let startedAt: TimeInterval
        let confirmedAt: TimeInterval
        let requestedLatencyMillis: Int
    }
    private static var playbackWrites: [PlaybackWrite] = []

    static func playbackTrace() -> String {
        lock.lock()
        let snapshot = playbackWrites
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return "Trace encoding failed" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func playbackLatencyMillis() -> Int {
        lock.lock(); defer { lock.unlock() }
        return playbackWrites.count.isMultiple(of: 2) ? 20 : 145
    }

    private static func recordPlaybackWrite(_ write: PlaybackWrite) {
        lock.lock(); defer { lock.unlock() }
        playbackWrites.append(write)
    }

    private static func shouldFailWrite(explicit: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if ValidationFixture.routeReconnect, acceptedWrites > 0, !explicit, !reconnectFailureSent {
            reconnectFailureSent = true
            return true
        }
        let fail = ValidationFixture.scenario == "failed" && acceptedWrites > 0
        if !fail { acceptedWrites += 1 }
        return fail
    }
    static var setupCheckIsRunning: Bool { false }
    static func checkConnection(pairingPath: String, deviceIP: String,
                                cancellation: SetupConnectionCancellation) async -> SetupIssue? {
        .serviceUnavailable // Pairing is intentionally not simulated as verified.
    }
    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String,
                    explicit: Bool = false, checkInterval: TimeInterval = 10) async -> Result<Void, LocationEngineError> {
        guard ValidationFixture.enabled else { return .failure(.notActive) }
        if ValidationFixture.scenario == "connecting" {
            try? await Task.sleep(for: .seconds(300))
            return .failure(.tunnelUnreachable)
        }
        if ValidationFixture.scenario == "route-camera", latitude > 40 {
            // Keep the previous synthetic location visible until the test has
            // checked the new route's camera before its first accepted write.
            try? await Task.sleep(for: .seconds(25))
        }
        let observePlayback = ValidationFixture.routePace
        let latency = observePlayback ? playbackLatencyMillis() : 60
        let startedAt = ProcessInfo.processInfo.systemUptime
        try? await Task.sleep(for: .milliseconds(latency))
        // Fail after one accepted test command so recovery includes a location
        // that may remain, rather than the separate never-started case.
        if shouldFailWrite(explicit: explicit) { return .failure(.tunnelUnreachable) }
        if observePlayback {
            recordPlaybackWrite(PlaybackWrite(latitude: latitude, longitude: longitude,
                startedAt: startedAt, confirmedAt: ProcessInfo.processInfo.systemUptime, requestedLatencyMillis: latency))
        }
        return Result.success(()) // TEST ONLY: UI command acceptance, not device spoofing.
    }
    static func clear(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        if ValidationFixture.enabled { return Result.success(()) }
        return .failure(.notActive)
    }
    static func prepareForTermination() {}
    static func invalidateProbe() {}
}

@MainActor final class PairingStore: ObservableObject {
    @Published private(set) var hasPairingFile = ValidationFixture.enabled && !ValidationFixture.firstLaunch
    @Published private(set) var revision = UUID()
    @Published var lastError: String?
    static let fileName = "NO-REAL-PAIRING-IN-UI-TESTS"
    static let supportedTypes: [UTType] = [.data]
    var pairingURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(Self.fileName) }
    var pairingPath: String { pairingURL.path }
    func refresh() {}
    func importPairing(from url: URL) throws { throw PairingImportError.invalidContents }
    func importPairingFromClipboard() throws { throw PairingImportError.invalidContents }
    func removePairing() throws { hasPairingFile = false; revision = UUID() }
}
enum PairingImportError: LocalizedError {
    case invalidContents
    var errorDescription: String? { "Real pairing is unavailable in the simulator validation app." }
}
@MainActor final class PairOnDeviceService: ObservableObject {
    enum Phase: Equatable {
        case idle, stopping, advertising, deviceConnected, awaitingPIN(String), succeeded, failed(String)
    }
    static var nativeWorkOutstanding: Bool { false }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pin: String?
    @Published private(set) var debugPort: UInt16?
    var isBusy: Bool { false }
    func start(pairingStore: PairingStore, preferences: SessionPreferences) {
        phase = .failed("Real pairing requires a physical iPhone.")
    }
    func acknowledgeFailure() { phase = .idle }
    func resetToIdle() { phase = .idle }
}
