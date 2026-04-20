import Foundation

struct ProviderProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var serviceIdentifier: String?
    var metadata: [String: String]

    init(id: UUID = UUID(), name: String, serviceIdentifier: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        self.metadata = metadata
    }

    var stableIdentifier: String {
        if let serviceIdentifier, !serviceIdentifier.isEmpty {
            return serviceIdentifier
        }
        return name.lowercased()
    }

    var lastUsedAt: Date? {
        guard let rawValue = metadata["lastUsed"] else { return nil }
        return TimeHelpers.parseISODate(rawValue)
    }

    var planName: String? {
        metadata["plan"]
    }

    func matches(_ other: ProviderProfile?) -> Bool {
        guard let other else { return false }
        return stableIdentifier == other.stableIdentifier
    }
}