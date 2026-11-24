import Foundation

/// Lifetime of one notification submission, including time spent suspended.
struct PairingPINNotification {
    static let legacyIdentifier = "locus.pairing.pin"
    static let lifetime: Duration = .seconds(5 * 60)
    let identifier: String
    let expiresAt: ContinuousClock.Instant

    init(startedAt: ContinuousClock.Instant, id: UUID = UUID()) {
        identifier = "\(Self.legacyIdentifier).\(id.uuidString)"
        expiresAt = startedAt.advanced(by: Self.lifetime)
    }

    static func matches(_ identifier: String) -> Bool {
        identifier == legacyIdentifier || identifier.hasPrefix(legacyIdentifier + ".")
    }

    func canPresent(_ identifier: String, at now: ContinuousClock.Instant) -> Bool {
        self.identifier == identifier && now < expiresAt
    }
}

/// Main-actor owned by the native adapter. Kept independent of Network/idevice
/// so cancellation ordering and file-replacement decisions can be regression tested.
struct PairingAttemptState {
    private(set) var cancelled = false
    private(set) var finished = false
    private var listeningPort: UInt16?
    private var wakeRequested = false

    var acceptsCallbacks: Bool { !cancelled && !finished }

    mutating func listening(on port: UInt16) -> UInt16? {
        guard !finished, port != 0 else { return nil }
        listeningPort = port
        return cancellationPort()
    }

    mutating func cancel() -> UInt16? {
        guard !finished else { return nil }
        cancelled = true
        return cancellationPort()
    }

    mutating func finish() {
        finished = true
        listeningPort = nil
    }

    func canInstall(startingRevision: UUID, currentRevision: UUID) -> Bool {
        acceptsCallbacks && startingRevision == currentRevision
    }

    private mutating func cancellationPort() -> UInt16? {
        guard cancelled, !finished, !wakeRequested, let listeningPort else { return nil }
        wakeRequested = true
        return listeningPort
    }
}
