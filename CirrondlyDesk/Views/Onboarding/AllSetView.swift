import SwiftUI

struct AllSetView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.cirrondlyGreenAccent)
            Text("All set")
                .font(Typography.body(20, weight: .semibold))
            Text("Cirrondly Desk will keep polling locally in the background.")
                .font(Typography.body(14))
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}