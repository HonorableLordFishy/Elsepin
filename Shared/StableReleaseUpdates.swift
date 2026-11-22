import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Numeric release tags only. A prerelease suffix never becomes an official update,
/// even if someone accidentally clears GitHub's prerelease checkbox.
struct ReleaseVersion: Equatable, Comparable, Sendable {
    let components: [Int]
    init?(_ text: String) {
        let number = text.first == "v" || text.first == "V" ? String(text.dropFirst()) : text
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), number.utf8.count <= 32,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        components = values + Array(repeating: 0, count: 3 - values.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

struct StableRelease: Codable, Equatable, Sendable {
    let id: Int64
    let tag: String
    let url: URL
    let build: Int?
    init(id: Int64, tag: String, url: URL, build: Int? = nil) {
        self.id = id; self.tag = tag; self.url = url; self.build = build
    }
    var version: String { tag.first == "v" || tag.first == "V" ? String(tag.dropFirst()) : tag }
    var displayVersion: String { build.map { "\(version) (build \($0))" } ?? version }
    var isValid: Bool {
        guard id > 0, ReleaseVersion(tag) != nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.lowercased() == "github.com",
              parts.port == nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return false }
        return parts.path == "/N3moStudio/Elsepin-Releases/releases/tag/\(tag)"
    }
    func isUpdate(for installed: String, installedBuild: String? = nil) -> Bool {
        guard isValid, let current = ReleaseVersion(installed), let candidate = ReleaseVersion(tag) else { return false }
        if candidate != current { return candidate > current }
        guard let build, build > 0, let installedBuild, !installedBuild.isEmpty,
              installedBuild.utf8.allSatisfy({ (48...57).contains($0) }),
              let currentBuild = Int(installedBuild), currentBuild > 0 else { return false }
        return build > currentBuild
    }
}

private struct GitHubStableRelease: Decodable {
    let id: Int64
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let published_at: String?
    let body: String?
    var stable: StableRelease? {
        guard !draft, !prerelease, let published_at,
              ISO8601DateFormatter().date(from: published_at) != nil else { return nil }
        let value = StableRelease(id: id, tag: tag_name, url: html_url,
                                  build: Self.releaseBuild(from: body))
        return value.isValid ? value : nil
    }

    private static func releaseBuild(from body: String?) -> Int? {
        guard let body else { return nil }
        let lines = body.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let first = lines.first(where: { !$0.isEmpty })
        let legacy: Int?
        if let first, first.hasPrefix("Build") {
            let remainder = String(first.dropFirst(5))
            guard remainder.hasPrefix(" ") else { return nil }
            let valueAndDescription = String(remainder.dropFirst())
            let pieces = valueAndDescription.components(separatedBy: " · ")
            guard (1...2).contains(pieces.count), !pieces[0].isEmpty,
                  pieces[0].utf8.allSatisfy({ (48...57).contains($0) }),
                  pieces.count == 1 || !pieces[1].isEmpty,
                  let value = Int(pieces[0]), value > 0 else { return nil }
            legacy = value
        } else {
            legacy = nil
        }
        let markerPrefix = "<!-- elsepin-build:"
        let markerLines = lines.filter { $0.contains(markerPrefix) }
        if !markerLines.isEmpty {
            var values: [Int] = []
            for line in markerLines {
                guard line.hasPrefix(markerPrefix), line.hasSuffix("-->"),
                      line.dropFirst(markerPrefix.count).dropLast(3).first == " " else { return nil }
                let text = String(line.dropFirst(markerPrefix.count).dropLast(3))
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
                      let value = Int(text), value > 0 else { return nil }
                values.append(value)
            }
            guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
            if let legacy, legacy != first { return nil }
            return first
        }
        return legacy
    }
}

struct ReleaseUpdateState: Codable, Equatable {
    static let interval: TimeInterval = 24 * 60 * 60
    var lastAttempt: Date?
    var lastChecked: Date?
    var retryAfter: Date?
    var lastCheckFailed = false
    var release: StableRelease?
    var etag: String?
    var dismissedTag: String?
    var dismissedBuild: Int?

    /// Reserve the daily attempt before awaiting the network, including failures.
    /// Clock rollback rebases the wait without causing extra requests on each launch.
    mutating func beginAttempt(at now: Date, force: Bool = false) -> Bool {
        // Manual checks bypass the daily schedule, never server backoff.
        guard retryAfter.map({ now >= $0 }) ?? true else { return false }
        if !force, let lastAttempt, lastAttempt > now {
            self.lastAttempt = now
            retryAfter = nil
            return false
        }
        guard force || (lastAttempt.map({ now.timeIntervalSince($0) >= Self.interval }) ?? true) else { return false }
        lastAttempt = now
        retryAfter = nil
        return true
    }

