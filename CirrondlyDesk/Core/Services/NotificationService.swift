import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var deliveredKeys = Set<String>()

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func handle(snapshot: UsageSnapshot) {
        guard !isQuietHours else { return }

        for provider in snapshot.providers {
            for window in provider.windows where window.kind == .fiveHour || window.kind == .weekly {
                for threshold in configuredThresholds where window.percentage >= Double(threshold) {
                    let resetKey = window.resetAt.map(TimeHelpers.iso8601Plain.string(from:)) ?? "none"
                    let key = "\(provider.identifier):\(window.kind.reportingKey):\(threshold):\(resetKey)"
                    guard deliveredKeys.insert(key).inserted else { continue }
                    send(title: title(for: threshold, kind: window.kind), body: "\(provider.displayName) is at \(Int(window.percentage.rounded()))%.")
                }
            }
        }
    }

    private var configuredThresholds: [Int] {
        [75, 90, 95, 100].filter { UserDefaults.standard.object(forKey: "notify.threshold.\($0)") as? Bool ?? ($0 == 75 || $0 == 90 || $0 == 100) }
    }

    private var isQuietHours: Bool {
        let enabled = UserDefaults.standard.bool(forKey: "notify.quiet.enabled")
        guard enabled else { return false }
        let start = UserDefaults.standard.integer(forKey: "notify.quiet.startHour")
        let end = UserDefaults.standard.integer(forKey: "notify.quiet.endHour")
        let currentHour = Calendar.current.component(.hour, from: Date())
        if start <= end {
            return (start..<end).contains(currentHour)
        }
        return currentHour >= start || currentHour < end
    }

    private func title(for threshold: Int, kind: WindowKind) -> String {
        let label = kind == .weekly ? "Weekly" : "Session"
        switch threshold {
        case 100:
            return "\(label) limit reached"
        default:
            return "\(label) at \(threshold)%"
        }
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UserDefaults.standard.object(forKey: "notify.sound") as? Bool ?? true ? .default : nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}