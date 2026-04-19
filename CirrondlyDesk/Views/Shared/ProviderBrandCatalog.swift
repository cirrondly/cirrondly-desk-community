import Foundation
import SwiftUI

enum ProviderBrandCatalog {
    private static let fallbackHexes: [String: String] = [
        "amp": "#F34E3F",
        "antigravity": "#4285F4",
        "claude": "#DE7356",
        "codex": "#74AA9C",
        "copilot": "#A855F7",
        "cursor": "#000000",
        "factory": "#020202",
        "gemini": "#4285F4",
        "jetbrains-ai-assistant": "#7D5FE6",
        "kimi": "#000000",
        "kiro": "#C09CFF",
        "minimax": "#F5433C",
        "mock": "#EF4444",
        "opencode-go": "#000000",
        "perplexity": "#20808D",
        "synthetic": "#000000",
        "windsurf": "#111111",
        "zai": "#2D2D2D"
    ]

    private static let aliases: [String: String] = [
        "claude-code": "claude",
        "claude-subscription": "claude",
        "jetbrains-ai": "jetbrains-ai-assistant"
    ]

    private static let solidIconBackgroundProviders: Set<String> = ["copilot"]

    private static let brandHexes: [String: String] = {
        guard let url = Bundle.main.url(forResource: "provider-brands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode([String: String].self, from: data) else {
            return fallbackHexes
        }

        return fallbackHexes.merging(payload) { _, bundled in bundled }
    }()

    static func color(for identifier: String) -> Color {
        let pluginIdentifier = pluginIdentifier(for: identifier)
        guard let hex = brandHexes[pluginIdentifier] else {
            return .cirrondlyBlueDark
        }
        return Color(hex: hex)
    }

    static func tint(for identifier: String, opacity: Double) -> Color {
        color(for: identifier).opacity(opacity)
    }

    static func pluginIdentifier(for identifier: String) -> String {
        aliases[identifier] ?? identifier
    }

    static func usesSolidIconBackground(for identifier: String) -> Bool {
        solidIconBackgroundProviders.contains(pluginIdentifier(for: identifier))
    }
}