import Foundation

public enum ChatConversationRole: String, Codable, Sendable, Hashable {
    case user
    case assistant
    case system
    case tool
}

public struct ChatConversationMessage: Codable, Sendable, Hashable {
    public var id: String
    public var role: ChatConversationRole
    public var createdAt: String
    public var content: String

    public init(id: String, role: ChatConversationRole, createdAt: String, content: String) {
        self.id = id
        self.role = role
        self.createdAt = createdAt
        self.content = content
    }
}

public struct ChatConversationArchiveFile: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var conversationId: String
    public var title: String
    public var sourceURL: String
    public var createdAt: String
    public var updatedAt: String
    public var messages: [ChatConversationMessage]

    public init(
        schemaVersion: Int,
        conversationId: String,
        title: String,
        sourceURL: String,
        createdAt: String,
        updatedAt: String,
        messages: [ChatConversationMessage]
    ) {
        self.schemaVersion = schemaVersion
        self.conversationId = conversationId
        self.title = title
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

public struct ChatConversationProcessedRevision: Codable, Sendable, Hashable {
    public var conversationId: String
    public var messageId: String
    public var contentHash: String
    public var taskId: String

    public init(conversationId: String, messageId: String, contentHash: String, taskId: String) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.contentHash = contentHash
        self.taskId = taskId
    }
}

public enum ChatConversationProcessingStatus: String, Codable, Sendable, Hashable {
    case pending
    case partiallyProcessed
    case processed
    case needsReexport
}

public enum ChatConversationArchiveIssue: String, Codable, Sendable, Hashable {
    case missingStructuredData
    case invalidStructuredData
    case mismatchedConversationIdentity
}

public struct ChatConversationArchiveSummary: Sendable, Hashable {
    public var conversationId: String
    public var title: String
    public var sourceURL: String?
    public var createdAt: String
    public var updatedAt: String
    public var messages: [ChatConversationMessage]
    public var status: ChatConversationProcessingStatus
    public var processedMessageCount: Int
    public var pendingMessageCount: Int
    public var pendingMessageIDs: [String]
    public var issue: ChatConversationArchiveIssue?

    public init(
        conversationId: String,
        title: String,
        sourceURL: String?,
        createdAt: String,
        updatedAt: String,
        messages: [ChatConversationMessage],
        status: ChatConversationProcessingStatus,
        processedMessageCount: Int,
        pendingMessageCount: Int,
        pendingMessageIDs: [String],
        issue: ChatConversationArchiveIssue?
    ) {
        self.conversationId = conversationId
        self.title = title
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.status = status
        self.processedMessageCount = processedMessageCount
        self.pendingMessageCount = pendingMessageCount
        self.pendingMessageIDs = pendingMessageIDs
        self.issue = issue
    }
}

public struct ChatConversationMessageReference: Codable, Sendable, Hashable {
    public var conversationId: String
    public var messageId: String

    public init(conversationId: String, messageId: String) {
        self.conversationId = conversationId
        self.messageId = messageId
    }
}

public struct ChatConversationTopic: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var isUserLocked: Bool

    public init(id: String, name: String, isUserLocked: Bool = false) {
        self.id = id
        self.name = name
        self.isUserLocked = isUserLocked
    }
}

public struct ChatConversationSegment: Codable, Sendable, Hashable {
    public var id: String
    public var conversationId: String
    public var topicId: String
    public var title: String
    public var summary: String
    public var sourceMessages: [ChatConversationMessageReference]
    public var isUserLocked: Bool

    public init(
        id: String,
        conversationId: String,
        topicId: String,
        title: String,
        summary: String,
        sourceMessages: [ChatConversationMessageReference],
        isUserLocked: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.topicId = topicId
        self.title = title
        self.summary = summary
        self.sourceMessages = sourceMessages
        self.isUserLocked = isUserLocked
    }
}

public enum ChatStudyAssetKind: String, Codable, Sendable, Hashable, CaseIterable {
    case finishedWork
    case expressionModule
    case sourceMaterial
    case methodStrategy
    case viewpointKnowledge
}

public enum ChatStudyAssetUse: String, Codable, Sendable, Hashable, CaseIterable {
    case memorize
    case imitate
    case quote
    case practice
    case review
}

public enum ChatStudyAssetPreservation: String, Codable, Sendable, Hashable {
    case verbatim
    case distilled
}

public enum ChatStudyAssetOrigin: String, Codable, Sendable, Hashable {
    case skill
    case userSelection
    case userEdited
}

public enum ChatConversationSourceStatus: String, Sendable, Hashable {
    case current
    case changed
    case unavailable
    case legacyUnscoped
}

public struct ChatConversationSourceSpan: Codable, Sendable, Hashable {
    public var message: ChatConversationMessageReference
    public var contentHash: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var textHash: String

