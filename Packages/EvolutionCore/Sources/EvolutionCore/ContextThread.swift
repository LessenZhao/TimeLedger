import Foundation

public struct ContextThread: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var source: ContextSource
    public var externalId: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var cwd: String?
    public var projectHint: String?
    public var rawPath: String?
    public var contentHash: String
    public var importedAt: Date
    public var schemaVersion: Int

    public init(
        id: String = UUID().uuidString,
        source: ContextSource,
        externalId: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        cwd: String? = nil,
        projectHint: String? = nil,
        rawPath: String? = nil,
        contentHash: String,
        importedAt: Date = Date(),
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.id = id
        self.source = source
        self.externalId = externalId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cwd = cwd
        self.projectHint = projectHint
        self.rawPath = rawPath
        self.contentHash = contentHash
        self.importedAt = importedAt
        self.schemaVersion = schemaVersion
    }
}
