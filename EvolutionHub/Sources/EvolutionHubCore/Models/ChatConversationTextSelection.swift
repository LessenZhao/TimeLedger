import EvolutionCore
import Foundation

public enum ChatConversationTextSelectionError: Error, Sendable, Equatable {
    case emptyRange
    case outOfBounds
    case emptyText
    case contentHashMismatch
    case textMismatch
}

public struct ChatConversationTextSelection: Sendable, Hashable {
    public var conversationID: String
    public var message: ChatConversationMessage
    public var span: ChatConversationSourceSpan
    public var textSnapshot: String

    public init(
        conversationID: String,
        message: ChatConversationMessage,
        span: ChatConversationSourceSpan,
        textSnapshot: String
    ) {
        self.conversationID = conversationID
        self.message = message
        self.span = span
        self.textSnapshot = textSnapshot
    }

    public static func make(
        conversationID: String,
        message: ChatConversationMessage,
        rangeUTF16: NSRange,
        expectedContentHash: String? = nil
    ) throws -> ChatConversationTextSelection {
        guard rangeUTF16.length > 0 else {
            throw ChatConversationTextSelectionError.emptyRange
        }
        let source = message.content as NSString
        guard rangeUTF16.location >= 0,
              rangeUTF16.location + rangeUTF16.length <= source.length else {
            throw ChatConversationTextSelectionError.outOfBounds
        }
        let text = source.substring(with: rangeUTF16)
        guard !text.isEmpty else {
            throw ChatConversationTextSelectionError.emptyText
        }
        let contentHash = ContentHasher.hash(message.content)
        if let expectedContentHash, expectedContentHash != contentHash {
            throw ChatConversationTextSelectionError.contentHashMismatch
        }
        let textHash = ContentHasher.hash(text)
        let span = ChatConversationSourceSpan(
            message: ChatConversationMessageReference(
                conversationId: conversationID,
                messageId: message.id
            ),
            contentHash: contentHash,
            locationUTF16: rangeUTF16.location,
            lengthUTF16: rangeUTF16.length,
            textHash: textHash
        )
        return ChatConversationTextSelection(
            conversationID: conversationID,
            message: message,
            span: span,
            textSnapshot: text
        )
    }
}

public enum ChatConversationSourceDestination: Hashable {
    case candidate(jobID: String, segmentID: String)
    case formal(segmentID: String)
    case readOnly
}
