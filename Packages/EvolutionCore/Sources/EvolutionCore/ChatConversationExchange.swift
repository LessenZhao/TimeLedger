import Foundation

public struct ChatConversationTaskSourceBlock: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var text: String
    public var textHash: String

    public init(
        id: String,
        locationUTF16: Int,
        lengthUTF16: Int,
        text: String,
        textHash: String
    ) {
        self.id = id
        self.locationUTF16 = locationUTF16
        self.lengthUTF16 = lengthUTF16
        self.text = text
        self.textHash = textHash
    }
}

public struct ChatConversationTaskMessage: Codable, Sendable, Hashable {
    public var conversationId: String
    public var messageId: String
    public var role: ChatConversationRole
    public var createdAt: String
    public var content: String
    public var contentHash: String
    public var contextOnly: Bool
    public var sourceBlocks: [ChatConversationTaskSourceBlock]

    public init(
        conversationId: String,
        message: ChatConversationMessage,
        contextOnly: Bool,
        sourceBlocks: [ChatConversationTaskSourceBlock]? = nil
    ) {
        self.conversationId = conversationId
        self.messageId = message.id
        self.role = message.role
        self.createdAt = message.createdAt
        self.content = message.content
        self.contentHash = ContentHasher.hash(message.content)
        self.contextOnly = contextOnly
        self.sourceBlocks = sourceBlocks ?? ChatConversationSourceBlockBuilder().blocks(
            conversationId: conversationId,
            message: message
        )
    }

    public init(
        conversationId: String,
        messageId: String,
        role: ChatConversationRole,
        createdAt: String,
        content: String,
        contentHash: String,
        contextOnly: Bool,
        sourceBlocks: [ChatConversationTaskSourceBlock]
    ) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.role = role
        self.createdAt = createdAt
        self.content = content
        self.contentHash = contentHash
        self.contextOnly = contextOnly
        self.sourceBlocks = sourceBlocks
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

public struct ChatConversationTaskAsset: Codable, Sendable, Hashable {
    public var id: String
    public var segmentId: String
    public var title: String
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var currentText: String
    public var isUserLocked: Bool

    public init(
        id: String,
        segmentId: String,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>,
        currentText: String,
        isUserLocked: Bool
    ) {
        self.id = id
        self.segmentId = segmentId
        self.title = title
        self.kind = kind
        self.subtype = subtype
        self.uses = uses
        self.currentText = currentText
        self.isUserLocked = isUserLocked
    }

    private enum CodingKeys: String, CodingKey {
        case id, segmentId, title, kind, subtype, uses, currentText, isUserLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        segmentId = try container.decode(String.self, forKey: .segmentId)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(ChatStudyAssetKind.self, forKey: .kind)
        subtype = try container.decode(String.self, forKey: .subtype)
        uses = Set(try container.decode([ChatStudyAssetUse].self, forKey: .uses))
        currentText = try container.decode(String.self, forKey: .currentText)
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
        try container.encode(currentText, forKey: .currentText)
        try container.encode(isUserLocked, forKey: .isUserLocked)
    }
}

public struct ChatConversationProcessingTask: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var jobId: String
    public var createdAt: String
    public var selectedConversationIDs: [String]
    public var inputMessages: [ChatConversationTaskMessage]
    public var existingTopics: [ChatConversationTaskTopic]
    public var existingAssets: [ChatConversationTaskAsset]
    public var sourceDigest: String
    public var baseLedgerDigest: String

    public init(
        schemaVersion: Int = 2,
        jobId: String,
        createdAt: String,
        selectedConversationIDs: [String],
        inputMessages: [ChatConversationTaskMessage],
        existingTopics: [ChatConversationTaskTopic],
        existingAssets: [ChatConversationTaskAsset],
        sourceDigest: String,
        baseLedgerDigest: String
    ) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.createdAt = createdAt
        self.selectedConversationIDs = selectedConversationIDs
        self.inputMessages = inputMessages
        self.existingTopics = existingTopics
        self.existingAssets = existingAssets
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

public struct ChatConversationProposalSegment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var topicTarget: ChatConversationTopicTarget
    public var sourceMessages: [ChatConversationMessageReference]

