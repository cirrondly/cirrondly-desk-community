import Foundation

enum ProviderServiceHealth: String, Codable, Hashable, Sendable {
    case checking
    case operational
    case degraded
    case outage
    case unknown

    var label: String {
        switch self {
        case .checking:
            return "Checking"
        case .operational:
            return "Operational"
        case .degraded:
            return "Degraded"
        case .outage:
            return "Outage"
        case .unknown:
            return "Unknown"
        }
    }

    var showsAlert: Bool {
        switch self {
        case .degraded, .outage:
            return true
        case .checking, .operational, .unknown:
            return false
        }
    }
}

struct ProviderServiceStatus: Hashable, Sendable {
    let serviceName: String
    let statusPageURL: URL?
    let health: ProviderServiceHealth
    let message: String
    let checkedAt: Date?

    var label: String { health.label }
    var showsAlert: Bool { health.showsAlert }
    var hasStatusPage: Bool { statusPageURL != nil }
}

@MainActor
final class ServiceStatusMonitor: ObservableObject {
    @Published private(set) var statuses: [String: ProviderServiceStatus]

    private let refreshTTL: TimeInterval = 900
    private var lastRefreshAt: Date?
    private var refreshTask: Task<Void, Never>?

    init() {
        statuses = ServiceStatusCatalog.bootstrapStatuses()
    }

    func status(for providerID: String) -> ProviderServiceStatus {
        statuses[providerID] ?? ServiceStatusCatalog.fallbackStatus(for: providerID)
    }

    func refreshIfNeeded(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            if !force { return }
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < refreshTTL {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            let serviceStatuses = await withTaskGroup(of: (String, ProviderServiceStatus).self, returning: [String: ProviderServiceStatus].self) { group in
                for descriptor in ServiceStatusCatalog.descriptors {
                    group.addTask {
                        let status = await Self.fetchStatus(for: descriptor)
                        return (descriptor.id, status)
                    }
                }

                var resolved: [String: ProviderServiceStatus] = [:]
                for await (serviceID, status) in group {
                    resolved[serviceID] = status
                }
                return resolved
            }

            var nextStatuses = self.statuses
            for descriptor in ServiceStatusCatalog.descriptors {
                let status = serviceStatuses[descriptor.id] ?? ServiceStatusCatalog.statusWithoutFetch(for: descriptor)
                for providerID in descriptor.providerIDs {
                    nextStatuses[providerID] = status
                }
            }

            self.statuses = nextStatuses
            self.lastRefreshAt = Date()
            self.refreshTask = nil
        }

        refreshTask = task
        await task.value
    }

    private static func fetchStatus(for descriptor: ServiceStatusDescriptor) async -> ProviderServiceStatus {
        guard let summaryURL = descriptor.summaryURL else {
            return ServiceStatusCatalog.statusWithoutFetch(for: descriptor)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: summaryURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                return ProviderServiceStatus(
                    serviceName: descriptor.name,
                    statusPageURL: descriptor.statusPageURL,
                    health: .unknown,
                    message: "Could not verify the public status page right now.",
                    checkedAt: Date()
                )
            }

            let payload = try JSONDecoder().decode(StatusPagePayload.self, from: data)
            return ProviderServiceStatus(
                serviceName: descriptor.name,
                statusPageURL: descriptor.statusPageURL,
                health: ProviderServiceHealth(indicator: payload.status.indicator),
                message: payload.status.description,
                checkedAt: Date()
            )
        } catch {
            return ProviderServiceStatus(
                serviceName: descriptor.name,
                statusPageURL: descriptor.statusPageURL,
                health: .unknown,
                message: "Could not verify the public status page right now.",
                checkedAt: Date()
            )
        }
    }
}

