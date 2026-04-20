import AppKit
import Foundation

final class CopilotProvider: UsageProvider {
    static let identifier = "copilot"
    static let displayName = "Copilot"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let keychainService: KeychainService
    private let session = URLSession(configuration: .ephemeral)
    private let calculator = BurnRateCalculator()
    private let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!
    private let openUsageService = "OpenUsage-copilot"
    private let githubCLIService = "gh:github.com"
    private let activeProfileDefaultsKey = "provider.copilot.activeProfile"
    private let cachedTokenDefaultsKey = "provider.copilot.cachedToken"
    private let knownPlanPrefix = "provider.copilot.plan."

    private var discoveredAccounts: [CopilotAccount] = []
    private var cachedProfiles: [ProviderProfile] = []
    private var selectedProfile: ProviderProfile?

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
        refreshProfiles()
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.copilot.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.copilot.enabled") }
    }

    var profiles: [ProviderProfile] {
        refreshProfiles()
        return cachedProfiles
    }

    var activeProfile: ProviderProfile? {
        get {
            refreshProfiles()
            return selectedProfile
        }
        set {
            refreshProfiles()
            selectedProfile = cachedProfiles.first(where: { $0.matches(newValue) }) ?? newValue
            persistActiveProfileSelection()
        }
    }

    func isAvailable() async -> Bool {
        refreshProfiles()
        return hasAnyCopilotFootprint()
    }

    func probe() async throws -> ProviderResult {
        refreshProfiles()
        let account = currentAccount()

        guard var credential = loadToken(for: account) else {
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

        let resetDate = parseCopilotResetDate(payload["quota_reset_date"])
            ?? parseCopilotResetDate(payload["limited_user_reset_date"])
            ?? computeCopilotResetDate(account: account)
        let monthlyWindowStart = previousMonthBoundary(for: resetDate)
        var windows: [Window] = []

        if let snapshots = payload["quota_snapshots"] as? [String: Any] {
            if let premium = makeProgressWindow(label: "Premium Requests", snapshot: snapshots["premium_interactions"] as? [String: Any], resetAt: resetDate, windowStart: monthlyWindowStart) {
                windows.append(premium)
            }
            if let chat = makeProgressWindow(label: "Chat Messages", snapshot: snapshots["chat"] as? [String: Any], resetAt: resetDate, windowStart: monthlyWindowStart) {
                windows.append(chat)
            }
        }

        if let limited = payload["limited_user_quotas"] as? [String: Any], let monthly = payload["monthly_quotas"] as? [String: Any] {
            if let chat = makeLimitedWindow(label: "Chat Messages", remaining: limited["chat"], total: monthly["chat"], resetAt: resetDate, windowStart: monthlyWindowStart) {
                windows.append(chat)
            }
            if let completions = makeLimitedWindow(label: "Inline Suggestions", remaining: limited["completions"], total: monthly["completions"], resetAt: resetDate, windowStart: monthlyWindowStart) {
                windows.append(completions)
            }
        }

        let warnings = windows.isEmpty ? [ProviderWarning(level: .info, message: "Copilot returned no quota data for this account.")] : []
        let plan = planLabel(from: stringValue(payload["copilot_plan"]))
        savePlan(plan, for: account)
        let profile = account?.login ?? account?.email ?? runningClientName() ?? detectedClientName() ?? plan ?? "GitHub"

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

    private func loadToken(for account: CopilotAccount?) -> CopilotCredential? {
        if let token = sanitizedToken(account?.oauthToken) {
            return CopilotCredential(token: token, source: .localConfig)
        }

        return loadOpenUsageToken() ?? loadGitHubCLIToken() ?? loadTokenFromDefaults()
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
        guard let token = defaults.string(forKey: cachedTokenDefaultsKey), !token.isEmpty else { return nil }
        return CopilotCredential(token: token, source: .state)
    }

    private func saveToken(_ token: String) {
        defaults.set(token, forKey: cachedTokenDefaultsKey)
        try? keychainService.save("{\"token\":\"\(token)\"}", service: openUsageService, account: "token")
    }

    private func clearCachedToken() {
        keychainService.deleteAll(service: openUsageService)
        defaults.removeObject(forKey: cachedTokenDefaultsKey)
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

    private func makeProgressWindow(label: String, snapshot: [String: Any]?, resetAt: Date?, windowStart: Date?) -> Window? {
        guard let remaining = numberValue(snapshot?["percent_remaining"]) else { return nil }
        let used = min(100, max(0, 100 - remaining))
        return Window(kind: .custom(label), used: used, limit: 100, unit: .requests, percentage: used, resetAt: resetAt, windowStart: windowStart)
    }

    private func makeLimitedWindow(label: String, remaining: Any?, total: Any?, resetAt: Date?, windowStart: Date?) -> Window? {
        guard let remaining = numberValue(remaining), let total = numberValue(total), total > 0 else { return nil }
        let used = total - remaining
        let percentage = min(100, max(0, (used / total) * 100))
        return Window(kind: .custom(label), used: used, limit: total, unit: .requests, percentage: percentage, resetAt: resetAt, windowStart: windowStart)
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
        if !cachedProfiles.isEmpty {
            return true
        }

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
            for url in transcriptURLs(in: root) {
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

    private func transcriptURLs(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var urls: [URL] = []
        while let nextObject = enumerator.nextObject() {
            guard let url = nextObject as? URL,
                  url.pathExtension == "jsonl",
                  url.path.contains("/GitHub.copilot-chat/transcripts/") else {
                continue
            }
            urls.append(url)
        }
        return urls
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

    private func refreshProfiles() {
        let accounts = discoverAccounts()
        discoveredAccounts = accounts
        let duplicateLogins = Set(
            Dictionary(grouping: accounts, by: { $0.login.lowercased() })
                .filter { $0.value.count > 1 }
                .keys
        )
        cachedProfiles = accounts.map { profile(from: $0, disambiguate: duplicateLogins.contains($0.login.lowercased())) }

        guard !cachedProfiles.isEmpty else {
            selectedProfile = nil
            defaults.removeObject(forKey: activeProfileDefaultsKey)
            return
        }

        if let storedIdentifier = defaults.string(forKey: activeProfileDefaultsKey),
           let storedProfile = cachedProfiles.first(where: { $0.stableIdentifier == storedIdentifier }) {
            selectedProfile = storedProfile
            return
        }

        if let selectedProfile,
           let matchedProfile = cachedProfiles.first(where: { $0.matches(selectedProfile) }) {
            self.selectedProfile = matchedProfile
            return
        }

        selectedProfile = cachedProfiles.max { lhs, rhs in
            (lhs.lastUsedAt ?? .distantPast) < (rhs.lastUsedAt ?? .distantPast)
        }
        persistActiveProfileSelection()
    }

    private func persistActiveProfileSelection() {
        guard let selectedProfile else {
            defaults.removeObject(forKey: activeProfileDefaultsKey)
            return
        }
        defaults.set(selectedProfile.stableIdentifier, forKey: activeProfileDefaultsKey)
    }

    private func currentAccount() -> CopilotAccount? {
        guard let selectedProfile else { return discoveredAccounts.first }
        return discoveredAccounts.first { $0.stableIdentifier == selectedProfile.stableIdentifier } ?? discoveredAccounts.first
    }

    private func discoverAccounts() -> [CopilotAccount] {
        var accountsByIdentifier: [String: CopilotAccount] = [:]

        mergeAccounts(from: homeConfigURL.appending(path: "apps.json"), source: "apps.json", into: &accountsByIdentifier)
        mergeAccounts(from: homeConfigURL.appending(path: "hosts.json"), source: "hosts.json", into: &accountsByIdentifier)

        for account in discoverJetBrainsCopilotAccounts() {
            merge(account, into: &accountsByIdentifier)
        }

        return accountsByIdentifier.values.sorted { lhs, rhs in
            if lhs.lastUsed != rhs.lastUsed {
                return (lhs.lastUsed ?? .distantPast) > (rhs.lastUsed ?? .distantPast)
            }
            return lhs.login.localizedCaseInsensitiveCompare(rhs.login) == .orderedAscending
        }
    }

    private var homeConfigURL: URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: ".config/github-copilot", directoryHint: .isDirectory)
    }

    private func mergeAccounts(from url: URL, source: String, into accountsByIdentifier: inout [String: CopilotAccount]) {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) else {
            return
        }

        let lastUsed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        var discovered: [CopilotAccount] = []
        if let object = payload as? [String: Any] {
            for (key, value) in object {
                collectAccounts(from: value, source: source, lastUsed: lastUsed, accountIdentifier: key, into: &discovered)
            }
        } else {
            collectAccounts(from: payload, source: source, lastUsed: lastUsed, accountIdentifier: nil, into: &discovered)
        }

        for account in discovered {
            merge(account, into: &accountsByIdentifier)
        }
    }

    private func collectAccounts(from value: Any, source: String, lastUsed: Date?, accountIdentifier: String?, into accounts: inout [CopilotAccount]) {
        if let entry = value as? [String: Any], let account = makeAccount(from: entry, source: source, lastUsed: lastUsed, accountIdentifier: accountIdentifier) {
            accounts.append(account)
        }

        if let object = value as? [String: Any] {
            for (key, nested) in object {
                collectAccounts(from: nested, source: source, lastUsed: lastUsed, accountIdentifier: accountIdentifier ?? key, into: &accounts)
            }
            return
        }

        if let array = value as? [Any] {
            for nested in array {
                collectAccounts(from: nested, source: source, lastUsed: lastUsed, accountIdentifier: accountIdentifier, into: &accounts)
            }
        }
    }

    private func makeAccount(from entry: [String: Any], source: String, lastUsed: Date?, accountIdentifier: String?) -> CopilotAccount? {
        let login = stringValue(entry["user"]) ?? stringValue(entry["login"]) ?? stringValue(entry["username"])
        let email = stringValue(entry["email"])
        let token = stringValue(entry["oauth_token"]) ?? stringValue(entry["oauthToken"]) ?? stringValue(entry["token"])
        let githubAppID = stringValue(entry["githubAppId"]) ?? accountIdentifier?.split(separator: ":").last.map(String.init)

        let resolvedLogin: String
        if let login, !login.isEmpty {
            resolvedLogin = login
        } else if let email, !email.isEmpty {
            resolvedLogin = email.components(separatedBy: "@").first ?? email
        } else {
            return nil
        }

        return CopilotAccount(
            login: resolvedLogin,
            serviceIdentifier: accountIdentifier?.lowercased() ?? resolvedLogin.lowercased(),
            githubAppID: githubAppID,
            email: email,
            tokenSource: source,
            lastUsed: lastUsed,
            oauthToken: token,
            billingApiResetDate: nil,
            plan: defaults.string(forKey: knownPlanPrefix + resolvedLogin.lowercased())
        )
    }

    private func discoverJetBrainsCopilotAccounts() -> [CopilotAccount] {
        let baseURL = fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/JetBrains", directoryHint: .isDirectory)
        guard let ideURLs = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var accounts: [CopilotAccount] = []
        for ideURL in ideURLs {
            let configURL = ideURL.appending(path: "options", directoryHint: .isDirectory).appending(path: "github-copilot-intellij.xml")
            guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { continue }

            let attributes = parseJetBrainsAttributes(in: text)
            let login = attributes.first { key, _ in
                let lowered = key.lowercased()
                return lowered.contains("user") || lowered.contains("login")
            }?.value
            let email = attributes.first { $0.key.lowercased().contains("email") }?.value
            let token = attributes.first { key, _ in
                let lowered = key.lowercased()
                return lowered.contains("oauth") || lowered.contains("token")
            }?.value

            guard login != nil || email != nil else { continue }
            let lastUsed = try? configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            accounts.append(
                CopilotAccount(
                    login: login ?? (email?.components(separatedBy: "@").first ?? "jetbrains"),
                    serviceIdentifier: ["jetbrains", login ?? email ?? UUID().uuidString].joined(separator: ":").lowercased(),
                    githubAppID: nil,
                    email: email,
                    tokenSource: "jetbrains",
                    lastUsed: lastUsed ?? nil,
                    oauthToken: token,
                    billingApiResetDate: nil,
                    plan: login.flatMap { defaults.string(forKey: knownPlanPrefix + $0.lowercased()) }
                )
            )
        }

        return accounts
    }

    private func parseJetBrainsAttributes(in text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"name=\"([^\"]+)\"\s+value=\"([^\"]+)\""#) else {
            return [:]
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).reduce(into: [:]) { partial, match in
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else {
                return
            }
            partial[String(text[keyRange])] = String(text[valueRange])
        }
    }

    private func merge(_ account: CopilotAccount, into accountsByIdentifier: inout [String: CopilotAccount]) {
        let identifier = account.stableIdentifier
        guard let existing = accountsByIdentifier[identifier] else {
            accountsByIdentifier[identifier] = account
            return
        }

        accountsByIdentifier[identifier] = CopilotAccount(
            login: existing.login,
            serviceIdentifier: existing.serviceIdentifier,
            githubAppID: existing.githubAppID ?? account.githubAppID,
            email: existing.email ?? account.email,
            tokenSource: existing.oauthToken != nil ? existing.tokenSource : account.tokenSource,
            lastUsed: max(existing.lastUsed ?? .distantPast, account.lastUsed ?? .distantPast) == .distantPast ? nil : max(existing.lastUsed ?? .distantPast, account.lastUsed ?? .distantPast),
            oauthToken: existing.oauthToken ?? account.oauthToken,
            billingApiResetDate: existing.billingApiResetDate ?? account.billingApiResetDate,
            plan: existing.plan ?? account.plan
        )
    }

    private func profile(from account: CopilotAccount, disambiguate: Bool) -> ProviderProfile {
        var metadata: [String: String] = ["tokenSource": account.tokenSource]
        if let email = account.email {
            metadata["email"] = email
        }
        if let lastUsed = account.lastUsed {
            metadata["lastUsed"] = TimeHelpers.iso8601Plain.string(from: lastUsed)
        }
        if let plan = account.plan {
            metadata["plan"] = plan
        }
        if let githubAppID = account.githubAppID {
            metadata["githubAppId"] = githubAppID
        }

        return ProviderProfile(
            name: profileName(for: account, disambiguate: disambiguate),
            serviceIdentifier: account.stableIdentifier,
            metadata: metadata
        )
    }

    private func profileName(for account: CopilotAccount, disambiguate: Bool) -> String {
        guard disambiguate else { return account.login }
        if let githubAppID = account.githubAppID, !githubAppID.isEmpty {
            let suffix = String(githubAppID.prefix(6))
            return "\(account.login) · \(suffix)"
        }
        return "\(account.login) · \(account.tokenSource)"
    }

    private func savePlan(_ plan: String?, for account: CopilotAccount?) {
        guard let account else { return }
        if let plan, !plan.isEmpty {
            defaults.set(plan, forKey: knownPlanPrefix + account.stableIdentifier)
        }
    }

    private func sanitizedToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func parseCopilotResetDate(_ value: Any?) -> Date? {
        if let string = stringValue(value) {
            if let date = TimeHelpers.parseISODate(string) {
                return date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: string) {
                return date
            }
        }

        if let numeric = numberValue(value) {
            return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1000 : numeric)
        }

        return nil
    }

    private func computeCopilotResetDate(account: CopilotAccount?) -> Date {
        if let apiReset = account?.billingApiResetDate {
            return apiReset
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? Date()
    }

    private func previousMonthBoundary(for resetDate: Date?) -> Date? {
        guard let resetDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(byAdding: .month, value: -1, to: resetDate)
    }
}

private struct CopilotCredential {
    enum Source {
        case localConfig
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

private struct CopilotAccount {
    let login: String
    let serviceIdentifier: String
    let githubAppID: String?
    let email: String?
    let tokenSource: String
    let lastUsed: Date?
    let oauthToken: String?
    let billingApiResetDate: Date?
    let plan: String?

    var stableIdentifier: String {
        serviceIdentifier.lowercased()
    }
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