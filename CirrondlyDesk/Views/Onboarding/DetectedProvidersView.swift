import SwiftUI

struct DetectedProvidersView: View {
    let providers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected providers")
                .font(Typography.body(18, weight: .semibold))
            ForEach(providers, id: \.self) { provider in
                Label(provider, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.cirrondlyGreenAccent)
            }
        }
        .padding(24)
    }
}