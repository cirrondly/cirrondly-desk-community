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
}