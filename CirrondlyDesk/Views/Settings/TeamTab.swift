import SwiftUI

struct TeamTab: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var token = ""
    @State private var email = ""

    var body: some View {
        Form {
            switch container.teamEnrollmentService.state {
            case .notEnrolled, .error:
                Section("Enable team analytics") {
                    TextField("Workspace organization token", text: $token)
                    TextField("Work email", text: $email)
                    Button("Connect") {
                        Task { await container.teamEnrollmentService.enroll(token: token, userEmail: email) }
                    }
                    Link("How to get a token", destination: URL(string: "https://app.cirrondly.com/help")!)
                }
            case .enrolling:
                ProgressView("Connecting…")
            case .enrolled(_, let workspaceId, let email):
                Section("Connected") {
                    Text("Workspace ID: \(workspaceId)")
                    Text("Email: \(email)")
                    Text("While connected, your usage stats are sent hourly to your Cirrondly workspace. Stop at any time by disconnecting.")
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))
                    Button("Disconnect", role: .destructive) {
                        Task { await container.teamEnrollmentService.disconnect() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}