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
    public var sourceMessages: [ChatConversationMessageReference]
    public var isUserLocked: Bool

    public init(id: String, conversationId: String, topicId: String, sourceMessages: [ChatConversationMessageReference], isUserLocked: Bool = false) {
        self.id = id
        self.conversationId = conversationId
        self.topicId = topicId
        self.sourceMessages = sourceMessages
        self.isUserLocked = isUserLocked
    }
}

public struct ChatConversationFinding: Codable, Sendable, Hashable {
    public var id: String
    public var topicId: String
    public var body: String
    public var sourceMessages: [ChatConversationMessageReference]

    public init(id: String, topicId: String, body: String, sourceMessages: [ChatConversationMessageReference]) {
        self.id = id
        self.topicId = topicId
        self.body = body
        self.sourceMessages = sourceMessages
    }
}

public struct ChatConversationMark: Codable, Sendable, Hashable {
    public var findingId: String
    public var isHighlighted: Bool
    public var note: String?

    public init(findingId: String, isHighlighted: Bool = false, note: String? = nil) {
        self.findingId = findingId
        self.isHighlighted = isHighlighted
        self.note = note
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
    public var findings: [ChatConversationFinding]
    public var processedRevisions: [ChatConversationProcessedRevision]
    public var marks: [ChatConversationMark]
    public var receipts: [ChatConversationReceipt]
    public var updatedAt: String

    public init(
        schemaVersion: Int = 1,
        topics: [ChatConversationTopic] = [],
        segments: [ChatConversationSegment] = [],
        findings: [ChatConversationFinding] = [],
        processedRevisions: [ChatConversationProcessedRevision] = [],
        marks: [ChatConversationMark] = [],
        receipts: [ChatConversationReceipt] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.topics = topics
        self.segments = segments
        self.findings = findings
        self.processedRevisions = processedRevisions
        self.marks = marks
        self.receipts = receipts
        self.updatedAt = updatedAt
    }

    public static let empty = ChatConversationLedgerDocument()
}
