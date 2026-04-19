import Foundation

protocol UsageProvider: AnyObject {
    static var identifier: String { get }
    static var displayName: String { get }
    static var category: ProviderCategory { get }

    var isEnabled: Bool { get set }
    var profiles: [ProviderProfile] { get }
    var activeProfile: ProviderProfile? { get set }

    func isAvailable() async -> Bool
    func probe() async throws -> ProviderResult
    func sessions(since: Date) async throws -> [RawSession]
}

extension UsageProvider {
    var identifier: String { Self.identifier }
    var displayName: String { Self.displayName }
    var category: ProviderCategory { Self.category }

    func sessions(since: Date) async throws -> [RawSession] { [] }
}