import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Cirrondly Desk Community")
                .font(Typography.display(30))
            Text("Track local AI coding usage across your tools with no account, no telemetry, and no cloud sync.")
                .font(Typography.body(14))
        }
        .padding(24)
    }
}