import Foundation

public struct ContextEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var source: ContextSource
    public var threadId: String
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String
    public var summary: String
    public var projectHint: String?
    public var rawReference: String?
    public var importedAt: Date
    public var schemaVersion: Int

    public init(
        id: String = UUID().uuidString,
        source: ContextSource,
        threadId: String,
        startedAt: Date,
        endedAt: Date? = nil,
        title: String,
        summary: String = "",
        projectHint: String? = nil,
        rawReference: String? = nil,
        importedAt: Date = Date(),
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.id = id
        self.source = source
        self.threadId = threadId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.summary = summary
        self.projectHint = projectHint
        self.rawReference = rawReference
        self.importedAt = importedAt
        self.schemaVersion = schemaVersion
    }
}
