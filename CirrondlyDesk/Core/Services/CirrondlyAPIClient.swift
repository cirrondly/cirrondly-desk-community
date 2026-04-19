import Foundation

struct EnrollmentResponse: Decodable {
    let agentId: String
    let workspaceId: String
    let workspaceName: String?
    let email: String
    let agentSecret: String

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case workspaceId = "workspace_id"
        case workspaceName = "workspace_name"
        case email
        case agentSecret = "agent_secret"
    }
}

struct UsageReportSession: Codable, Hashable {
    let provider: String
    let profile: String
    let model: String
    let startedAt: Date
    let endedAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let requestCount: Int
    let costUSD: Double
    let projectHint: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case profile
        case model
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case requestCount = "request_count"
        case costUSD = "cost_usd"
        case projectHint = "project_hint"
    }
}

struct UsageReportPayload: Codable {
    let agentId: String
    let periodStart: Date
    let periodEnd: Date
    let sessions: [UsageReportSession]

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case sessions
    }
}

enum CirrondlyAPIError: Error {
    case invalidResponse
    case unauthorized
}

final class CirrondlyAPIClient {
    private let baseURL = URL(string: "https://api.cirrondly.com/api/v1")!
    private let session: URLSession
    private let keychainService: KeychainService

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func enroll(token: String, email: String) async throws -> EnrollmentResponse {
        var request = URLRequest(url: baseURL.appending(path: "agents/enroll"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "organization_token": token,
            "user_email": email,
            "machine_id": MachineIDHasher.machineId(),
            "platform": "macos",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CirrondlyAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw CirrondlyAPIError.invalidResponse }
        return try JSONDecoder().decode(EnrollmentResponse.self, from: data)
    }

    func reportUsage(_ payload: UsageReportPayload, bearer: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "usage/report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.apiEncoder.encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CirrondlyAPIError.invalidResponse }
        if http.statusCode == 401 {
            throw CirrondlyAPIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else { throw CirrondlyAPIError.invalidResponse }
    }

    func disconnect(agentId: String, bearer: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "agents/\(agentId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CirrondlyAPIError.invalidResponse }
        if http.statusCode == 401 {
            throw CirrondlyAPIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) || http.statusCode == 404 else {
            throw CirrondlyAPIError.invalidResponse
        }
    }
}

private extension JSONEncoder {
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}