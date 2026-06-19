import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notifyNewMail(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "GmailBox"
        content.body = count == 1 ? "1 new email arrived." : "\(count) new emails arrived."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "gmailbox-new-mail-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
