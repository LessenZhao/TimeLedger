import EvolutionCore
@testable import EvolutionHubCore
import XCTest

final class ChatConversationEvidencePresentationTests: XCTestCase {
    func testSourceMessageCanonicalMarkdownRemovesOuterWhitespaceBeforeHashing() {
        let message = ChatConversationMessage(
            id: "assistant-1",
            role: .assistant,
            createdAt: "2026-07-02T00:00:00Z",
            content: "\n\n  **重点内容**  \n"
        )
        let sourceMessage = ChatConversationSourceMessage(
            reference: .init(conversationId: "conversation-1", messageId: "assistant-1"),
            message: message
        )

        XCTAssertEqual(sourceMessage.canonicalMarkdown, "**重点内容**")
        XCTAssertEqual(
            ContentHasher.hash(sourceMessage.canonicalMarkdown),
            ContentHasher.hash("**重点内容**")
        )
        XCTAssertNotEqual(
            ContentHasher.hash(sourceMessage.canonicalMarkdown),
            ContentHasher.hash(message.content)
        )
    }

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
                turnCount: 2,
                attachmentMessageCount: 0
            )
        )
        XCTAssertEqual(presentation.turns(for: references).map(\.messages.count), [3, 2])
    }

    func testSummarizesAttachmentReferencesWithoutReadingAttachmentBodies() {
        let conversation = summary(
            id: "conversation-1",
            title: "c",
            messages: [
                message(
                    id: "assistant-1",
                    role: .assistant,
                    content: """
                    已整理完成。
                    [下载Word版](sandbox:/mnt/data/hunan-selection.docx)
                    """
                ),
                message(id: "assistant-2", role: .assistant, content: "普通会话正文"),
            ]
        )
        let presentation = ChatConversationEvidencePresentation(conversations: [conversation])
        let references = conversation.messages.map {
            ChatConversationMessageReference(conversationId: conversation.conversationId, messageId: $0.id)
        }

        XCTAssertEqual(presentation.summary(for: references).attachmentMessageCount, 1)
    }

    func testBuildsCandidateAndFormalAssetSourceContexts() throws {
        let user = ChatConversationMessageReference(conversationId: "conversation-1", messageId: "user-1")
        let assistant = ChatConversationMessageReference(conversationId: "conversation-1", messageId: "assistant-1")
        let candidateAsset = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "范文",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: ["b1"],
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        let candidate = ChatConversationProposal(
            jobId: "job-1",
            sourceDigest: "source",
            baseLedgerDigest: "ledger",
            segments: [
                ChatConversationProposalSegment(
                    id: "segment-1",
                    title: "完整范文",
                    summary: "生成并修改完整范文",
                    topicTarget: .new(id: "topic-1", name: "写作训练"),
                    sourceMessages: [user, assistant]
                )
            ],
            assets: [candidateAsset],
            ignoredMessages: []
        )

        XCTAssertEqual(
            ChatConversationEvidencePresentation.sourceContext(for: candidateAsset, in: candidate),
            ChatConversationAssetSourceContext(
                references: [user, assistant],
                destination: .candidate(jobID: "job-1", segmentID: "segment-1")
            )
        )

        let formalVersion = ChatStudyAssetVersion(
            id: "asset-1-v1",
            textSnapshot: "正文",
            textHash: ContentHasher.hash("正文"),
            preservation: .verbatim,
            origin: .skill,
            sourceMessages: [assistant],
            sourceSpans: [],
            supersedesVersionId: nil,
            createdAt: "2026-07-27T00:00:00Z"
        )
        let formalAsset = ChatStudyAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "范文",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            versions: [formalVersion],
            currentVersionId: formalVersion.id,
            isHighlighted: false
        )

        XCTAssertEqual(
            ChatConversationEvidencePresentation.sourceContext(for: formalAsset),
            ChatConversationAssetSourceContext(
                references: [assistant],
                destination: .formal(segmentID: "segment-1")
            )
        )
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
