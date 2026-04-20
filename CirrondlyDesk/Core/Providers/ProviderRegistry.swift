import Foundation

@MainActor
final class ProviderRegistry: ObservableObject {
    @Published private(set) var providers: [any UsageProvider]

    init(keychainService: KeychainService) {
        providers = [
            ClaudeCodeProvider(keychainService: keychainService),
            CursorProvider(keychainService: keychainService),
            CodexProvider(keychainService: keychainService),
            CopilotProvider(keychainService: keychainService),
            AntigravityProvider(),
            AmpProvider(),
            FactoryProvider(keychainService: keychainService),
            KiroProvider(),
            KimiProvider(),
            WindsurfProvider(),
            GeminiProvider(),
            MiniMaxProvider(),
            PerplexityProvider(),
            OpenCodeGoProvider(),
            SyntheticProvider(),
            ZAIProvider(),
            JetBrainsAIProvider(),
            ContinueProvider(),
            AiderProvider()
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

    func setActiveProfile(_ profile: ProviderProfile, for id: String) {
        guard let provider = provider(id: id) else { return }
        provider.activeProfile = profile
        providers = providers.map { $0 }
    }
}