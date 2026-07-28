import EvolutionCore
import Foundation

public struct ChatConversationSourceSummary: Sendable, Hashable {
    public var messageCount: Int
    public var userMessageCount: Int
    public var assistantMessageCount: Int
    public var unavailableMessageCount: Int
    public var turnCount: Int
    public var attachmentMessageCount: Int

    public init(
        messageCount: Int,
        userMessageCount: Int,
        assistantMessageCount: Int,
        unavailableMessageCount: Int,
        turnCount: Int,
        attachmentMessageCount: Int
    ) {
        self.messageCount = messageCount
        self.userMessageCount = userMessageCount
        self.assistantMessageCount = assistantMessageCount
        self.unavailableMessageCount = unavailableMessageCount
        self.turnCount = turnCount
        self.attachmentMessageCount = attachmentMessageCount
    }
}

public struct ChatConversationAssetSourceContext: Sendable, Hashable {
    public var references: [ChatConversationMessageReference]
    public var destination: ChatConversationSourceDestination

    public init(
        references: [ChatConversationMessageReference],
        destination: ChatConversationSourceDestination
    ) {
        self.references = references
        self.destination = destination
    }
}

public struct ChatConversationSourceMessage: Identifiable, Sendable, Hashable {
    public var reference: ChatConversationMessageReference
    public var role: ChatConversationRole
    public var createdAt: String
    public var content: String

    public var id: ChatConversationMessageReference { reference }

    public init(reference: ChatConversationMessageReference, message: ChatConversationMessage) {
        self.reference = reference
        self.role = message.role
        self.createdAt = message.createdAt
        self.content = message.content
    }
}

public struct ChatConversationSourceTurn: Identifiable, Sendable, Hashable {
    public var id: String
    public var conversationId: String
    public var messages: [ChatConversationSourceMessage]

    public init(id: String, conversationId: String, messages: [ChatConversationSourceMessage]) {
        self.id = id
        self.conversationId = conversationId
        self.messages = messages
    }
}

/// Presentation-only evidence resolver. It keeps raw message identity intact,
/// but derives human-readable turns and fragment relationships for both drafts
/// and accepted ledger records.
public struct ChatConversationEvidencePresentation: Sendable {
    private var messagesByReference: [ChatConversationMessageReference: ChatConversationMessage]
    private var messageOrderByReference: [ChatConversationMessageReference: Int]
    private var titlesByConversationID: [String: String]

    public init(conversations: [ChatConversationArchiveSummary]) {
        var messages: [ChatConversationMessageReference: ChatConversationMessage] = [:]
        var order: [ChatConversationMessageReference: Int] = [:]
        var titles: [String: String] = [:]

        for conversation in conversations {
            titles[conversation.conversationId] = conversation.title
            for (index, message) in conversation.messages.enumerated() {
                let reference = ChatConversationMessageReference(
                    conversationId: conversation.conversationId,
                    messageId: message.id
                )
                messages[reference] = message
                order[reference] = index
            }
        }

        self.messagesByReference = messages
        self.messageOrderByReference = order
        self.titlesByConversationID = titles
    }

    public func sourceMessage(for reference: ChatConversationMessageReference) -> ChatConversationMessage? {
        messagesByReference[reference]
    }

    public func conversationTitle(for conversationID: String) -> String {
        titlesByConversationID[conversationID] ?? conversationID
    }

    public func summary(for references: [ChatConversationMessageReference]) -> ChatConversationSourceSummary {
        let available = references.compactMap { messagesByReference[$0] }
        let turns = turns(for: references)
        return ChatConversationSourceSummary(
            messageCount: references.count,
            userMessageCount: available.filter { $0.role == .user }.count,
            assistantMessageCount: available.filter { $0.role == .assistant }.count,
            unavailableMessageCount: references.count - available.count,
            turnCount: turns.count,
            attachmentMessageCount: available.filter {
                Self.containsAttachmentReference(in: $0.content)
            }.count
        )
    }

    public static func sourceContext(
        for asset: ChatConversationProposalAsset,
        in candidate: ChatConversationProposal
    ) -> ChatConversationAssetSourceContext? {
        guard let segment = candidate.segments.first(where: { $0.id == asset.segmentId }),
              !segment.sourceMessages.isEmpty else {
            return nil
        }
        return ChatConversationAssetSourceContext(
            references: segment.sourceMessages,
            destination: .candidate(jobID: candidate.jobId, segmentID: segment.id)
        )
    }

