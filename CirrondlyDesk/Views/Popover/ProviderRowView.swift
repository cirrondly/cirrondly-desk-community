import AppKit
import SwiftUI

struct ProviderRowView: View {
    let provider: ProviderResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ProviderIconView(identifier: provider.identifier)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(Typography.body(13, weight: .semibold))
                            .foregroundStyle(Color.cirrondlyBlack)

                        ProviderServiceStatusView(providerID: provider.identifier, style: .pill)
                    }
                    Text(subtitle)
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.78))
                }
                Spacer()

                Text(provider.category.title)
                    .font(Typography.body(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(brandColor)
                    .background(categoryBackground, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(categoryBorder, lineWidth: 1)
                    )
            }

            ForEach(provider.windows.prefix(3)) { window in
                if window.kind == .weekly {
                    WeeklyProgressBar(window: window)
                } else {
                    SessionProgressBar(title: window.kind.title, window: window)
                }
            }

            ContributionHeatmap(cells: provider.dailyHeatmap, accentColor: brandColor)

            if !provider.warnings.isEmpty {
                ForEach(provider.warnings) { warning in
                    Text(warning.message)
                        .font(Typography.body(10))
                        .foregroundStyle(warning.level == .critical ? Color.cirrondlyCriticalRed : Color.cirrondlyBlueDark.opacity(0.65))
                }
            }
        }
        .padding(14)
        .background(Color.cirrondlyWhiteCard.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(brandColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var brandColor: Color {
        ProviderBrandCatalog.color(for: provider.identifier)
    }

    private var subtitle: String {
        let trimmed = provider.profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Default" else {
            switch provider.source {
            case .local:
                return "Local usage"
            case .api:
                return "Live account"
            case .mixed:
                return "Local + live data"
            }
        }
        return trimmed
    }

    private var categoryBackground: Color {
        brandColor.opacity(0.12)
    }

    private var categoryBorder: Color {
        brandColor.opacity(0.3)
    }
}

private struct ProviderIconView: View {
    let identifier: String

    var body: some View {
        ProviderIconBadge(identifier: identifier, size: 24, cornerRadius: 10)
    }
}