    public init(
        message: ChatConversationMessageReference,
        contentHash: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        textHash: String
    ) {
        self.message = message
        self.contentHash = contentHash
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
        self.textHash = textHash
    }
}

public struct ChatStudyAssetVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var textSnapshot: String
    public var textHash: String
    public var preservation: ChatStudyAssetPreservation
    public var origin: ChatStudyAssetOrigin
    public var sourceMessages: [ChatConversationMessageReference]
    public var sourceSpans: [ChatConversationSourceSpan]
    public var supersedesVersionId: String?
    public var createdAt: String

    public init(
        id: String,
        textSnapshot: String,
        textHash: String,
        preservation: ChatStudyAssetPreservation,
        origin: ChatStudyAssetOrigin,
        sourceMessages: [ChatConversationMessageReference],
        sourceSpans: [ChatConversationSourceSpan],
        supersedesVersionId: String?,
        createdAt: String
    ) {
        self.id = id
        self.textSnapshot = textSnapshot
        self.textHash = textHash
        self.preservation = preservation
        self.origin = origin
        self.sourceMessages = sourceMessages
        self.sourceSpans = sourceSpans
        self.supersedesVersionId = supersedesVersionId
        self.createdAt = createdAt
    }
}

public struct ChatStudyAsset: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var segmentId: String
    public var title: String
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var versions: [ChatStudyAssetVersion]
    public var currentVersionId: String
    public var isHighlighted: Bool
    public var note: String?
    public var isUserLocked: Bool

    public init(
        id: String,
        segmentId: String,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>,
        versions: [ChatStudyAssetVersion],
        currentVersionId: String,
        isHighlighted: Bool = false,
        note: String? = nil,
        isUserLocked: Bool = false
    ) {
        self.id = id
        self.segmentId = segmentId
        self.title = title
        self.kind = kind
        self.subtype = subtype
        self.uses = uses
        self.versions = versions
        self.currentVersionId = currentVersionId
        self.isHighlighted = isHighlighted
        self.note = note
        self.isUserLocked = isUserLocked
    }

    public var currentVersion: ChatStudyAssetVersion? {
        versions.first(where: { $0.id == currentVersionId }) ?? versions.last
    }

    private enum CodingKeys: String, CodingKey {
        case id, segmentId, title, kind, subtype, uses, versions, currentVersionId, isHighlighted, note, isUserLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        segmentId = try container.decode(String.self, forKey: .segmentId)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(ChatStudyAssetKind.self, forKey: .kind)
        subtype = try container.decode(String.self, forKey: .subtype)
        uses = Set(try container.decode([ChatStudyAssetUse].self, forKey: .uses))
        versions = try container.decode([ChatStudyAssetVersion].self, forKey: .versions)
        currentVersionId = try container.decode(String.self, forKey: .currentVersionId)
        isHighlighted = try container.decode(Bool.self, forKey: .isHighlighted)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        isUserLocked = try container.decode(Bool.self, forKey: .isUserLocked)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(subtype, forKey: .subtype)
        try container.encode(uses.map(\.rawValue).sorted().compactMap(ChatStudyAssetUse.init(rawValue:)), forKey: .uses)
        try container.encode(versions, forKey: .versions)
        try container.encode(currentVersionId, forKey: .currentVersionId)
        try container.encode(isHighlighted, forKey: .isHighlighted)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(isUserLocked, forKey: .isUserLocked)
    }
}

public enum ChatConversationReceiptStatus: String, Codable, Sendable, Hashable {
    case pending
    case accepted
    case rejected
    case noOp
}

public struct ChatConversationReceipt: Codable, Sendable, Hashable {
    public var jobId: String
    public var proposalDigest: String
    public var status: ChatConversationReceiptStatus
    public var recordedAt: String
    public var reason: String?

    public init(jobId: String, proposalDigest: String, status: ChatConversationReceiptStatus, recordedAt: String, reason: String? = nil) {
        self.jobId = jobId
        self.proposalDigest = proposalDigest
        self.status = status
        self.recordedAt = recordedAt
        self.reason = reason
    }
}

public struct ChatConversationLedgerDocument: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var topics: [ChatConversationTopic]
    public var segments: [ChatConversationSegment]
    public var assets: [ChatStudyAsset]
    public var processedRevisions: [ChatConversationProcessedRevision]
    public var receipts: [ChatConversationReceipt]
    public var updatedAt: String

    public init(
        schemaVersion: Int = 2,
        topics: [ChatConversationTopic] = [],
        segments: [ChatConversationSegment] = [],
        assets: [ChatStudyAsset] = [],
        processedRevisions: [ChatConversationProcessedRevision] = [],
        receipts: [ChatConversationReceipt] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.topics = topics
        self.segments = segments
        self.assets = assets
        self.processedRevisions = processedRevisions
        self.receipts = receipts
        self.updatedAt = updatedAt
    }

    public static let empty = ChatConversationLedgerDocument(schemaVersion: 2)
}
