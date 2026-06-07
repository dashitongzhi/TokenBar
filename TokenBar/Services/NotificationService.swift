import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private var notifiedKeys = Set<String>()

    private init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(appState: AppState) {
        guard let provider = appState.mostUrgentProvider, provider.status != .healthy else { return }
        let key = "\(provider.id)-\(provider.status.rawValue)"
        guard notifiedKeys.contains(key) == false else { return }
        notifiedKeys.insert(key)

        let content = UNMutableNotificationContent()
        content.title = "TokenBar: \(provider.name) \(provider.status.rawValue)"
        if let predicted = provider.predictedExhaustion {
            let hours = max(predicted.timeIntervalSinceNow / 3600, 0)
            content.body = "Current burn rate may exhaust quota in \(String(format: "%.1f", hours))h."
        } else {
            content.body = "Usage is at \(Int(provider.usageRatio * 100))%."
        }
        content.sound = provider.status == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
