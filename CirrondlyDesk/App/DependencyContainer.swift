import Combine
import Foundation

@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    let keychainService: KeychainService
    let providerRegistry: ProviderRegistry
    let usageAggregator: UsageAggregator
    let serviceStatusMonitor: ServiceStatusMonitor
    let pollingManager: PollingManager
    let notificationService: NotificationService
    let statusLineExporter: StatusLineExporter
    let apiClient: CirrondlyAPIClient
    let teamEnrollmentService: TeamEnrollmentService
    let launchAtLoginService: LaunchAtLoginService
    let updateChecker: UpdateChecker
    let analyticsHeartbeat: AnalyticsHeartbeat
    let reportingScheduler: ReportingScheduler

    private var cancellables = Set<AnyCancellable>()

    private init() {
        keychainService = KeychainService()
        apiClient = CirrondlyAPIClient(keychainService: keychainService)
        providerRegistry = ProviderRegistry(keychainService: keychainService)
        usageAggregator = UsageAggregator(providerRegistry: providerRegistry)
        serviceStatusMonitor = ServiceStatusMonitor()
        notificationService = NotificationService()
        statusLineExporter = StatusLineExporter()
        teamEnrollmentService = TeamEnrollmentService(apiClient: apiClient, keychainService: keychainService)
        launchAtLoginService = LaunchAtLoginService()
        updateChecker = UpdateChecker()
        analyticsHeartbeat = AnalyticsHeartbeat()
        reportingScheduler = ReportingScheduler(apiClient: apiClient, aggregator: usageAggregator, enrollment: teamEnrollmentService, keychainService: keychainService)
        pollingManager = PollingManager(usageAggregator: usageAggregator, serviceStatusMonitor: serviceStatusMonitor, exporter: statusLineExporter, notifications: notificationService, reportingScheduler: reportingScheduler)

        bindObjectChanges()
    }

    private func bindObjectChanges() {
        providerRegistry.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        usageAggregator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        serviceStatusMonitor.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}