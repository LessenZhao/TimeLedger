import Foundation

public enum CollectorMode: String, Codable, Sendable, Hashable {
    case incremental
    case full
    case thread
}

public struct CollectorRequest: Codable, Sendable, Hashable {
    public var source: ContextSource
    public var startAt: Date
    public var endAt: Date
    public var outputRoot: String
    public var mode: CollectorMode
    public var requestId: String
    public var schemaVersion: Int

    public init(
        source: ContextSource,
        startAt: Date,
        endAt: Date,
        outputRoot: String,
        mode: CollectorMode = .incremental,
        requestId: String = UUID().uuidString,
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.source = source
        self.startAt = startAt
        self.endAt = endAt
        self.outputRoot = outputRoot
        self.mode = mode
        self.requestId = requestId
        self.schemaVersion = schemaVersion
    }
}

public enum CollectorStatus: String, Codable, Sendable, Hashable {
    case succeeded
    case partial
    case failed
    case cancelled
    case waitingForBrowser
}

public struct CollectorResult: Codable, Sendable, Hashable {
    public var requestId: String
    public var source: ContextSource
    public var status: CollectorStatus
    public var startedAt: Date
    public var finishedAt: Date
    public var threadsFound: Int
    public var threadsChanged: Int
    public var messagesImported: Int
    public var outputPaths: [String]
    public var warnings: [String]
    public var errors: [String]
    public var schemaVersion: Int

    public init(
        requestId: String,
        source: ContextSource,
        status: CollectorStatus,
        startedAt: Date,
        finishedAt: Date,
        threadsFound: Int = 0,
        threadsChanged: Int = 0,
        messagesImported: Int = 0,
        outputPaths: [String] = [],
        warnings: [String] = [],
        errors: [String] = [],
        schemaVersion: Int = EvolutionSchema.current
    ) {
        self.requestId = requestId
        self.source = source
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.threadsFound = threadsFound
        self.threadsChanged = threadsChanged
        self.messagesImported = messagesImported
        self.outputPaths = outputPaths
        self.warnings = warnings
        self.errors = errors
        self.schemaVersion = schemaVersion
    }

    public var isBlockingFailure: Bool {
        status == .failed
    }

    /// ChatGPT waiting must not block other collectors' success presentation.
    public var isNonBlockingWait: Bool {
        status == .waitingForBrowser
    }
}
