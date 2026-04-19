import Foundation

@MainActor
final class PollingManager {
    var baseInterval: TimeInterval = 300
    var activeInterval: TimeInterval = 30
    var backgroundInterval: TimeInterval = 900

    private let usageAggregator: UsageAggregator
    private let serviceStatusMonitor: ServiceStatusMonitor
    private let exporter: StatusLineExporter
    private let notifications: NotificationService
    private let reportingScheduler: ReportingScheduler

    private var loopTask: Task<Void, Never>?
    private var currentInterval: TimeInterval = 300

    init(usageAggregator: UsageAggregator, serviceStatusMonitor: ServiceStatusMonitor, exporter: StatusLineExporter, notifications: NotificationService, reportingScheduler: ReportingScheduler) {
        self.usageAggregator = usageAggregator
        self.serviceStatusMonitor = serviceStatusMonitor
        self.exporter = exporter
        self.notifications = notifications
        self.reportingScheduler = reportingScheduler
        currentInterval = baseInterval
    }

    func start() {
        reportingScheduler.scheduleHourly()
        guard loopTask == nil else { return }

        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAndProcess(force: false)
                try? await Task.sleep(for: .seconds(self.currentInterval))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        reportingScheduler.stop()
    }

    func onPopoverOpen() {
        currentInterval = activeInterval
    }

    func onPopoverClose() {
        currentInterval = baseInterval
    }

    func onPowerChange(unplugged: Bool) {
        currentInterval = unplugged ? backgroundInterval : baseInterval
    }

    func forceRefresh() async {
        await refreshAndProcess(force: true)
    }

    private func refreshAndProcess(force: Bool) async {
        async let usageRefresh: Void = usageAggregator.refresh(force: force)
        async let serviceRefresh: Void = serviceStatusMonitor.refreshIfNeeded(force: force)
        _ = await (usageRefresh, serviceRefresh)
        guard let snapshot = usageAggregator.snapshot else { return }
        exporter.export(snapshot: snapshot)
        notifications.handle(snapshot: snapshot)
        await reportingScheduler.sendDueReportIfNeeded()
    }
}