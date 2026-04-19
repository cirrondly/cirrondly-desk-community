import Foundation

@MainActor
final class AnalyticsHeartbeat {
    func sendIfEnabled() async {
        guard !(UserDefaults.standard.object(forKey: "advanced.analytics.optOut") as? Bool ?? false) else {
            return
        }
    }
}