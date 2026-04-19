import AppKit
import Foundation

final class JetBrainsAIProvider: UsageProvider {
    static let identifier = "jetbrains-ai"
    static let displayName = "JetBrains AI"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let creditUnitScale = 100_000.0
    private let quotaFilename = "AIAssistantQuotaManager2.xml"
    private let productPrefixes = [
        "Aqua", "AndroidStudio", "CLion", "DataGrip", "DataSpell", "GoLand",
        "IdeaIC", "IntelliJIdea", "IntelliJIdeaCE", "PhpStorm", "PyCharm",
        "PyCharmCE", "Rider", "RubyMine", "RustRover", "WebStorm", "Writerside"
    ]

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.jetbrains-ai.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.jetbrains-ai.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        !quotaPaths().isEmpty || runningIDEName() != nil
    }

    func probe() async throws -> ProviderResult {
        let states = quotaPaths().compactMap(readQuotaState(at:))
        guard let chosen = pickBestState(states) else {
            let profile = runningIDEName() ?? newestPyCharmDirectory() ?? "JetBrains"
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: profile,
                windows: [],
                today: .zero,
                burnRate: nil,
                dailyHeatmap: [],
                models: [],
                source: .local,
                freshness: Date(),
                warnings: [ProviderWarning(level: .info, message: "JetBrains AI Assistant was detected, but local quota data was unavailable. Open AI Assistant once and try again.")]
            )
        }

        let quota = chosen.quota
        let percentage = min(100, max(0, (quota.used / quota.maximum) * 100))
        let scale = displayScale(quota: quota, nextRefill: chosen.nextRefill)
        let usedCredits = formatCredits(quota.used / scale)
        let totalCredits = formatCredits(quota.maximum / scale)
        let remainingText = quota.remaining.map { formatCredits($0 / scale) + " credits" }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: runningIDEName() ?? chosen.ideName ?? newestPyCharmDirectory() ?? "JetBrains",
            windows: [
                Window(
                    kind: .monthly,
                    used: quota.used,
                    limit: quota.maximum,
                    unit: .requests,
                    percentage: percentage,
                    resetAt: chosen.resetAt
                )
            ],
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .local,
            freshness: Date(),
            warnings: [
                ProviderWarning(level: .info, message: "Used \(usedCredits) / \(totalCredits) credits."),
                remainingText.map { ProviderWarning(level: .info, message: "Remaining: \($0)") }
            ].compactMap { $0 }
        )
    }

    private func quotaPaths() -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/JetBrains", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            return []
        }

        return entries
            .filter { isLikelyIDEDirectory($0.lastPathComponent) }
            .map { $0.appending(path: "options", directoryHint: .isDirectory).appending(path: quotaFilename) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func isLikelyIDEDirectory(_ name: String) -> Bool {
        let hasPrefix = productPrefixes.contains { name.hasPrefix($0) }
        guard hasPrefix else { return false }
        return name.range(of: #"\d{4}\.\d"#, options: .regularExpression) != nil
    }

    private func readQuotaState(at url: URL) -> JetBrainsQuotaState? {
        guard let xml = try? String(contentsOf: url, encoding: .utf8),
              let quotaInfo = parseOptionJSON(named: "quotaInfo", in: xml),
              let quota = normalizeQuota(quotaInfo) else {
            return nil
        }

        let nextRefill = parseOptionJSON(named: "nextRefill", in: xml)
        let ideName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let resetAt = parseResetDate(quota.until, nextRefill: nextRefill)
        return JetBrainsQuotaState(path: url, ideName: ideName, quota: quota, nextRefill: nextRefill, resetAt: resetAt)
    }

    private func parseOptionJSON(named optionName: String, in xml: String) -> [String: Any]? {
        let pattern = #"<option\b[^>]*\bname="\#(optionName)"[^>]*/>"#
        guard let elementRegex = try? NSRegularExpression(pattern: pattern),
              let match = elementRegex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let matchRange = Range(match.range, in: xml) else {
            return nil
        }

        let element = String(xml[matchRange])
        guard let valueRegex = try? NSRegularExpression(pattern: #"\bvalue="([^"]*)""#),
              let valueMatch = valueRegex.firstMatch(in: element, range: NSRange(element.startIndex..., in: element)),
              let valueRange = Range(valueMatch.range(at: 1), in: element) else {
            return nil
        }

        let decoded = decodeXMLEntities(String(element[valueRange]))
        guard let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func decodeXMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#13;", with: "\r")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func normalizeQuota(_ quotaInfo: [String: Any]) -> JetBrainsQuota? {
        var maximum = doubleValue(quotaInfo["maximum"])
        var used = doubleValue(quotaInfo["current"])
        var remaining = doubleValue(quotaInfo["available"])

        let tariff = quotaInfo["tariffQuota"] as? [String: Any]
        let topUp = quotaInfo["topUpQuota"] as? [String: Any]

        if maximum == nil {
            let tariffMaximum = tariff.flatMap { doubleValue($0["maximum"]) } ?? 0
            let topUpMaximum = topUp.flatMap { doubleValue($0["maximum"]) } ?? 0
            if tariff != nil || topUp != nil {
                maximum = tariffMaximum + topUpMaximum
            }
        }

        if used == nil {
            let tariffUsed = tariff.flatMap { doubleValue($0["current"]) } ?? 0
            let topUpUsed = topUp.flatMap { doubleValue($0["current"]) } ?? 0
            if tariff != nil || topUp != nil {
                used = tariffUsed + topUpUsed
            }
        }

        if remaining == nil {
            let tariffRemaining = tariff.flatMap { doubleValue($0["available"]) } ?? 0
            let topUpRemaining = topUp.flatMap { doubleValue($0["available"]) } ?? 0
            if tariff != nil || topUp != nil {
                remaining = tariffRemaining + topUpRemaining
            }
        }

        if remaining == nil, let maximum, let used {
            remaining = maximum - used
        }

        guard let maximum, maximum > 0, let used else { return nil }
        let clampedUsed = min(max(used, 0), maximum)
        let clampedRemaining = remaining.map { min(max($0, 0), maximum) }
        return JetBrainsQuota(used: clampedUsed, maximum: maximum, remaining: clampedRemaining, until: stringValue(quotaInfo["until"]))
    }

    private func parseResetDate(_ until: String?, nextRefill: [String: Any]?) -> Date? {
        if let next = stringValue(nextRefill?["next"]), let date = TimeHelpers.parseISODate(next) {
            return date
        }
        return TimeHelpers.parseISODate(until)
    }

    private func pickBestState(_ states: [JetBrainsQuotaState]) -> JetBrainsQuotaState? {
        states.max { lhs, rhs in
            let lhsReset = lhs.resetAt ?? .distantPast
            let rhsReset = rhs.resetAt ?? .distantPast
            if lhsReset != rhsReset {
                return lhsReset < rhsReset
            }

            let lhsRatio = lhs.quota.maximum > 0 ? lhs.quota.used / lhs.quota.maximum : 0
            let rhsRatio = rhs.quota.maximum > 0 ? rhs.quota.used / rhs.quota.maximum : 0
            if lhsRatio != rhsRatio {
                return lhsRatio < rhsRatio
            }

            return lhs.quota.used < rhs.quota.used
        }
    }

    private func displayScale(quota: JetBrainsQuota, nextRefill: [String: Any]?) -> Double {
        var maximum = max(abs(quota.maximum), abs(quota.used), abs(quota.remaining ?? 0))
        if let tariff = nextRefill?["tariff"] as? [String: Any], let amount = doubleValue(tariff["amount"]) {
            maximum = max(maximum, abs(amount))
        }
        return maximum >= creditUnitScale ? creditUnitScale : 1
    }

    private func formatCredits(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let string = String(format: "%.2f", rounded)
        return string.replacingOccurrences(of: #"\.0+$|(?<=\.[0-9])0+$"#, with: "", options: .regularExpression)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }

    private func runningIDEName() -> String? {
        NSWorkspace.shared.runningApplications
            .compactMap(\ .localizedName)
            .first { $0.localizedCaseInsensitiveContains("pycharm") || $0.localizedCaseInsensitiveContains("jetbrains") }
    }

    private func newestPyCharmDirectory() -> String? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/JetBrains")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return entries
            .filter { $0.lastPathComponent.localizedCaseInsensitiveContains("pycharm") }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first?
            .lastPathComponent
    }
}

private struct JetBrainsQuotaState {
    let path: URL
    let ideName: String?
    let quota: JetBrainsQuota
    let nextRefill: [String: Any]?
    let resetAt: Date?
}

private struct JetBrainsQuota {
    let used: Double
    let maximum: Double
    let remaining: Double?
    let until: String?
}