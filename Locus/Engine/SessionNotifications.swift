import Foundation
import UserNotifications
import Combine
import UIKit

/// Retains a cold-launch tap until the map and privacy gate can consume it.
@MainActor
final class SessionNotificationNavigation: ObservableObject {
    static let shared = SessionNotificationNavigation()
    @Published var pendingSessionDetails = false
}

final class SessionNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SessionNotifications()
    static let reminderID = "locus.session.reminder"
    static let connectionID = "locus.session.connection"
    @MainActor private var pairingCleanup: AnyCancellable?

    @MainActor
    func install() {
        UNUserNotificationCenter.current().delegate = self
        guard pairingCleanup == nil else { return }
        PairingPINNotifications.shared.removeStaleNotifications()
        pairingCleanup = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { _ in
            Task { @MainActor in PairingPINNotifications.shared.removeStaleNotifications() }
        }
    }

    func requestPermission() async -> Bool {
        let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        DeveloperLogStore.shared.record("notification_permission_result", ["allowed": String(allowed)])
        return allowed
    }

    func warn(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        addLogged(UNNotificationRequest(
            identifier: Self.connectionID, content: content, trigger: nil))
    }

    func scheduleReminder(minutes: Int, startedAt: Date) {
        cancelReminder()
        guard minutes > 0 else { return }
        let remaining = startedAt.addingTimeInterval(Double(minutes * 60)).timeIntervalSinceNow
        // Changing settings after the deadline shouldn't generate repeated alerts.
        guard remaining > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Check your Elsepin session"
        content.body = "Your session reminder is due. Open Elsepin to review its current status."
        content.sound = .default
        addLogged(UNNotificationRequest(
            identifier: Self.reminderID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)))
    }

    func cancelReminder() {
        DeveloperLogStore.shared.record("reminder_cancel_requested")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        if PairingPINNotification.matches(identifier) {
            DeveloperLogStore.shared.record("notification_foreground_delivery", ["id": identifier])
            Task { @MainActor in
                let notifications = PairingPINNotifications.shared
                if notifications.canPresent(identifier) {
                    completionHandler([.banner, .sound])
                } else {
                    notifications.clear(identifier)
                    completionHandler([])
                }
            }
            return
        }
        DeveloperLogStore.shared.record("notification_foreground_delivery", ["id": identifier,
            "title": notification.request.content.title, "body": notification.request.content.body])
        // Connection errors already have an in-app alert. Reminders still need a banner.
        completionHandler(identifier == Self.connectionID ? [] : [.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DeveloperLogStore.shared.record("notification_response", ["id": response.notification.request.identifier,
            "action": response.actionIdentifier])
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           [Self.reminderID, Self.connectionID].contains(response.notification.request.identifier) {
            Task { @MainActor in
                SessionNotificationNavigation.shared.pendingSessionDetails = true
            }
        }
        completionHandler()
    }

    private func addLogged(_ request: UNNotificationRequest) {
        DeveloperLogStore.shared.record("notification_requested", ["id": request.identifier,
            "title": request.content.title, "body": request.content.body, "scheduled": String(request.trigger != nil)])
        UNUserNotificationCenter.current().add(request) { error in
            var details = ["id": request.identifier, "result": error == nil ? "accepted_by_iOS_not_proof_seen" : "failed"]
            if let error = error as NSError? { details["error_domain"] = error.domain; details["error_code"] = String(error.code) }
            DeveloperLogStore.shared.record("notification_request_result", details)
        }
    }
}

/// Owns PIN notification display independently from ActivityKit and the pairing worker.
@MainActor
final class PairingPINNotifications {
    static let shared = PairingPINNotifications()
    private let center = UNUserNotificationCenter.current()
    private let clock = ContinuousClock()
    private var current: PairingPINNotification?
    private var expiry: Task<Void, Never>?

    func post(_ pin: String) -> String {
        if let current { clear(current.identifier) }
        let notification = PairingPINNotification(startedAt: clock.now)
        let identifier = notification.identifier
        current = notification
        expiry = Task {
            do { try await clock.sleep(until: notification.expiresAt, tolerance: .zero) }
            catch { return }
            clear(identifier)
        }

        let content = UNMutableNotificationContent()
        content.title = "Elsepin pairing code"
        content.body = pin
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        DeveloperLogStore.shared.record("notification_requested", ["id": identifier, "scheduled": "false"])
        center.add(request) { error in
            let accepted = error == nil
            DeveloperLogStore.shared.record("notification_request_result", [
                "id": identifier, "result": accepted ? "accepted_by_iOS_not_proof_seen" : "failed"
            ])
            Task { @MainActor in
                if !accepted || !self.canPresent(identifier) { self.clear(identifier) }
            }
        }
        return identifier
    }

    func canPresent(_ identifier: String) -> Bool {
        current?.canPresent(identifier, at: clock.now) == true
    }

    func clear(_ identifier: String) {
        if current?.identifier == identifier {
            current = nil
            expiry?.cancel()
            expiry = nil
        }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// iOS can keep delivered local notifications while the app cannot run.
    /// On launch or resume, discard expired and abandoned PIN requests and alerts.
    func removeStaleNotifications() {
        if let current, !canPresent(current.identifier) { clear(current.identifier) }
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier)
            Task { @MainActor in self.clearStale(identifiers) }
        }
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.map(\.request.identifier)
            Task { @MainActor in self.clearStale(identifiers) }
        }
    }

    private func clearStale(_ identifiers: [String]) {
        for identifier in identifiers where PairingPINNotification.matches(identifier) && !canPresent(identifier) {
            clear(identifier)
        }
    }
}
