import SwiftUI
import SwiftData
import UserNotifications

@main
struct HeldApp: App {
    @UIApplicationDelegateAdaptor(HeldAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            HeldOrder.self,
            OrderItem.self,
            Milestone.self,
            Evidence.self,
            HeldReminder.self,
            AppSettings.self
        ])
    }
}

extension Notification.Name {
    static let heldOpenOrders = Notification.Name("Held.OpenOrders")
}

final class HeldAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .heldOpenOrders, object: nil)
        completionHandler()
    }
}
