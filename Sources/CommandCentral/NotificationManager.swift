import Foundation
import UserNotifications

/// System notifications (Notification Center banners).
final class NotificationManager {
    static let shared = NotificationManager()

    private var requested = false

    func requestIfNeeded() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        requestIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Discord webhook integration — paste a channel webhook URL in Settings.
enum Discord {
    static var webhook: String {
        UserDefaults.standard.string(forKey: "discordWebhook") ?? ""
    }

    static var isConfigured: Bool { !webhook.isEmpty }

    static func send(_ message: String) {
        guard let url = URL(string: webhook), isConfigured else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["content": message])
        URLSession.shared.dataTask(with: request).resume()
    }
}
