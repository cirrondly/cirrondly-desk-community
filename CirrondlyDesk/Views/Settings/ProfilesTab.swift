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
                            HStack {
                                Text(profile.name)
                                Spacer()
                                if provider.activeProfile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.cirrondlyGreenAccent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .padding()
    }
}