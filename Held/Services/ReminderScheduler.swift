import Foundation
import UserNotifications
import Combine

@MainActor
final class ReminderScheduler: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastErrorMessage: String?

    private let center: UNUserNotificationCenter
    private static let identifierPrefix = "held.order."
    private static let weeklyDigestIdentifier = "held.weekly.digest"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        Task { await refreshAuthorizationStatus() }
    }

    var authorizationStatusDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return L("Notifications have not been requested.")
        case .denied:
            return L("Notifications are disabled. You can enable them in Settings.")
        case .authorized:
            return L("Notifications are enabled.")
        case .provisional:
            return L("Provisional notifications are enabled.")
        case .ephemeral:
            return L("Notifications are enabled for this app clip.")
        @unknown default:
            return L("Notification availability is unknown.")
        }
    }

    /// Call only from an explicit user action, such as enabling reminders.
    /// Synchronization itself never requests authorization.
    @discardableResult
    func requestAuthorization() async -> Bool {
        lastErrorMessage = nil
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if !granted {
                lastErrorMessage = "Notifications were not enabled. You can allow them later in Settings."
            }
            return granted
        } catch {
            await refreshAuthorizationStatus()
            lastErrorMessage = "Notification permission could not be requested. Please try again."
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Replaces only Held-owned pending requests. Requests from other app
    /// features are left untouched. No authorization prompt is triggered.
    func sync(orders: [HeldOrder], settings: AppSettings) async {
        await refreshAuthorizationStatus()
        lastErrorMessage = nil

        let pending = await center.pendingNotificationRequests()
        let now = Date()
        var desired: [String: UNNotificationRequest] = [:]

        let activeOrders = orders.filter(\.isActive)

        if settings.remindersEnabled && Self.canSchedule(authorizationStatus) {
            for order in activeOrders {
                for reminder in order.reminders where reminder.enabled {
                    // triggerAt is the check-in or deadline event. Deadline
                    // notifications fire leadDays before it, matching the
                    // AttentionEngine's advance-warning window.
                    let fireDate = reminder.kind == .deadline
                        ? Calendar.current.date(byAdding: .day, value: -max(0, reminder.leadDays), to: reminder.triggerAt) ?? reminder.triggerAt
                        : reminder.triggerAt
                    guard fireDate > now else { continue }
                    let identifier = Self.identifier(orderID: order.id, reminderID: reminder.id)
                    let content = UNMutableNotificationContent()
                    content.title = reminder.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("Order reminder")
                        : reminder.label
                    content.body = order.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("You asked Keyvow to remind you about this order.")
                        : order.title
                    content.sound = .default
                    content.threadIdentifier = "held.order.\(order.id)"
                    content.userInfo = [
                        "orderID": order.id,
                        "reminderID": reminder.id
                    ]
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: max(1, fireDate.timeIntervalSince(now)),
                        repeats: false
                    )
                    desired[identifier] = UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: trigger
                    )
                }
            }
        }

        if settings.remindersEnabled && settings.weeklyDigest && Self.canSchedule(authorizationStatus) {
            let activeCount = activeOrders.count
            let attentionCount = AttentionEngine.attention(orders: activeOrders, settings: settings, now: now).count
            let content = UNMutableNotificationContent()
            content.title = L("Your week with Keyvow")
            content.body = attentionCount > 0
                ? L("Notification active orders with attention", Int64(activeCount), Int64(attentionCount))
                : L("Notification active orders without attention", Int64(activeCount))
            content.sound = .default
            content.threadIdentifier = "held.digest"
            content.userInfo = ["destination": "orders"]
            var components = DateComponents()
            components.weekday = 2 // Monday in the Gregorian calendar.
            components.hour = 9
            components.minute = 0
            desired[Self.weeklyDigestIdentifier] = UNNotificationRequest(
                identifier: Self.weeklyDigestIdentifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
        }

        let staleIdentifiers = pending
            .map(\.identifier)
            .filter {
                ($0.hasPrefix(Self.identifierPrefix) || $0 == Self.weeklyDigestIdentifier)
                    && desired[$0] == nil
            }
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        // Replacing by stable identifier also updates content and fire dates.
        let existing = Set(pending.map(\.identifier))
        for identifier in desired.keys where existing.contains(identifier) {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
        do {
            for request in desired.values {
                try await center.add(request)
            }
        } catch {
            lastErrorMessage = "Some reminders could not be scheduled. Please try again."
            await refreshAuthorizationStatus()
        }
    }

    /// Call when an order is deleted or its reminders must all be cancelled.
    func cancel(for order: HeldOrder) async {
        await cancel(orderID: order.id)
    }

    func cancel(orderID: String) async {
        let prefix = Self.orderPrefix(orderID: orderID)
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let pendingIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        let deliveredIDs = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    private static func canSchedule(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func orderPrefix(orderID: String) -> String {
        "\(identifierPrefix)\(orderID)."
    }

    private static func identifier(orderID: String, reminderID: String) -> String {
        "\(orderPrefix(orderID: orderID))reminder.\(reminderID)"
    }
}
