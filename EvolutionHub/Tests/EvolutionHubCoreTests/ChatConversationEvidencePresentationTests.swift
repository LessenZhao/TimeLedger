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
        XCTAssertEqual(presentation.turns(for: references).first?.messages.map(\.content), [
            "First question",
            "First answer",
            "Follow-up answer",
        ])
    }

    func testDerivesCandidateFindingSegmentsFromTheFindingEvidence() {
        let first = reference(conversation: "conversation-1", message: "message-1")
        let second = reference(conversation: "conversation-2", message: "message-2")
        let candidate = ChatConversationProposal(
            jobId: "job-evidence",
            sourceDigest: "source",
            baseLedgerDigest: "ledger",
            segments: [
                ChatConversationProposalSegment(
                    id: "segment-1",
                    topicTarget: .new(id: "topic-1", name: "Topic"),
                    sourceMessages: [first]
                ),
                ChatConversationProposalSegment(
                    id: "segment-2",
                    topicTarget: .new(id: "topic-1", name: "Topic"),
                    sourceMessages: [second]
                ),
            ],
            findings: [
                ChatConversationProposalFinding(
                    id: "finding-1",
                    topicTarget: .new(id: "topic-1", name: "Topic"),
                    body: "Cross-conversation finding",
                    sourceMessages: [first, second]
                ),
            ],
            ignoredMessages: []
        )

        XCTAssertEqual(
            ChatConversationEvidencePresentation.segmentIDs(
                for: candidate.findings[0],
                in: candidate.segments
            ),
            ["segment-1", "segment-2"]
        )
    }

    func testDerivesFormalFindingSegmentsFromTheSameEvidenceReferences() {
        let first = reference(conversation: "conversation-1", message: "message-1")
        let second = reference(conversation: "conversation-2", message: "message-2")
        let finding = ChatConversationFinding(
            id: "finding-1",
            topicId: "topic-1",
            body: "Accepted finding",
            sourceMessages: [first, second]
        )
        let segments = [
            ChatConversationSegment(
                id: "segment-1",
                conversationId: "conversation-1",
                topicId: "topic-1",
                sourceMessages: [first]
            ),
            ChatConversationSegment(
                id: "segment-2",
                conversationId: "conversation-2",
                topicId: "topic-1",
                sourceMessages: [second]
            ),
        ]

        XCTAssertEqual(
            ChatConversationEvidencePresentation.segmentIDs(for: finding, in: segments),
            ["segment-1", "segment-2"]
        )
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
            createdAt: "2026-07-27T00:00:00Z",
            updatedAt: "2026-07-27T00:00:00Z",
            messages: messages,
            status: .pending,
            processedMessageCount: 0,
            pendingMessageCount: messages.count,
            pendingMessageIDs: messages.map(\.id),
            issue: nil
        )
    }

    private func message(
        id: String,
        role: ChatConversationRole,
        content: String
    ) -> ChatConversationMessage {
        ChatConversationMessage(
            id: id,
            role: role,
            createdAt: "2026-07-27T00:00:00Z",
            content: content
        )
    }

    private func reference(conversation: String, message: String) -> ChatConversationMessageReference {
        ChatConversationMessageReference(conversationId: conversation, messageId: message)
    }
}
