import Foundation

public enum ContextMessageRole: String, Codable, Sendable, Hashable {
    case user
    case assistant
    case system
    case other
}

public struct ContextMessage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var threadId: String
    public var externalId: String
    public var role: ContextMessageRole
    public var createdAt: Date
    public var text: String
    public var attachmentRefs: [String]
    public var contentHash: String
    public var schemaVersion: Int

    public init(
        id: String = UUID().uuidString,
        threadId: String,
        externalId: String,
        role: ContextMessageRole,
        createdAt: Date,
        text: String,
        attachmentRefs: [String] = [],
        contentHash: String,
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.id = id
        self.threadId = threadId
        self.externalId = externalId
        self.role = role
        self.createdAt = createdAt
        self.text = text
        self.attachmentRefs = attachmentRefs
        self.contentHash = contentHash
        self.schemaVersion = schemaVersion
    }
}
