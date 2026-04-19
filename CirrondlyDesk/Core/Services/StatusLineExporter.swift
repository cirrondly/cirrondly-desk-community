import Foundation

@MainActor
final class StatusLineExporter {
    func export(snapshot: UsageSnapshot) {
        guard UserDefaults.standard.object(forKey: "advanced.statusline.enabled") as? Bool ?? true else {
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = home.appending(path: ".cirrondly", directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "usage.json")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload = makePayload(snapshot: snapshot)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }

        let tempURL = directory.appending(path: "usage.json.tmp")
        try? data.write(to: tempURL, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
    }

    private func makePayload(snapshot: UsageSnapshot) -> [String: Any] {
        var providers: [String: Any] = [:]

        for provider in snapshot.providers {
            var payload: [String: Any] = [
                "today_cost_usd": provider.today.costUSD,
            ]

            if let burnRate = provider.burnRate {
                payload["burn_rate_usd_hr"] = burnRate.costPerHour
            }

            for window in provider.windows {
                payload[window.kind.reportingKey] = [
                    "utilization": Int(window.percentage.rounded()),
                    "resets_at": window.resetAt.map { TimeHelpers.iso8601Plain.string(from: $0) } as Any,
                ]
            }

            providers[provider.identifier] = payload
        }

        return [
            "last_updated": TimeHelpers.iso8601Plain.string(from: snapshot.generatedAt),
            "providers": providers,
            "summary": [
                "worst_percentage": Int(snapshot.summary.worstPercentage.rounded()),
                "worst_provider": snapshot.summary.worstProvider as Any,
                "worst_window": snapshot.summary.worstWindow as Any,
            ],
        ]
    }
}