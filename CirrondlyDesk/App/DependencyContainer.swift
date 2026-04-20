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
    let launchAtLoginService: LaunchAtLoginService
    let updateChecker: UpdateChecker
    let historyWindowManager: ProviderHistoryWindowManager

    private var cancellables = Set<AnyCancellable>()

    private init() {
        keychainService = KeychainService()
        providerRegistry = ProviderRegistry(keychainService: keychainService)
        usageAggregator = UsageAggregator(providerRegistry: providerRegistry)
        serviceStatusMonitor = ServiceStatusMonitor()
        notificationService = NotificationService()
        statusLineExporter = StatusLineExporter()
        launchAtLoginService = LaunchAtLoginService()
        updateChecker = UpdateChecker()
        historyWindowManager = ProviderHistoryWindowManager()
        pollingManager = PollingManager(usageAggregator: usageAggregator, serviceStatusMonitor: serviceStatusMonitor, exporter: statusLineExporter, notifications: notificationService)

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