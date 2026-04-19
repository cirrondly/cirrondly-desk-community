import AppKit
import SwiftUI

enum ProviderIconCatalog {
    static func image(for identifier: String) -> NSImage? {
        let resource = resourceName(for: identifier)
        let url = Bundle.main.url(forResource: resource, withExtension: "svg")
            ?? Bundle.main.url(forResource: resource, withExtension: "svg", subdirectory: "ProviderIcons")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func resourceName(for identifier: String) -> String {
        switch identifier {
        case "claude-code", "claude-subscription":
            return "claude"
        case "jetbrains-ai":
            return "jetbrains-ai"
        default:
            return identifier
        }
    }
}

struct ProviderIconBadge: View {
    let identifier: String
    var size: CGFloat = 34
    var cornerRadius: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(backgroundColor)

            if let image = ProviderIconCatalog.image(for: identifier) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.14)
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(fallbackColor)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: ProviderBrandCatalog.tint(for: identifier, opacity: 0.16), radius: 8, x: 0, y: 4)
    }

    private var radius: CGFloat {
        cornerRadius ?? size * 0.3
    }

    private var fallbackSymbol: String {
        switch identifier {
        case "continue":
            return "arrow.triangle.branch"
        case "aider":
            return "hammer.fill"
        default:
            return "bolt.circle.fill"
        }
    }

    private var backgroundColor: Color {
        if ProviderBrandCatalog.usesSolidIconBackground(for: identifier) {
            return ProviderBrandCatalog.color(for: identifier)
        }
        return Color.white.opacity(0.94)
    }

    private var borderColor: Color {
        if ProviderBrandCatalog.usesSolidIconBackground(for: identifier) {
            return Color.white.opacity(0.24)
        }
        return ProviderBrandCatalog.tint(for: identifier, opacity: 0.34)
    }

    private var fallbackColor: Color {
        if ProviderBrandCatalog.usesSolidIconBackground(for: identifier) {
            return Color.white
        }
        return ProviderBrandCatalog.color(for: identifier)
    }
}