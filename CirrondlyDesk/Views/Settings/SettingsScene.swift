import SwiftUI

enum SettingsPaneTab: String, Hashable {
    case general
    case providers
    case display
    case advanced
    case about
}

struct SettingsScene: View {
    @State private var selection: SettingsPaneTab = .general

    var body: some View {
        ZStack {
            GradientBackground()

            TabView(selection: $selection) {
                GeneralTab()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsPaneTab.general)
                ProvidersTab()
                    .tabItem { Label("Providers", systemImage: "square.grid.2x2") }
                    .tag(SettingsPaneTab.providers)
                DisplayTab()
                    .tabItem { Label("Display", systemImage: "eye") }
                    .tag(SettingsPaneTab.display)
                AdvancedTab()
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                    .tag(SettingsPaneTab.advanced)
                AboutTab()
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(SettingsPaneTab.about)
            }
            .frame(minWidth: 920, minHeight: 620)
            .tint(Color.cirrondlyBlueDark)
            .foregroundStyle(Color.cirrondlyBlueDark)
            .padding(24)
        }
    }
}

struct SettingsPaneScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let eyebrow: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.cirrondlyBlueLight.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color.cirrondlyBlueDark.opacity(0.08), radius: 18, x: 0, y: 12)
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String?
    let eyebrow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .font(Typography.body(11, weight: .semibold))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.64))
            }

            Text(title)
                .font(Typography.body(20, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Typography.body(12))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsSplitRow<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.body(13, weight: .semibold))
                    .foregroundStyle(Color.cirrondlyBlueDark)
                Text(subtitle)
                    .font(Typography.body(11))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            accessory()
        }
    }
}

struct SettingsBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(Typography.body(10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct SettingsEmptyState: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.cirrondlyBlueDark)

            Text(title)
                .font(Typography.body(18, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark)

            Text(subtitle)
                .font(Typography.body(12))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.cirrondlyBlueLight.opacity(0.7), lineWidth: 1)
        )
    }
}