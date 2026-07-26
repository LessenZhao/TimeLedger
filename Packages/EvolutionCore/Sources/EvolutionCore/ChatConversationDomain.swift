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
        self.status = status
        self.processedMessageCount = processedMessageCount
        self.pendingMessageCount = pendingMessageCount
        self.pendingMessageIDs = pendingMessageIDs
        self.issue = issue
    }
}
