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
                    SettingsSectionCard(title: L10n.tr("settings.sources.providers.cardTitle"), subtitle: L10n.tr("settings.sources.providers.cardSubtitle"), eyebrow: L10n.tr("settings.tab.sources")) {
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(
                                title: L10n.tr("settings.sources.providers.headerTitle"),
                                subtitle: L10n.tr("settings.sources.providers.headerSubtitle"),
                                eyebrow: L10n.tr("settings.tab.sources")
                            )

                            Button(L10n.tr("settings.sources.providers.refreshAll")) {
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
                        title: L10n.tr("settings.sources.empty.title"),
                        subtitle: L10n.tr("settings.sources.empty.subtitle"),
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
        guard isEnabled else { return L10n.tr("settings.sources.sidebar.disabledInApp") }
        if let warning = result?.warnings.first?.message, !warning.isEmpty {
            return warning
        }
        if let primary = result?.primaryWindow {
            return "\(primary.kind.title) · \(Int(primary.percentage.rounded()))%"
        }
        return L10n.tr("settings.sources.sidebar.waitingForUsage")
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
            SettingsSectionCard(title: provider.displayName, subtitle: provider.category.title, eyebrow: L10n.tr("settings.sources.provider.eyebrow")) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    ProviderInfoGrid(provider: provider, result: result, isRefreshing: isRefreshing, isEnabled: isEnabled)

                    if let warnings = nonEmptyWarnings {
                        warningsSection(warnings)
                    }
                }
            }

            if let result {
                SettingsSectionCard(title: L10n.tr("settings.sources.windows.cardTitle"), subtitle: L10n.tr("settings.sources.windows.cardSubtitle"), eyebrow: L10n.tr("settings.sources.windows.eyebrow")) {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(
                            title: L10n.tr("settings.sources.windows.headerTitle"),
                            subtitle: L10n.tr("settings.sources.windows.headerSubtitle"),
                            eyebrow: L10n.tr("settings.sources.windows.eyebrow")
                        )

                        if result.windows.isEmpty {
                            Text(L10n.tr("settings.sources.windows.empty"))
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
                SettingsSectionCard(title: L10n.tr("settings.sources.claudeAuth.cardTitle"), subtitle: L10n.tr("settings.sources.claudeAuth.cardSubtitle"), eyebrow: L10n.tr("settings.sources.claudeAuth.eyebrow")) {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(
                            title: L10n.tr("settings.sources.claudeAuth.headerTitle"),
                            subtitle: L10n.tr("settings.sources.claudeAuth.headerSubtitle"),
                            eyebrow: L10n.tr("settings.sources.claudeAuth.eyebrow")
                        )

                        SecureField(L10n.tr("settings.sources.claudeAuth.fieldPlaceholder"), text: $claudeSessionKey)
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
            return L10n.tr("settings.sources.statusLine.disabled")
        }
        if isRefreshing {
            return L10n.tr("settings.sources.statusLine.refreshing")
        }
        if let warning = result?.warnings.first?.message, !warning.isEmpty {
            return warning
        }
        if let result {
            return L10n.tr("settings.sources.statusLine.tracking", sourceLabel(result.source), result.profile)
        }
        return L10n.tr("settings.sources.statusLine.waitingFirstRefresh")
    }

    private func warningsSection(_ warnings: [ProviderWarning]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("settings.sources.latestMessages"))
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
            return L10n.tr("settings.sources.sourceLabel.localData")
        case .api:
            return L10n.tr("settings.sources.sourceLabel.providerAPIs")
        case .mixed:
            return L10n.tr("settings.sources.sourceLabel.mixedSources")
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
            infoCard(title: L10n.tr("settings.sources.info.state"), value: stateText)
            infoCard(title: L10n.tr("settings.sources.info.source"), value: sourceText)
            infoCard(title: L10n.tr("settings.sources.info.profile"), value: result?.profile ?? provider.activeProfile?.name ?? L10n.tr("settings.sources.defaultProfile"))
            infoCard(title: L10n.tr("settings.sources.info.updated"), value: updatedText)
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
        if !isEnabled { return L10n.tr("settings.sources.state.disabled") }
        if isRefreshing { return L10n.tr("settings.sources.state.refreshing") }
        if let warning = result?.warnings.first {
            switch warning.level {
            case .info:
                return L10n.tr("settings.sources.state.informational")
            case .warning:
                return L10n.tr("settings.sources.state.needsAttention")
            case .critical:
                return L10n.tr("settings.sources.state.critical")
            }
        }
        if result != nil { return L10n.tr("settings.sources.state.connected") }
        return L10n.tr("settings.sources.state.enabled")
    }

    private var sourceText: String {
        guard let result else { return L10n.tr("settings.sources.source.awaitingRefresh") }
        switch result.source {
        case .local:
            return L10n.tr("settings.sources.source.local")
        case .api:
            return L10n.tr("settings.sources.source.api")
        case .mixed:
            return L10n.tr("settings.sources.source.mixed")
        }
    }

    private var updatedText: String {
        guard let result else { return L10n.tr("settings.sources.updated.notFetched") }
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
                Text(L10n.tr("progress.resets", RelativeDateTimeFormatter().localizedString(for: resetAt, relativeTo: Date())))
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
        window.unit.localizedLabel
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