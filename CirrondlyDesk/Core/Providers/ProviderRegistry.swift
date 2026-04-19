import Foundation

@MainActor
final class ProviderRegistry: ObservableObject {
    @Published private(set) var providers: [any UsageProvider]

    init(keychainService: KeychainService) {
        providers = [
            ClaudeCodeProvider(keychainService: keychainService),
            CodexProvider(keychainService: keychainService),
            KiroProvider(),
            CopilotProvider(keychainService: keychainService)
        ]
    }

    func enabledProviders() -> [any UsageProvider] {
        providers.filter { $0.isEnabled }
    }

    func provider(id: String) -> (any UsageProvider)? {
        providers.first { $0.identifier == id }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let provider = provider(id: id) else { return }
        provider.isEnabled = enabled
        providers = providers.map { $0 }
    }
}