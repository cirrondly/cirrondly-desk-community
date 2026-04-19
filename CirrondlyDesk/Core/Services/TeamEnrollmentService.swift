import Foundation

@MainActor
final class TeamEnrollmentService: ObservableObject {
    enum State: Equatable {
        case notEnrolled
        case enrolling
        case enrolled(agentId: String, workspaceId: String, email: String)
        case error(String)
    }

    @Published private(set) var state: State = .notEnrolled

    private let apiClient: CirrondlyAPIClient
    private let keychainService: KeychainService

    private let defaults = UserDefaults.standard
    private let keychainServiceName = "com.cirrondly.desk"

    init(apiClient: CirrondlyAPIClient, keychainService: KeychainService) {
        self.apiClient = apiClient
        self.keychainService = keychainService
        restoreState()
    }

    var isEnrolled: Bool {
        if case .enrolled = state { return true }
        return false
    }

    var agentId: String? {
        if case .enrolled(let agentId, _, _) = state { return agentId }
        return nil
    }

    func enroll(token: String, userEmail: String) async {
        state = .enrolling
        do {
            let response = try await apiClient.enroll(token: token, email: userEmail)
            defaults.set(response.agentId, forKey: "team.agentId")
            defaults.set(response.workspaceId, forKey: "team.workspaceId")
            defaults.set(response.workspaceName, forKey: "team.workspaceName")
            defaults.set(response.email, forKey: "team.email")
            defaults.set(Date(), forKey: "team.lastEnrolledAt")
            try keychainService.save(response.agentSecret, service: keychainServiceName, account: "agent_secret")
            state = .enrolled(agentId: response.agentId, workspaceId: response.workspaceId, email: response.email)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func disconnect() async {
        let existingAgentId = defaults.string(forKey: "team.agentId")
        let secret = keychainService.read(service: keychainServiceName, account: "agent_secret")

        if let existingAgentId, let secret {
            try? await apiClient.disconnect(agentId: existingAgentId, bearer: secret)
        }

        defaults.removeObject(forKey: "team.agentId")
        defaults.removeObject(forKey: "team.workspaceId")
        defaults.removeObject(forKey: "team.workspaceName")
        defaults.removeObject(forKey: "team.email")
        defaults.removeObject(forKey: "team.lastReportedAt")
        keychainService.delete(service: keychainServiceName, account: "agent_secret")
        state = .notEnrolled
    }

    func handleUnauthorized() {
        state = .error("Cirrondly workspace authorization expired. Reconnect to resume team reporting.")
    }

    func agentSecret() -> String? {
        keychainService.read(service: keychainServiceName, account: "agent_secret")
    }

    private func restoreState() {
        guard
            let agentId = defaults.string(forKey: "team.agentId"),
            let workspaceId = defaults.string(forKey: "team.workspaceId"),
            let email = defaults.string(forKey: "team.email"),
            keychainService.read(service: keychainServiceName, account: "agent_secret") != nil
        else {
            state = .notEnrolled
            return
        }

        state = .enrolled(agentId: agentId, workspaceId: workspaceId, email: email)
    }
}