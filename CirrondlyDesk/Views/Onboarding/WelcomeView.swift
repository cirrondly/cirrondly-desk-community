import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Cirrondly Desk")
                .font(Typography.display(30))
            Text("Track local AI coding usage across your tools, then optionally connect a paid workspace for team reporting.")
                .font(Typography.body(14))
        }
        .padding(24)
    }
}