    public static func sourceContext(
        for asset: ChatStudyAsset
    ) -> ChatConversationAssetSourceContext? {
        guard let version = asset.currentVersion,
              !version.sourceMessages.isEmpty else {
            return nil
        }
        return ChatConversationAssetSourceContext(
            references: version.sourceMessages,
            destination: .formal(segmentID: asset.segmentId)
        )
    }

    public static func containsAttachmentReference(in content: String) -> Bool {
        let lowered = content.lowercased()
        if lowered.contains("sandbox:/mnt/data/") {
            return true
        }
        let markdownAttachmentPattern =
            #"\]\((?:file:|https?://|sandbox:)[^)\n]+\.(?:pdf|docx?|xlsx?|pptx?|zip)(?:[?#][^)\n]*)?\)"#
        return lowered.range(
            of: markdownAttachmentPattern,
            options: .regularExpression
        ) != nil
    }

    /// A turn begins with a user message and includes the visible assistant
    /// messages that follow before the next user message. A leading assistant
    /// message is kept as a readable preface instead of being discarded.
    public func turns(for references: [ChatConversationMessageReference]) -> [ChatConversationSourceTurn] {
        let distinctReferences = orderedDistinct(references)
        let conversationOrder = orderedDistinct(distinctReferences.map(\.conversationId))
        var turns: [ChatConversationSourceTurn] = []

        for conversationID in conversationOrder {
            let orderedReferences = distinctReferences
                .enumerated()
                .filter { $0.element.conversationId == conversationID }
                .sorted { lhs, rhs in
                    let lhsOrder = messageOrderByReference[lhs.element] ?? Int.max
                    let rhsOrder = messageOrderByReference[rhs.element] ?? Int.max
                    return lhsOrder == rhsOrder ? lhs.offset < rhs.offset : lhsOrder < rhsOrder
                }
                .map(\.element)

            var currentMessages: [ChatConversationSourceMessage] = []
            for reference in orderedReferences {
                guard let message = messagesByReference[reference] else { continue }
                if message.role == .user, !currentMessages.isEmpty {
                    turns.append(makeTurn(conversationID: conversationID, messages: currentMessages))
                    currentMessages = []
                }
                currentMessages.append(ChatConversationSourceMessage(reference: reference, message: message))
            }
            if !currentMessages.isEmpty {
                turns.append(makeTurn(conversationID: conversationID, messages: currentMessages))
            }
        }

        return turns
    }

    public static func segmentIDs(
        for asset: ChatConversationProposalAsset,
        in segments: [ChatConversationProposalSegment]
    ) -> [String] {
        segments.contains(where: { $0.id == asset.segmentId }) ? [asset.segmentId] : []
    }

    public static func segmentIDs(
        for asset: ChatStudyAsset,
        in segments: [ChatConversationSegment]
    ) -> [String] {
        segments.contains(where: { $0.id == asset.segmentId }) ? [asset.segmentId] : []
    }

    public func sourceStatus(
        for version: ChatStudyAssetVersion
    ) -> ChatConversationSourceStatus {
        if version.sourceSpans.isEmpty {
            if version.sourceMessages.isEmpty {
                return .unavailable
            }
            let allPresent = version.sourceMessages.allSatisfy { messagesByReference[$0] != nil }
            return allPresent ? .legacyUnscoped : .unavailable
        }
        var sawChanged = false
        for span in version.sourceSpans {
            guard let message = messagesByReference[span.message] else {
                return .unavailable
            }
            let contentHash = ContentHasher.hash(message.content)
            if contentHash != span.contentHash {
                sawChanged = true
                continue
            }
            let ns = message.content as NSString
            guard span.locationUTF16 >= 0,
                  span.lengthUTF16 > 0,
                  span.locationUTF16 + span.lengthUTF16 <= ns.length else {
                sawChanged = true
                continue
            }
            let text = ns.substring(with: NSRange(location: span.locationUTF16, length: span.lengthUTF16))
            if ContentHasher.hash(text) != span.textHash {
                sawChanged = true
            }
        }
        return sawChanged ? .changed : .current
    }

    private static func segmentIDs(
        for references: [ChatConversationMessageReference],
        segments: [(String, [ChatConversationMessageReference])]
    ) -> [String] {
        let evidence = Set(references)
        return segments.compactMap { id, sourceMessages in
            sourceMessages.contains(where: evidence.contains) ? id : nil
        }
    }

    private func makeTurn(
        conversationID: String,
        messages: [ChatConversationSourceMessage]
    ) -> ChatConversationSourceTurn {
        let firstID = messages.first?.reference.messageId ?? UUID().uuidString
        return ChatConversationSourceTurn(
            id: "\(conversationID):\(firstID)",
            conversationId: conversationID,
            messages: messages
        )
    }

    private func orderedDistinct<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