    func update(for installed: String, installedBuild: String? = nil, at now: Date, includeDismissed: Bool = false) -> StableRelease? {
        guard let release, let lastChecked,
              (0...(7 * Self.interval)).contains(now.timeIntervalSince(lastChecked)),
              includeDismissed || !isDismissed(release),
              release.isUpdate(for: installed, installedBuild: installedBuild) else { return nil }
        return release
    }

    private func isDismissed(_ release: StableRelease) -> Bool {
        guard dismissedTag == release.tag else { return false }
        // A pre-build-aware cached dismissal keeps its original tag-wide meaning.
        guard let dismissedBuild else { return true }
        return dismissedBuild == release.build
    }
}

/// No timer, background task, credentials, analytics or retries. The app calls
/// this on foreground entry / Settings appearance; all gates survive relaunch.
@MainActor
final class StableReleaseChecker {
    static let defaultsKey = "shift.updates.stable.v1"
    static let endpoint = URL(string: "https://api.github.com/repos/N3moStudio/Elsepin-Releases/releases/latest")!
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private(set) var state: ReleaseUpdateState
    private(set) var isChecking = false
    private let defaults: UserDefaults
    private let fetch: Fetch
    private var generation = UUID()

    init(defaults: UserDefaults = .standard, fetch: @escaping Fetch = { try await StableReleaseTransport.fetch($0) }) {
        self.defaults = defaults
        self.fetch = fetch
        state = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(ReleaseUpdateState.self, from: $0) } ?? ReleaseUpdateState()
    }

    func dismiss(_ release: StableRelease) {
        state.dismissedTag = release.tag
        state.dismissedBuild = release.build
        save()
    }

    func reset() {
        generation = UUID()
        state = ReleaseUpdateState()
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func checkIfDue(at now: Date = Date(), force: Bool = false) async {
        guard !Task.isCancelled, !isChecking else { return }
        let before = state
        guard state.beginAttempt(at: now, force: force) else {
            if state != before { save() }
            return
        }
        isChecking = true
        let requestGeneration = generation
        save()
        defer { isChecking = false }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Elsepin-Release-Check", forHTTPHeaderField: "User-Agent")
        if state.lastChecked != nil, let etag = Self.validETag(state.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await fetch(request)
            guard generation == requestGeneration else { return }
            try Task.checkCancellation()
            guard response.url == Self.endpoint else { throw UpdateError.invalidResponse }
            switch response.statusCode {
            case 200:
                guard data.count <= 256 * 1024 else { throw UpdateError.invalidResponse }
                let payload = try JSONDecoder().decode(GitHubStableRelease.self, from: data)
                state.release = payload.stable
                state.etag = Self.validETag(response.value(forHTTPHeaderField: "ETag"))
            case 304:
                guard request.value(forHTTPHeaderField: "If-None-Match") != nil else { throw UpdateError.invalidResponse }
            case 404:
                state.release = nil
                state.etag = nil
            default:
                if response.statusCode == 429 || response.statusCode == 403 {
                    state.retryAfter = Self.retryDate(response, now: now) ?? now.addingTimeInterval(60)
                }
                throw UpdateError.invalidResponse
            }
            state.lastChecked = now
            state.lastCheckFailed = false
            // One record per completed check. `notice` is a render-time computed
            // property, so the decision itself must not write to disk.
            DeveloperLogStore.shared.record("update_check_completed", [
                "status": String(response.statusCode),
                "release_tag": state.release?.tag ?? "none",
                "has_etag": String(state.etag != nil)
            ])
        } catch {
            guard generation == requestGeneration else { return }
            // Keep a bounded-age cached notice. Never turn an error into "up to date".
            state.lastCheckFailed = true
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    private static func validETag(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 512,
              !value.contains("\r"), !value.contains("\n") else { return nil }
        return value
    }

    private static func retryDate(_ response: HTTPURLResponse, now: Date) -> Date? {
        var dates: [Date] = []
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
                dates.append(now.addingTimeInterval(seconds))
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
                if let date = formatter.date(from: header) { dates.append(date) }
            }
        }
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
           let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = TimeInterval(value), epoch.isFinite { dates.append(Date(timeIntervalSince1970: epoch)) }
        return dates.filter { $0 > now }.max()
    }

    private enum UpdateError: Error { case invalidResponse }
}

private enum StableReleaseTransport {
    static func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        #if !os(Linux) && !os(Windows)
        config.waitsForConnectivity = false
        #endif
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }
}
