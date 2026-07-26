import Foundation

public struct ChatConversationTaskMessage: Codable, Sendable, Hashable {
    public var conversationId: String
    public var messageId: String
    public var role: ChatConversationRole
    public var createdAt: String
    public var content: String
    public var contentHash: String
    public var contextOnly: Bool

    public init(conversationId: String, message: ChatConversationMessage, contextOnly: Bool) {
        self.conversationId = conversationId
        self.messageId = message.id
        self.role = message.role
        self.createdAt = message.createdAt
        self.content = message.content
        self.contentHash = ContentHasher.hash(message.content)
        self.contextOnly = contextOnly
    }

    public var reference: ChatConversationMessageReference {
        ChatConversationMessageReference(conversationId: conversationId, messageId: messageId)
    }
}

public struct ChatConversationTaskTopic: Codable, Sendable, Hashable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ChatConversationTaskFinding: Codable, Sendable, Hashable {
    public var id: String
    public var topicId: String
    public var body: String

    public init(id: String, topicId: String, body: String) {
        self.id = id
        self.topicId = topicId
        self.body = body
    }
}

public struct ChatConversationProcessingTask: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var jobId: String
    public var createdAt: String
    public var selectedConversationIDs: [String]
    public var inputMessages: [ChatConversationTaskMessage]
    public var existingTopics: [ChatConversationTaskTopic]
    public var existingFindings: [ChatConversationTaskFinding]
    public var sourceDigest: String
    public var baseLedgerDigest: String

    public init(schemaVersion: Int = 1, jobId: String, createdAt: String, selectedConversationIDs: [String], inputMessages: [ChatConversationTaskMessage], existingTopics: [ChatConversationTaskTopic], existingFindings: [ChatConversationTaskFinding], sourceDigest: String, baseLedgerDigest: String) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.createdAt = createdAt
        self.selectedConversationIDs = selectedConversationIDs
        self.inputMessages = inputMessages
        self.existingTopics = existingTopics
        self.existingFindings = existingFindings
        self.sourceDigest = sourceDigest
        self.baseLedgerDigest = baseLedgerDigest
    }
}

public enum ChatConversationTopicTarget: Sendable, Hashable {
    case existing(id: String)
    case new(id: String, name: String)
}

extension ChatConversationTopicTarget: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id, name }
    private enum Kind: String, Codable { case existing, new }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let id = try container.decode(String.self, forKey: .id)
        switch kind {
        case .existing:
            self = .existing(id: id)
        case .new:
            self = .new(id: id, name: try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .existing(let id):
            try container.encode(Kind.existing, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .new(let id, let name):
            try container.encode(Kind.new, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
        }
    }
}

public struct ChatConversationProposalSegment: Codable, Sendable, Hashable {
    public var id: String
    public var topicTarget: ChatConversationTopicTarget
    public var sourceMessages: [ChatConversationMessageReference]

    public init(id: String, topicTarget: ChatConversationTopicTarget, sourceMessages: [ChatConversationMessageReference]) {
        self.id = id
        self.topicTarget = topicTarget
        self.sourceMessages = sourceMessages
    }
}

public struct ChatConversationProposalFinding: Codable, Sendable, Hashable {
    public var id: String
    public var topicTarget: ChatConversationTopicTarget
    public var body: String
    public var sourceMessages: [ChatConversationMessageReference]

    public init(id: String, topicTarget: ChatConversationTopicTarget, body: String, sourceMessages: [ChatConversationMessageReference]) {
        self.id = id
        self.topicTarget = topicTarget
        self.body = body
        self.sourceMessages = sourceMessages
    }
}

public struct ChatConversationIgnoredMessage: Codable, Sendable, Hashable {
    public var sourceMessage: ChatConversationMessageReference
    public var reason: String

    public init(sourceMessage: ChatConversationMessageReference, reason: String) {
        self.sourceMessage = sourceMessage
        self.reason = reason
    }
}

public struct ChatConversationProposal: Codable, Sendable, Hashable {
    public var jobId: String
    public var sourceDigest: String
    public var baseLedgerDigest: String
    public var segments: [ChatConversationProposalSegment]
    public var findings: [ChatConversationProposalFinding]
    public var ignoredMessages: [ChatConversationIgnoredMessage]

    public init(jobId: String, sourceDigest: String, baseLedgerDigest: String, segments: [ChatConversationProposalSegment], findings: [ChatConversationProposalFinding], ignoredMessages: [ChatConversationIgnoredMessage]) {
        self.jobId = jobId
        self.sourceDigest = sourceDigest
        self.baseLedgerDigest = baseLedgerDigest
        self.segments = segments
        self.findings = findings
        self.ignoredMessages = ignoredMessages
    }
}
