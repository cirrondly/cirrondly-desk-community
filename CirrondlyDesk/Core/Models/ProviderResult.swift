import Foundation

enum ProviderCategory: String, Codable, CaseIterable, Hashable {
    case subscription
    case api
    case usageBased
    case free

    var title: String {
        switch self {
        case .subscription:
            return L10n.tr("provider.category.subscription")
        case .api:
            return L10n.tr("provider.category.api")
        case .usageBased:
            return L10n.tr("provider.category.usageBased")
        case .free:
            return L10n.tr("provider.category.free")
        }
    }
}

enum WindowKind: Codable, Hashable {
    case fiveHour
    case weekly
    case monthly
    case custom(String)

    var title: String {
        switch self {
        case .fiveHour:
            return L10n.tr("window.title.session")
        case .weekly:
            return L10n.tr("window.title.weekly")
        case .monthly:
            return L10n.tr("window.title.monthly")
        case .custom(let name):
            return name
        }
    }

    var reportingKey: String {
        switch self {
        case .fiveHour:
            return "session"
        case .weekly:
            return "weekly"
        case .monthly:
            return "monthly"
        case .custom(let name):
            return name.lowercased().replacingOccurrences(of: " ", with: "-")
        }
    }
}

enum UsageUnit: String, Codable, Hashable {
    case tokens
    case requests
    case credits
    case dollars

    var localizedLabel: String {
        switch self {
        case .tokens:
            return L10n.tr("unit.tokens")
        case .requests:
            return L10n.tr("unit.requests")
        case .credits:
            return L10n.tr("unit.credits")
        case .dollars:
            return "USD"
        }
    }

    var localizedChartLabel: String {
        switch self {
        case .tokens:
            return L10n.tr("unit.tokens.chart")
        case .requests:
            return L10n.tr("unit.requests.chart")
        case .credits:
            return L10n.tr("unit.credits.chart")
        case .dollars:
            return "USD"
        }
    }
}

enum ForecastStatus: String, Codable, Hashable {
    case onTrack
    case tight
    case willExceed
}

struct Forecast: Codable, Hashable {
    let projectedUsageAtReset: Double
    let projectedPercentageAtReset: Double
    let status: ForecastStatus
    let timeToDepletion: TimeInterval?
}

enum DataSource: String, Codable, Hashable {
    case local
    case api
    case mixed
}

enum ProviderWarningLevel: String, Codable, Hashable {
    case info
    case warning
    case critical
}

struct ProviderWarning: Identifiable, Codable, Hashable {
    let id: UUID
    let level: ProviderWarningLevel
    let message: String

    init(id: UUID = UUID(), level: ProviderWarningLevel, message: String) {
        self.id = id
        self.level = level
        self.message = message
    }
}

struct DailyUsage: Codable, Hashable {
    var costUSD: Double
    var tokens: Int
    var requests: Int

    static let zero = DailyUsage(costUSD: 0, tokens: 0, requests: 0)
}

struct ModelBreakdown: Identifiable, Codable, Hashable {
    var id: String { model }
    let model: String
    let tokens: Int
    let requests: Int
    let costUSD: Double
}

struct Window: Identifiable, Codable, Hashable {
    var id: String { kind.reportingKey }

    let kind: WindowKind
    let used: Double
    let limit: Double?
    let unit: UsageUnit
    let percentage: Double
    let resetAt: Date?
    let windowStart: Date?
    let forecast: Forecast?

    init(
        kind: WindowKind,
        used: Double,
        limit: Double?,
        unit: UsageUnit,
        percentage: Double,
        resetAt: Date?,
        windowStart: Date? = nil,
        forecast: Forecast? = nil
    ) {
        self.kind = kind
        self.used = used
        self.limit = limit
        self.unit = unit
        self.percentage = percentage
        self.resetAt = resetAt

        let inferredWindowStart = windowStart ?? ForecastCalculator.inferredWindowStart(kind: kind, resetAt: resetAt)
        self.windowStart = inferredWindowStart
        self.forecast = forecast ?? ForecastCalculator.forecastUsage(
            used: used,
            limit: limit,
            windowStart: inferredWindowStart,
            windowEnd: resetAt
        )
    }
}

struct ProviderResult: Identifiable, Codable, Hashable {
    var id: String { identifier + ":" + profile }

    let identifier: String
    let displayName: String
    let category: ProviderCategory
    let profile: String
    let windows: [Window]
    let today: DailyUsage
    let burnRate: BurnRate?
    let dailyHeatmap: [DailyCell]
    let models: [ModelBreakdown]
    let source: DataSource
    let freshness: Date
    let warnings: [ProviderWarning]

    var primaryWindow: Window? {
        windows.max { lhs, rhs in lhs.percentage < rhs.percentage }
    }

    var isStale: Bool {
        Date().timeIntervalSince(freshness) > 600
    }

    static func unavailable(
        identifier: String,
        displayName: String,
        category: ProviderCategory,
        profile: String = "Default",
        warning: String
    ) -> ProviderResult {
        ProviderResult(
            identifier: identifier,
            displayName: displayName,
            category: category,
            profile: profile,
            windows: [],
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .local,
            freshness: .distantPast,
            warnings: [ProviderWarning(level: .warning, message: warning)]
        )
    }
}