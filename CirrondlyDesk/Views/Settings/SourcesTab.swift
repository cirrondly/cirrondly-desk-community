import SwiftUI

struct ProvidersTab: View {
    @EnvironmentObject private var container: DependencyContainer
    @AppStorage("sources.claude.sessionKey") private var claudeSessionKey = ""
    @State private var selectedProviderID: String?

    private var providers: [any UsageProvider] {
        container.providerRegistry.providers
    }

    private var selectedProvider: (any UsageProvider)? {
        if let selectedProviderID, let provider = container.providerRegistry.provider(id: selectedProviderID) {
            return provider
        }
        return providers.first
    }

    private var providerIDsKey: String {
        providers.map(\.identifier).joined(separator: "|")
    }

    private func providerToggleBinding(for provider: any UsageProvider) -> Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: { newValue in
                container.providerRegistry.setEnabled(newValue, for: provider.identifier)
                container.usageAggregator.syncEnabledProviders()
                Task { await container.pollingManager.forceRefresh() }
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 18) {
                SettingsPaneScroll {
                    SettingsSectionCard(title: "Providers", subtitle: "Enable the sources Cirrondly should track and inspect their current state.", eyebrow: "Sources") {
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(
                                title: "Providers",
                                subtitle: "This list controls which sources appear in the app and which providers are polled in the background.",
                                eyebrow: "Sources"
                            )

                            Button("Refresh all providers") {
                                Task { await container.pollingManager.forceRefresh() }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(providers.enumerated()), id: \.element.identifier) { _, provider in
                                    ProviderSidebarRow(
                                        provider: provider,
                                        result: container.usageAggregator.providerResult(for: provider.identifier),
                                        isRefreshing: container.usageAggregator.isRefreshing,
                                        isSelected: selectedProviderID == provider.identifier || (selectedProviderID == nil && providers.first?.identifier == provider.identifier),
                                        isEnabled: providerToggleBinding(for: provider),
                                        onSelect: { selectedProviderID = provider.identifier }
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity)

                if let provider = selectedProvider {
                    ProviderDetailPanel(
                        provider: provider,
                        result: container.usageAggregator.providerResult(for: provider.identifier),
                        isRefreshing: container.usageAggregator.isRefreshing,
                        isEnabled: providerToggleBinding(for: provider),
                        claudeSessionKey: $claudeSessionKey,
                        refresh: {
                            Task { await container.pollingManager.forceRefresh() }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SettingsEmptyState(
                        title: "No provider selected",
                        subtitle: "Enable a source from the sidebar to inspect its current status and configuration.",
                        symbol: "square.grid.2x2"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            ensureSelection()
        }
        .onChange(of: providerIDsKey) {
            ensureSelection()
        }
        .onChange(of: claudeSessionKey) {
            Task { await container.pollingManager.forceRefresh() }
        }
    }

    private func ensureSelection() {
        guard !providers.isEmpty else {
            selectedProviderID = nil
            return
        }

        if let selectedProviderID, providers.contains(where: { $0.identifier == selectedProviderID }) {
            return
        }

        selectedProviderID = providers.first?.identifier
    }
}

private struct ProviderSidebarRow: View {
    let provider: any UsageProvider
    let result: ProviderResult?
    let isRefreshing: Bool
    let isSelected: Bool
    @Binding var isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    ProviderBrandBadge(providerID: provider.identifier)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(Typography.body(13, weight: .semibold))
                                .foregroundStyle(Color.cirrondlyBlueDark)

                            ProviderServiceStatusView(providerID: provider.identifier, style: .dot)

                            if isRefreshing, isEnabled {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }

                        Text(subtitle)
                            .font(Typography.body(11))
                            .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? brandColor.opacity(0.12) : Color.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? brandColor.opacity(0.32) : Color.cirrondlyBlueLight.opacity(0.7), lineWidth: 1)
        )
    }

    private var brandColor: Color {
        ProviderBrandCatalog.color(for: provider.identifier)
    }

    private var subtitle: String {
        guard isEnabled else { return "Disabled in the app" }
        if let warning = result?.warnings.first?.message, !warning.isEmpty {
            return warning
        }
        if let primary = result?.primaryWindow {
            return "\(primary.kind.title) · \(Int(primary.percentage.rounded()))%"
        }
        return "Enabled and waiting for usage data"
    }
}

private struct ProviderDetailPanel: View {
    let provider: any UsageProvider
    let result: ProviderResult?
    let isRefreshing: Bool
    @Binding var isEnabled: Bool
    @Binding var claudeSessionKey: String
    let refresh: () -> Void

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: provider.displayName, subtitle: provider.category.title, eyebrow: "Provider") {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    ProviderInfoGrid(provider: provider, result: result, isRefreshing: isRefreshing, isEnabled: isEnabled)

                    if let warnings = nonEmptyWarnings {
                        warningsSection(warnings)
                    }
                }
            }

            if let result {
                SettingsSectionCard(title: "Usage Windows", subtitle: "These cards reflect the latest provider snapshot available in the app.", eyebrow: "Metrics") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(
                            title: "Usage windows",
                            subtitle: "The menu bar and popover derive their most important status from these values.",
                            eyebrow: "Metrics"
                        )

                        if result.windows.isEmpty {
                            Text("No quota windows were returned for this provider yet.")
                                .font(Typography.body(11))
                                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                                ForEach(result.windows) { window in
                                    ProviderWindowCard(window: window)
                                }
                            }
                        }
                    }
                }
            }

            if provider.identifier == "claude-code" {
                SettingsSectionCard(title: "Manual Auth", subtitle: "Optional fallback for Claude's web session key.", eyebrow: "Claude") {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(
                            title: "Claude session key",
                            subtitle: "Uses Claude.ai's internal API as a fallback. This may break if Anthropic changes its web auth flow.",
                            eyebrow: "Claude"
                        )

                        SecureField("Claude sessionKey", text: $claudeSessionKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ProviderBrandBadge(providerID: provider.identifier, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(provider.displayName)
                        .font(Typography.body(22, weight: .semibold))
                        .foregroundStyle(Color.cirrondlyBlueDark)

                    ProviderServiceStatusView(providerID: provider.identifier, style: .dot)

                    SettingsBadge(title: provider.category.title, tint: brandColor)
                }

                Text(statusLine)
                    .font(Typography.body(12))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(brandColor)

            ProviderServiceStatusPageButton(providerID: provider.identifier)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var nonEmptyWarnings: [ProviderWarning]? {
        guard let result, !result.warnings.isEmpty else { return nil }
        return result.warnings
    }

    private var brandColor: Color {
        ProviderBrandCatalog.color(for: provider.identifier)
    }

    private var statusLine: String {
        if !isEnabled {
            return "Disabled. This provider will not appear in the app or participate in background refresh."
        }
        if isRefreshing {
            return "Refreshing provider data now."
        }
        if let warning = result?.warnings.first?.message, !warning.isEmpty {
            return warning
        }
        if let result {
            return "Tracking via \(sourceLabel(result.source)) with profile \(result.profile)."
        }
        return "Enabled and waiting for the first successful refresh."
    }

    private func warningsSection(_ warnings: [ProviderWarning]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest messages")
                .font(Typography.body(13, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark)

            ForEach(warnings) { warning in
                Text(warning.message)
                    .font(Typography.body(11))
                    .foregroundStyle(Color.cirrondlyBlueDark)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(warningBackground(for: warning.level), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func warningBackground(for level: ProviderWarningLevel) -> Color {
        switch level {
        case .info:
            return Color.cirrondlyBlueLightest.opacity(0.95)
        case .warning:
            return Color.cirrondlyWarningOrange.opacity(0.16)
        case .critical:
            return Color.cirrondlyCriticalRed.opacity(0.14)
        }
    }

    private func sourceLabel(_ source: DataSource) -> String {
        switch source {
        case .local:
            return "local data"
        case .api:
            return "provider APIs"
        case .mixed:
            return "mixed sources"
        }
    }
}

private struct ProviderInfoGrid: View {
    let provider: any UsageProvider
    let result: ProviderResult?
    let isRefreshing: Bool
    let isEnabled: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            infoCard(title: "State", value: stateText)
            infoCard(title: "Source", value: sourceText)
            infoCard(title: "Profile", value: result?.profile ?? provider.activeProfile?.name ?? "Default")
            infoCard(title: "Updated", value: updatedText)
        }
    }

    private func infoCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.body(11, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.64))
            Text(value)
                .font(Typography.body(13, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.cirrondlyBlueLight.opacity(0.72), lineWidth: 1)
        )
    }

    private var stateText: String {
        if !isEnabled { return "Disabled" }
        if isRefreshing { return "Refreshing" }
        if let warning = result?.warnings.first {
            switch warning.level {
            case .info:
                return "Informational"
            case .warning:
                return "Needs attention"
            case .critical:
                return "Critical"
            }
        }
        if result != nil { return "Connected" }
        return "Enabled"
    }

    private var sourceText: String {
        guard let result else { return "Awaiting refresh" }
        switch result.source {
        case .local:
            return "Local"
        case .api:
            return "API"
        case .mixed:
            return "Mixed"
        }
    }

    private var updatedText: String {
        guard let result else { return "Not fetched yet" }
        return RelativeDateTimeFormatter().localizedString(for: result.freshness, relativeTo: Date())
    }
}

private struct ProviderWindowCard: View {
    let window: Window

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title)
                    .font(Typography.body(13, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(Int(window.percentage.rounded()))%")
                    .font(Typography.body(15, weight: .semibold))
                    .foregroundStyle(progressColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.cirrondlyBlueLightest)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(progressColor)
                        .frame(width: max(10, proxy.size.width * CGFloat(window.percentage / 100)))
                }
            }
            .frame(height: 10)

            Text(valueText)
                .font(Typography.body(11))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))

            if let resetAt = window.resetAt {
                Text("Resets \(RelativeDateTimeFormatter().localizedString(for: resetAt, relativeTo: Date()))")
                    .font(Typography.body(10))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.58))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.cirrondlyBlueLight.opacity(0.72), lineWidth: 1)
        )
    }

    private var valueText: String {
        if let limit = window.limit {
            return "\(formatted(window.used)) / \(formatted(limit)) \(unitText)"
        }
        return "\(formatted(window.used)) \(unitText)"
    }

    private var unitText: String {
        switch window.unit {
        case .tokens:
            return "tokens"
        case .requests:
            return "requests"
        case .credits:
            return "credits"
        case .dollars:
            return "USD"
        }
    }

    private var progressColor: Color {
        switch window.percentage {
        case 90...:
            return .cirrondlyCriticalRed
        case 70...:
            return .cirrondlyWarningOrange
        default:
            return .cirrondlyGreenAccent
        }
    }

    private func formatted(_ value: Double) -> String {
        if window.unit == .dollars {
            return String(format: "$%.2f", value)
        }
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private struct ProviderBrandBadge: View {
    let providerID: String
    var size: CGFloat = 34

    var body: some View {
        ProviderIconBadge(identifier: providerID, size: size)
    }
}