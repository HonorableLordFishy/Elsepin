import Foundation

struct DeveloperSessionContext: Equatable {
    let endpoint: String
    let pairingPath: String
    let pairingAttributes: PairingAttributes

    struct PairingAttributes: Equatable {
        let fileSystem: UInt64
        let fileNumber: UInt64
        let creationDate: Date
        let modificationDate: Date
        let size: UInt64
    }

    init?(endpoint: String, pairingPath: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: pairingPath),
              let fileSystem = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let creationDate = attributes[.creationDate] as? Date,
              let modificationDate = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { return nil }
        self.endpoint = endpoint
        self.pairingPath = pairingPath
        self.pairingAttributes = PairingAttributes(fileSystem: fileSystem.uint64Value,
            fileNumber: fileNumber.uint64Value, creationDate: creationDate,
            modificationDate: modificationDate, size: size.uint64Value)
    }
}

enum DeveloperSessionCommand {
    /// Only opening a new service needs the bootstrap transport. The command
    /// itself supplies the result on either path and is attempted at most once.
    static func run<Failure: Error>(
        requested: DeveloperSessionContext?, connected: DeveloperSessionContext?,
        discard: () -> Void, open: () -> Result<Void, Failure>,
        perform: () -> Result<Void, Failure>
    ) -> Result<Void, Failure> {
        if requested == nil || requested != connected {
            discard()
            if case .failure(let error) = open() { return .failure(error) }
        }
        return perform()
    }
}
