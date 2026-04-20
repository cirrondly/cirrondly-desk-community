import SwiftUI

struct ProfilesTab: View {
    @EnvironmentObject private var container: DependencyContainer

    var body: some View {
        List {
            ForEach(Array(container.providerRegistry.providers.enumerated()), id: \.element.identifier) { _, provider in
                Section(provider.displayName) {
                    if provider.profiles.isEmpty {
                        Text("No local profiles detected")
                            .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))
                    } else {
                        ForEach(provider.profiles) { profile in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(profile.name)
                                                .font(Typography.body(12, weight: .semibold))

                                            if profile.matches(provider.activeProfile) {
                                                Text("active")
                                                    .font(Typography.body(10, weight: .semibold))
                                                    .foregroundStyle(Color.cirrondlyGreenAccent)
                                            }
                                        }

                                        if let planName = profile.planName, !planName.isEmpty {
                                            Text(planName)
                                                .font(Typography.body(10))
                                                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                                        }

                                        if let lastUsedText = lastUsedText(for: profile) {
                                            Text(lastUsedText)
                                                .font(Typography.body(10))
                                                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                                        }
                                    }

                                    Spacer()

                                    Button(profile.matches(provider.activeProfile) ? "Active" : "Make Active") {
                                        container.providerRegistry.setActiveProfile(profile, for: provider.identifier)
                                        Task {
                                            await container.usageAggregator.refresh(force: true)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(profile.matches(provider.activeProfile))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .padding()
    }

    private func lastUsedText(for profile: ProviderProfile) -> String? {
        guard let lastUsedAt = profile.lastUsedAt else { return nil }
        return "Last used: \(RelativeDateTimeFormatter().localizedString(for: lastUsedAt, relativeTo: Date()))"
    }
}