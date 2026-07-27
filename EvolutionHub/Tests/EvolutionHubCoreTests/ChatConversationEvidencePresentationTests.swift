import EvolutionCore
@testable import EvolutionHubCore
import XCTest

final class ChatConversationEvidencePresentationTests: XCTestCase {
    func testSummarizesRawMessagesAndGroupsThemIntoReadableTurns() {
        let conversation = summary(
            id: "conversation-1",
            title: "Evidence conversation",
            messages: [
                message(id: "user-1", role: .user, content: "First question"),
                message(id: "assistant-1", role: .assistant, content: "First answer"),
                message(id: "assistant-2", role: .assistant, content: "Follow-up answer"),
                message(id: "user-2", role: .user, content: "Second question"),
                message(id: "assistant-3", role: .assistant, content: "Second answer"),
            ]
        )
        let presentation = ChatConversationEvidencePresentation(conversations: [conversation])
        let references = conversation.messages.map {
            ChatConversationMessageReference(conversationId: conversation.conversationId, messageId: $0.id)
        }

        XCTAssertEqual(
            presentation.summary(for: references),
            ChatConversationSourceSummary(
                messageCount: 5,
                userMessageCount: 2,
                assistantMessageCount: 3,
                unavailableMessageCount: 0,
                turnCount: 2
            )
        )
        XCTAssertEqual(presentation.turns(for: references).map(\.messages.count), [3, 2])
    }

    func testDerivesAssetSegmentFromSegmentId() {
        let asset = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-2",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: ["b"],
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        let segments = [
            ChatConversationProposalSegment(
                id: "segment-1",
                title: "a",
                summary: "a",
                topicTarget: .new(id: "t1", name: "T"),
                sourceMessages: []
            ),
            ChatConversationProposalSegment(
                id: "segment-2",
                title: "b",
                summary: "b",
                topicTarget: .new(id: "t1", name: "T"),
                sourceMessages: []
            ),
        ]
        XCTAssertEqual(
            ChatConversationEvidencePresentation.segmentIDs(for: asset, in: segments),
            ["segment-2"]
        )
    }

    func testSourceStatusForCurrentChangedUnavailableAndLegacy() {
        let content = "需要背诵的规范表述。"
        let conversation = summary(
            id: "conversation-1",
            title: "c",
            messages: [message(id: "assistant-1", role: .assistant, content: content)]
        )
        let presentation = ChatConversationEvidencePresentation(conversations: [conversation])
        let reference = ChatConversationMessageReference(conversationId: "conversation-1", messageId: "assistant-1")
        let contentHash = ContentHasher.hash(content)
        let textHash = ContentHasher.hash(content)
        let current = ChatStudyAssetVersion(
            id: "v1",
            textSnapshot: content,
            textHash: textHash,
            preservation: .verbatim,
            origin: .skill,
            sourceMessages: [reference],
            sourceSpans: [
                ChatConversationSourceSpan(
                    message: reference,
                    contentHash: contentHash,
                    locationUTF16: 0,
                    lengthUTF16: (content as NSString).length,
                    textHash: textHash
                )
            ],
            supersedesVersionId: nil,
            createdAt: "t"
        )
        XCTAssertEqual(presentation.sourceStatus(for: current), .current)

        let changed = ChatStudyAssetVersion(
            id: "v2",
            textSnapshot: content,
            textHash: textHash,
            preservation: .verbatim,
            origin: .skill,
            sourceMessages: [reference],
            sourceSpans: [
                ChatConversationSourceSpan(
                    message: reference,
                    contentHash: "old-hash",
                    locationUTF16: 0,
                    lengthUTF16: (content as NSString).length,
                    textHash: textHash
                )
            ],
            supersedesVersionId: nil,
            createdAt: "t"
        )
        XCTAssertEqual(presentation.sourceStatus(for: changed), .changed)

        let missingRef = ChatConversationMessageReference(conversationId: "conversation-1", messageId: "missing")
        let unavailable = ChatStudyAssetVersion(
            id: "v3",
            textSnapshot: content,
            textHash: textHash,
            preservation: .verbatim,
            origin: .skill,
            sourceMessages: [missingRef],
            sourceSpans: [
                ChatConversationSourceSpan(
                    message: missingRef,
                    contentHash: contentHash,
                    locationUTF16: 0,
                    lengthUTF16: 1,
                    textHash: textHash
                )
            ],
            supersedesVersionId: nil,
            createdAt: "t"
        )
        XCTAssertEqual(presentation.sourceStatus(for: unavailable), .unavailable)

        let legacy = ChatStudyAssetVersion(
            id: "v4",
            textSnapshot: content,
            textHash: textHash,
            preservation: .distilled,
            origin: .skill,
            sourceMessages: [reference],
            sourceSpans: [],
            supersedesVersionId: nil,
            createdAt: "t"
        )
        XCTAssertEqual(presentation.sourceStatus(for: legacy), .legacyUnscoped)
    }

    private func summary(
        id: String,
        title: String,
        messages: [ChatConversationMessage]
    ) -> ChatConversationArchiveSummary {
        ChatConversationArchiveSummary(
            conversationId: id,
            title: title,
            sourceURL: nil,
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-02T00:00:00Z",
            messages: messages,
            status: .pending,
            processedMessageCount: 0,
            pendingMessageCount: messages.count,
            pendingMessageIDs: messages.map(\.id),
            issue: nil
        )
    }

    private func message(id: String, role: ChatConversationRole, content: String) -> ChatConversationMessage {
        ChatConversationMessage(id: id, role: role, createdAt: "2026-07-02T00:00:00Z", content: content)
    }
}