private enum ServiceStatusCatalog {
    static let descriptors: [ServiceStatusDescriptor] = [
        ServiceStatusDescriptor(
            id: "anthropic",
            name: "Anthropic",
            providerIDs: ["claude-code", "claude-subscription"],
            statusPageURL: URL(string: "https://status.anthropic.com"),
            summaryURL: URL(string: "https://status.anthropic.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "cursor",
            name: "Cursor",
            providerIDs: ["cursor"],
            statusPageURL: URL(string: "https://status.cursor.com"),
            summaryURL: URL(string: "https://status.cursor.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "openai",
            name: "OpenAI",
            providerIDs: ["codex"],
            statusPageURL: URL(string: "https://status.openai.com"),
            summaryURL: URL(string: "https://status.openai.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "github",
            name: "GitHub",
            providerIDs: ["copilot"],
            statusPageURL: URL(string: "https://www.githubstatus.com"),
            summaryURL: URL(string: "https://www.githubstatus.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "sourcegraph",
            name: "Sourcegraph",
            providerIDs: ["amp"],
            statusPageURL: URL(string: "https://status.sourcegraph.com"),
            summaryURL: URL(string: "https://status.sourcegraph.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "aws",
            name: "AWS",
            providerIDs: ["kiro"],
            statusPageURL: URL(string: "https://health.aws.amazon.com/health/status"),
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "codeium",
            name: "Codeium",
            providerIDs: ["windsurf"],
            statusPageURL: URL(string: "https://status.codeium.com"),
            summaryURL: URL(string: "https://status.codeium.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "google-cloud",
            name: "Google Cloud",
            providerIDs: ["gemini"],
            statusPageURL: URL(string: "https://status.cloud.google.com"),
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "perplexity",
            name: "Perplexity",
            providerIDs: ["perplexity"],
            statusPageURL: URL(string: "https://status.perplexity.com"),
            summaryURL: URL(string: "https://status.perplexity.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "jetbrains",
            name: "JetBrains",
            providerIDs: ["jetbrains-ai"],
            statusPageURL: URL(string: "https://status.jetbrains.com"),
            summaryURL: URL(string: "https://status.jetbrains.com/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "continue",
            name: "Continue",
            providerIDs: ["continue"],
            statusPageURL: URL(string: "https://status.continue.dev"),
            summaryURL: URL(string: "https://status.continue.dev/api/v2/status.json")
        ),
        ServiceStatusDescriptor(
            id: "antigravity",
            name: "Antigravity",
            providerIDs: ["antigravity"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "factory",
            name: "Factory",
            providerIDs: ["factory"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "kimi",
            name: "Kimi",
            providerIDs: ["kimi"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "minimax",
            name: "MiniMax",
            providerIDs: ["minimax"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "opencode-go",
            name: "OpenCode Go",
            providerIDs: ["opencode-go"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "synthetic",
            name: "Synthetic",
            providerIDs: ["synthetic"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "zai",
            name: "Z.ai",
            providerIDs: ["zai"],
            statusPageURL: nil,
            summaryURL: nil
        ),
        ServiceStatusDescriptor(
            id: "aider",
            name: "Aider",
            providerIDs: ["aider"],
            statusPageURL: nil,
            summaryURL: nil
        )
    ]

    static func bootstrapStatuses() -> [String: ProviderServiceStatus] {
        var statuses: [String: ProviderServiceStatus] = [:]
        for descriptor in descriptors {
            let status = ProviderServiceStatus(
                serviceName: descriptor.name,
                statusPageURL: descriptor.statusPageURL,
                health: descriptor.summaryURL == nil ? .unknown : .checking,
                message: descriptor.summaryURL == nil ? "No public status page is configured for this provider yet." : "Checking the provider status page.",
                checkedAt: nil
            )
            for providerID in descriptor.providerIDs {
                statuses[providerID] = status
            }
        }
        return statuses
    }

    static func fallbackStatus(for providerID: String) -> ProviderServiceStatus {
        if let descriptor = descriptors.first(where: { $0.providerIDs.contains(providerID) }) {
            return statusWithoutFetch(for: descriptor)
        }

        return ProviderServiceStatus(
            serviceName: providerID,
            statusPageURL: nil,
            health: .unknown,
            message: "No public status page is configured for this provider yet.",
            checkedAt: nil
        )
    }

    static func statusWithoutFetch(for descriptor: ServiceStatusDescriptor) -> ProviderServiceStatus {
        ProviderServiceStatus(
            serviceName: descriptor.name,
            statusPageURL: descriptor.statusPageURL,
            health: .unknown,
            message: descriptor.statusPageURL == nil
                ? "No public status page is configured for this provider yet."
                : "Open the public status page to inspect the current service health.",
            checkedAt: nil
        )
    }
}

private struct ServiceStatusDescriptor: Hashable, Sendable {
    let id: String
    let name: String
    let providerIDs: [String]
    let statusPageURL: URL?
    let summaryURL: URL?
}

private struct StatusPagePayload: Decodable {
    let status: StatusPageSummary
}

private struct StatusPageSummary: Decodable {
    let indicator: String
    let description: String
}

private extension ProviderServiceHealth {
    init(indicator: String) {
        switch indicator.lowercased() {
        case "none":
            self = .operational
        case "minor", "maintenance":
            self = .degraded
        case "major", "critical":
            self = .outage
        default:
            self = .unknown
        }
    }
}