    public init(
        id: String,
        title: String,
        summary: String,
        topicTarget: ChatConversationTopicTarget,
        sourceMessages: [ChatConversationMessageReference]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.topicTarget = topicTarget
        self.sourceMessages = sourceMessages
    }
}

public struct ChatConversationProposalAsset: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var segmentId: String
    public var title: String
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var preservation: ChatStudyAssetPreservation
    public var draftText: String?
    public var sourceBlockIDs: [String]
    public var sourceSpans: [ChatConversationSourceSpan]
    public var replacesAssetID: String?
    public var origin: ChatStudyAssetOrigin

    public init(
        id: String,
        segmentId: String,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>,
        preservation: ChatStudyAssetPreservation,
        draftText: String?,
        sourceBlockIDs: [String],
        sourceSpans: [ChatConversationSourceSpan],
        replacesAssetID: String?,
        origin: ChatStudyAssetOrigin
    ) {
        self.id = id
        self.segmentId = segmentId
        self.title = title
        self.kind = kind
        self.subtype = subtype
        self.uses = uses
        self.preservation = preservation
        self.draftText = draftText
        self.sourceBlockIDs = sourceBlockIDs
        self.sourceSpans = sourceSpans
        self.replacesAssetID = replacesAssetID
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case id, segmentId, title, kind, subtype, uses, preservation, draftText
        case sourceBlockIDs, sourceSpans, replacesAssetID, origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        segmentId = try container.decode(String.self, forKey: .segmentId)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(ChatStudyAssetKind.self, forKey: .kind)
        subtype = try container.decode(String.self, forKey: .subtype)
        uses = Set(try container.decode([ChatStudyAssetUse].self, forKey: .uses))
        preservation = try container.decode(ChatStudyAssetPreservation.self, forKey: .preservation)
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText)
        sourceBlockIDs = try container.decode([String].self, forKey: .sourceBlockIDs)
        sourceSpans = try container.decode([ChatConversationSourceSpan].self, forKey: .sourceSpans)
        replacesAssetID = try container.decodeIfPresent(String.self, forKey: .replacesAssetID)
        origin = try container.decode(ChatStudyAssetOrigin.self, forKey: .origin)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(subtype, forKey: .subtype)
        try container.encode(uses.map(\.rawValue).sorted().compactMap(ChatStudyAssetUse.init(rawValue:)), forKey: .uses)
        try container.encode(preservation, forKey: .preservation)
        try container.encodeIfPresent(draftText, forKey: .draftText)
        try container.encode(sourceBlockIDs, forKey: .sourceBlockIDs)
        try container.encode(sourceSpans, forKey: .sourceSpans)
        try container.encodeIfPresent(replacesAssetID, forKey: .replacesAssetID)
        try container.encode(origin, forKey: .origin)
    }
}

public struct ChatConversationDuplicateAssetMatch: Codable, Sendable, Hashable {
    public var existingAssetId: String
    public var sourceBlockIDs: [String]

    public init(existingAssetId: String, sourceBlockIDs: [String]) {
        self.existingAssetId = existingAssetId
        self.sourceBlockIDs = sourceBlockIDs
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
    public var assets: [ChatConversationProposalAsset]
    public var duplicateMatches: [ChatConversationDuplicateAssetMatch]
    public var ignoredMessages: [ChatConversationIgnoredMessage]

    public init(
        jobId: String,
        sourceDigest: String,
        baseLedgerDigest: String,
        segments: [ChatConversationProposalSegment],
        assets: [ChatConversationProposalAsset],
        duplicateMatches: [ChatConversationDuplicateAssetMatch] = [],
        ignoredMessages: [ChatConversationIgnoredMessage]
    ) {
        self.jobId = jobId
        self.sourceDigest = sourceDigest
        self.baseLedgerDigest = baseLedgerDigest
        self.segments = segments
        self.assets = assets
        self.duplicateMatches = duplicateMatches
        self.ignoredMessages = ignoredMessages
    }
}
