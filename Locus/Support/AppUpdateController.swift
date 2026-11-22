import Foundation
import Combine

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var state: ReleaseUpdateState
    @Published private(set) var isChecking = false
    @Published private(set) var manualResult: String?
    let installedVersion: String
    let installedBuild: String
    let isPrerelease: Bool
    private let checker: StableReleaseChecker
    private var generation = UUID()

    init() {
        checker = StableReleaseChecker()
        state = checker.state
        installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        installedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        isPrerelease = Bundle.main.object(forInfoDictionaryKey: "ShiftReleaseChannel") as? String == "prerelease"
        DeveloperLogStore.shared.record("update_checker_init", [
            "installed_version": installedVersion,
            "installed_build": installedBuild,
            "is_prerelease": String(isPrerelease),
            "state_last_checked": state.lastChecked?.ISO8601Format() ?? "nil",
            "state_release_tag": state.release?.tag ?? "nil"
        ])
    }

    var notice: StableRelease? { state.update(for: installedVersion, installedBuild: installedBuild, at: Date()) }
    var availableUpdate: StableRelease? {
        state.update(for: installedVersion, installedBuild: installedBuild, at: Date(), includeDismissed: true)
    }

    func checkIfDue() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        await checker.checkIfDue()
        if state != checker.state { state = checker.state }
    }

    func checkNow() async {
        guard !isChecking else { return }
        if let retry = checker.state.retryAfter, retry > Date() {
            manualResult = "GitHub asked us to wait. Try again after \(retry.formatted(date: .omitted, time: .shortened))."
            return
        }
        isChecking = true
        manualResult = nil
        let requestGeneration = generation
        defer { isChecking = false }
        await checker.checkIfDue(force: true)
        state = checker.state
        guard !Task.isCancelled, generation == requestGeneration else { return }
        if let retry = state.retryAfter, retry > Date() {
            manualResult = "GitHub asked us to wait. Try again after \(retry.formatted(date: .omitted, time: .shortened))."
        }
        else if state.lastCheckFailed { manualResult = "Couldn’t check. Check your connection and try again." }
        else if let update = availableUpdate { manualResult = "Version \(update.displayVersion) is available." }
        else if state.release == nil { manualResult = "No official release is listed yet." }
        else { manualResult = "No newer official release found." }
    }

    func dismiss(_ release: StableRelease) {
        checker.dismiss(release)
        state = checker.state
    }

    func reset() { generation = UUID(); checker.reset(); state = checker.state; manualResult = nil }
}
