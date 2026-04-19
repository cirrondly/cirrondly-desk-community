import AppKit
import Foundation

final class CopilotProvider: UsageProvider {
    static let identifier = "copilot"
    static let displayName = "Copilot"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let keychainService: KeychainService
    private let session = URLSession(configuration: .ephemeral)
    private let calculator = BurnRateCalculator()
    private let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!
    private let openUsageService = "OpenUsage-copilot"
    private let githubCLIService = "gh:github.com"

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.copilot.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.copilot.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "GitHub")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "GitHub")

    func isAvailable() async -> Bool {
        hasAnyCopilotFootprint()
    }

    func probe() async throws -> ProviderResult {
        guard var credential = loadToken() else {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Run gh auth login first.")
        }

        var response = try await fetchUsage(token: credential.token)
        if response.statusCode == 401 || response.statusCode == 403, credential.source == .openUsageKeychain {
            clearCachedToken()
            if let fallback = loadGitHubCLIToken() {
                let fallbackResponse = try await fetchUsage(token: fallback.token)
                if (200...299).contains(fallbackResponse.statusCode) {
                    credential = fallback
                    response = fallbackResponse
                    saveToken(fallback.token)
                }
            }
        }

        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Token invalid. Run gh auth login to re-authenticate.")
            }
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Usage request failed (HTTP \(response.statusCode)). Try again later.")
        }

        if credential.source == .githubCLI {
            saveToken(credential.token)
        }

        let localActivity = try await loadLocalActivity()

        guard let payload = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Usage response invalid. Try again later.")
        }

        let resetDate = TimeHelpers.parseISODate(stringValue(payload["quota_reset_date"]) ?? stringValue(payload["limited_user_reset_date"]))
        var windows: [Window] = []

        if let snapshots = payload["quota_snapshots"] as? [String: Any] {
            if let premium = makeProgressWindow(label: "Premium Requests", snapshot: snapshots["premium_interactions"] as? [String: Any], resetAt: resetDate) {
                windows.append(premium)
            }
            if let chat = makeProgressWindow(label: "Chat Messages", snapshot: snapshots["chat"] as? [String: Any], resetAt: resetDate) {
                windows.append(chat)
            }
        }

        if let limited = payload["limited_user_quotas"] as? [String: Any], let monthly = payload["monthly_quotas"] as? [String: Any] {
            if let chat = makeLimitedWindow(label: "Chat Messages", remaining: limited["chat"], total: monthly["chat"], resetAt: resetDate) {
                windows.append(chat)
            }
            if let completions = makeLimitedWindow(label: "Inline Suggestions", remaining: limited["completions"], total: monthly["completions"], resetAt: resetDate) {
                windows.append(completions)
            }
        }

        let warnings = windows.isEmpty ? [ProviderWarning(level: .info, message: "Copilot returned no quota data for this account.")] : []
        let profile = runningClientName() ?? detectedClientName() ?? planLabel(from: stringValue(payload["copilot_plan"])) ?? "GitHub"

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: profile,
            windows: windows,
            today: DailyUsage(costUSD: 0, tokens: 0, requests: localActivity.todayCount),
            burnRate: nil,
            dailyHeatmap: localActivity.heatmap,
            models: [],
            source: .api,
            freshness: Date(),
            warnings: warnings
        )
    }

    private func loadToken() -> CopilotCredential? {
        loadOpenUsageToken() ?? loadGitHubCLIToken() ?? loadTokenFromDefaults()
    }

    private func loadOpenUsageToken() -> CopilotCredential? {
        if let raw = keychainService.readAny(service: openUsageService),
           let data = raw.data(using: .utf8),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = stringValue(payload["token"]) {
            return CopilotCredential(token: token, source: .openUsageKeychain)
        }
        return nil
    }

    private func loadGitHubCLIToken() -> CopilotCredential? {
        guard let raw = keychainService.readAny(service: githubCLIService) else { return nil }
        let token: String?
        if raw.hasPrefix("go-keyring-base64:"), let decoded = Data(base64Encoded: String(raw.dropFirst("go-keyring-base64:".count))) {
            token = String(data: decoded, encoding: .utf8)
        } else {
            token = raw
        }
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        return CopilotCredential(token: token, source: .githubCLI)
    }

    private func loadTokenFromDefaults() -> CopilotCredential? {
        guard let token = defaults.string(forKey: "provider.copilot.cachedToken"), !token.isEmpty else { return nil }
        return CopilotCredential(token: token, source: .state)
    }

    private func saveToken(_ token: String) {
        defaults.set(token, forKey: "provider.copilot.cachedToken")
        try? keychainService.save("{\"token\":\"\(token)\"}", service: openUsageService, account: "token")
    }

    private func clearCachedToken() {
        keychainService.deleteAll(service: openUsageService)
        defaults.removeObject(forKey: "provider.copilot.cachedToken")
    }

    private func fetchUsage(token: String) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        return (data, statusCode)
    }

    private func makeProgressWindow(label: String, snapshot: [String: Any]?, resetAt: Date?) -> Window? {
        guard let remaining = numberValue(snapshot?["percent_remaining"]) else { return nil }
        let used = min(100, max(0, 100 - remaining))
        return Window(kind: .custom(label), used: used, limit: 100, unit: .requests, percentage: used, resetAt: resetAt)
    }

    private func makeLimitedWindow(label: String, remaining: Any?, total: Any?, resetAt: Date?) -> Window? {
        guard let remaining = numberValue(remaining), let total = numberValue(total), total > 0 else { return nil }
        let used = total - remaining
        let percentage = min(100, max(0, (used / total) * 100))
        return Window(kind: .custom(label), used: used, limit: total, unit: .requests, percentage: percentage, resetAt: resetAt)
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }

    private func planLabel(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func hasAnyCopilotFootprint() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".config/github-copilot"),
            home.appending(path: ".config/gh-copilot"),
            home.appending(path: ".vscode/extensions"),
            home.appending(path: "Library/Application Support/Code/User/globalStorage"),
            home.appending(path: "Library/Application Support/Code - Insiders/User/globalStorage"),
            home.appending(path: "Library/Application Support/Code/CachedExtensionVSIXs"),
            home.appending(path: "Library/Application Support/Code - Insiders/CachedExtensionVSIXs"),
        ]

        if candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) == false ? false : hasCopilotEntry(in: $0) || $0.lastPathComponent.contains("copilot") }) {
            return true
        }

        return runningClientName() != nil
    }

    private func hasCopilotEntry(in directory: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        return entries.contains { $0.lastPathComponent.localizedCaseInsensitiveContains("copilot") }
    }

    private func runningClientName() -> String? {
        let names = NSWorkspace.shared.runningApplications.compactMap(\ .localizedName)
        if names.contains(where: { $0.localizedCaseInsensitiveContains("visual studio code") }) {
            return "VS Code"
        }
        if names.contains(where: { $0.localizedCaseInsensitiveContains("pycharm") || $0.localizedCaseInsensitiveContains("jetbrains") }) {
            return "JetBrains"
        }
        return nil
    }

    private func detectedClientName() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if FileManager.default.fileExists(atPath: home.appending(path: ".vscode/extensions/github.copilot-chat-0.44.1").path) || FileManager.default.fileExists(atPath: home.appending(path: "Library/Application Support/Code/CachedExtensionVSIXs/github.copilot-chat-0.44.1").path) {
            return "VS Code"
        }
        if FileManager.default.fileExists(atPath: home.appending(path: ".config/github-copilot/copilot-intellij.db").path) {
            return "JetBrains"
        }
        return nil
    }

    private func loadLocalActivity(days: Int = 90) async throws -> CopilotLocalActivity {
        var points: [(date: Date, value: Double)] = []
        let todayKey = TimeHelpers.dayFormatter.string(from: TimeHelpers.startOfDay(for: Date()))
        var todayCount = 0

        for root in workspaceStorageRoots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.path.contains("/GitHub.copilot-chat/transcripts/") else {
                    continue
                }

                let rows = try await JSONLStreamReader.readObjects(at: url)
                for row in rows {
                    guard let eventType = stringValue(row["type"]),
                          let weight = localActivityWeight(for: eventType),
                          let timestamp = localActivityTimestamp(in: row, eventType: eventType) else {
                        continue
                    }

                    let day = TimeHelpers.startOfDay(for: timestamp)
                    let dayKey = TimeHelpers.dayFormatter.string(from: day)
                    points.append((date: day, value: weight))
                    if dayKey == todayKey {
                        todayCount += Int(weight)
                    }
                }
            }
        }

        points.append(contentsOf: loadLogActivity(days: days))

        return CopilotLocalActivity(
            heatmap: calculator.heatmap(fromDailyValues: points, days: days),
            todayCount: todayCount
        )
    }

    private var workspaceStorageRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Application Support/Code/User/workspaceStorage", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Code - Insiders/User/workspaceStorage", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Cursor/User/workspaceStorage", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/VSCodium/User/workspaceStorage", directoryHint: .isDirectory)
        ]
    }

    private var logRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Application Support/Code/logs", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Code - Insiders/logs", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Cursor/logs", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/VSCodium/logs", directoryHint: .isDirectory)
        ]
    }

    private func loadLogActivity(days: Int) -> [(date: Date, value: Double)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: TimeHelpers.startOfDay(for: Date())) ?? .distantPast
        var points: [(date: Date, value: Double)] = []

        for root in logRoots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard isCopilotLogFile(url) else { continue }

                let daysInFile = copilotLogDays(for: url)
                for day in daysInFile where day >= cutoff {
                    points.append((date: day, value: 1))
                }
            }
        }

        return points
    }

    private func isCopilotLogFile(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        guard url.pathExtension == "log" else { return false }
        if path.contains("/github.copilot-chat/") {
            return true
        }
        return name.contains("github copilot")
    }

    private func copilotLogDays(for url: URL) -> [Date] {
        var days = Set<Date>()

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let string = String(line)
                guard let prefix = string.components(separatedBy: " [").first,
                      let timestamp = CopilotLogDateFormatter.log.date(from: prefix) else {
                    continue
                }
                days.insert(TimeHelpers.startOfDay(for: timestamp))
            }
        }

        if days.isEmpty,
           let fallback = fallbackLogDate(for: url) {
            days.insert(TimeHelpers.startOfDay(for: fallback))
        }

        return days.sorted()
    }

    private func fallbackLogDate(for url: URL) -> Date? {
        let pathComponents = url.pathComponents.reversed()
        for component in pathComponents {
            if let date = CopilotLogDateFormatter.path.date(from: component) {
                return date
            }

            if component.hasPrefix("output_logging_") {
                let raw = String(component.dropFirst("output_logging_".count))
                if let date = CopilotLogDateFormatter.path.date(from: raw) {
                    return date
                }
            }
        }

        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
            return values.contentModificationDate ?? values.creationDate
        }

        return nil
    }

    private func localActivityWeight(for eventType: String) -> Double? {
        switch eventType {
        case "user.message", "assistant.message", "session.start":
            return 1
        default:
            return nil
        }
    }

    private func localActivityTimestamp(in row: [String: Any], eventType: String) -> Date? {
        if let timestamp = TimeHelpers.parseISODate(stringValue(row["timestamp"])) {
            return timestamp
        }

        if eventType == "session.start",
           let data = row["data"] as? [String: Any],
           let startTime = TimeHelpers.parseISODate(stringValue(data["startTime"])) {
            return startTime
        }

        return nil
    }
}

private struct CopilotCredential {
    enum Source {
        case openUsageKeychain
        case githubCLI
        case state
    }

    let token: String
    let source: Source
}

private struct CopilotLocalActivity {
    let heatmap: [DailyCell]
    let todayCount: Int
}

private enum CopilotLogDateFormatter {
    static let log: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static let path: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()
}