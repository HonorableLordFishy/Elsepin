import Foundation

/// A single import uses one coordinator on its worker. Foundation allows
/// cancel() to interrupt that coordinator from any thread.
final class ImportFileReadCoordinator: @unchecked Sendable {
    #if canImport(Darwin)
    private let coordinator = NSFileCoordinator()
    #endif

    func read<Value>(_ url: URL, using reader: (URL) throws -> Value) throws -> Value {
        try Task.checkCancellation()
        #if canImport(Darwin)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result { try reader(readableURL) }
        }
        try Task.checkCancellation()
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
        #else
        return try reader(url)
        #endif
    }

    func cancel() {
        #if canImport(Darwin)
        coordinator.cancel()
        #endif
    }
}
