import SwiftUI

struct TimeToResetBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.mono(10))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.cirrondlyBlueLight.opacity(0.35), in: Capsule())
            .foregroundStyle(Color.cirrondlyBlueDark)
    }
}