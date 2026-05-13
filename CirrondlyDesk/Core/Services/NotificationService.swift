import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var deliveredKeys = Set<String>()
    private var lastServiceHealthByName: [String: ProviderServiceHealth] = [:]

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
                    send(
                        title: title(for: threshold, kind: window.kind),
                        body: L10n.tr("notification.threshold.body", provider.displayName, "\(Int(window.percentage.rounded()))")
                    )
                }
            }
        }
    }

    func handleServiceStatuses(for providers: [ProviderResult], monitor: ServiceStatusMonitor) {
        guard serviceStatusNotificationsEnabled else { return }

        let visibleServices = providers.reduce(into: [String: ProviderServiceStatus]()) { partialResult, provider in
            let status = monitor.status(for: provider.identifier)
            partialResult[status.serviceName] = status
        }

        for (serviceName, status) in visibleServices {
            let previousHealth = lastServiceHealthByName[serviceName]
            lastServiceHealthByName[serviceName] = status.health

            guard !isQuietHours,
                  status.health.showsAlert,
                  previousHealth != status.health else {
                continue
            }

            send(
                title: serviceStatusTitle(for: status),
                body: serviceStatusBody(for: status)
            )
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

    private var serviceStatusNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notify.serviceStatus") as? Bool ?? true
    }

    private func title(for threshold: Int, kind: WindowKind) -> String {
        let label = kind == .weekly ? L10n.tr("window.title.weekly") : L10n.tr("window.title.session")
        switch threshold {
        case 100:
            return L10n.tr("notification.threshold.limitReached", label)
        default:
            return L10n.tr("notification.threshold.at", label, "\(threshold)")
        }
    }

    private func serviceStatusTitle(for status: ProviderServiceStatus) -> String {
        switch status.health {
        case .outage:
            return L10n.tr("notification.service.outageTitle", status.serviceName)
        case .degraded:
            return L10n.tr("notification.service.degradedTitle", status.serviceName)
        case .checking, .operational, .unknown:
            return L10n.tr("notification.service.updateTitle", status.serviceName)
        }
    }

    private func serviceStatusBody(for status: ProviderServiceStatus) -> String {
        switch status.health {
        case .outage:
            return L10n.tr("notification.service.outageBody", status.serviceName, status.message)
        case .degraded:
            return L10n.tr("notification.service.degradedBody", status.serviceName, status.message)
        case .checking, .operational, .unknown:
            return status.message
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