import Foundation

@MainActor
final class ReportingScheduler {
    private let apiClient: CirrondlyAPIClient
    private let aggregator: UsageAggregator
    private let enrollment: TeamEnrollmentService
    private let keychainService: KeychainService
    private let defaults = UserDefaults.standard

    private var task: Task<Void, Never>?

    init(apiClient: CirrondlyAPIClient, aggregator: UsageAggregator, enrollment: TeamEnrollmentService, keychainService: KeychainService) {
        self.apiClient = apiClient
        self.aggregator = aggregator
        self.enrollment = enrollment
        self.keychainService = keychainService
    }

    func scheduleHourly() {
        guard enrollment.isEnrolled else {
            stop()
            return
        }

        if task != nil { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sendDueReportIfNeeded()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func sendDueReportIfNeeded() async {
        guard enrollment.isEnrolled else { return }
        let lastReportedAt = defaults.object(forKey: "team.lastReportedAt") as? Date
        if let lastReportedAt, Date().timeIntervalSince(lastReportedAt) < 3600 {
            return
        }
        await sendReport()
    }

    private func sendReport() async {
        guard
            let agentId = enrollment.agentId,
            let bearer = enrollment.agentSecret()
        else {
            return
        }

        let lastReportedAt = defaults.object(forKey: "team.lastReportedAt") as? Date
        do {
            let sessions = try await aggregator.collectSessionsForReporting(since: lastReportedAt)
            let payload = UsageReportPayload(
                agentId: agentId,
                periodStart: lastReportedAt ?? Date().addingTimeInterval(-3600),
                periodEnd: Date(),
                sessions: sessions
            )
            try await apiClient.reportUsage(payload, bearer: bearer)
            defaults.set(Date(), forKey: "team.lastReportedAt")
        } catch CirrondlyAPIError.unauthorized {
            enrollment.handleUnauthorized()
        } catch {
            return
        }
    }
}