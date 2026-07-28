import Foundation
import XCTest
@testable import EvolutionCore

final class ChatStudyAssetMaterializerTests: XCTestCase {
    func testVerbatimAssetUsesTaskBlocksInsteadOfModelDraftText() throws {
        let task = makeTask(
            assistantContent: "申论范文\n第一段。\n第二段。\n"
        )
        let assistant = try XCTUnwrap(task.inputMessages.first { $0.role == .assistant })
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "扩大内需范文",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize, .imitate],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: assistant.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )

        let version = try ChatStudyAssetMaterializer().materialize(
            candidate,
            task: task,
            createdAt: "2026-07-27T00:00:00Z"
        )

        XCTAssertEqual(version.textSnapshot, assistant.content)
        XCTAssertEqual(version.textHash, ContentHasher.hash(assistant.content))
        XCTAssertFalse(version.sourceSpans.isEmpty)
    }

    func testVerbatimListMarkdownKeepsExactNewlinesAndMarkers() throws {
        let content = """
        # 三、每天的标准流程

        建议把每日训练控制在90—120分钟。

        ## 版本一：普通题目

        - 5分钟：审题和列框架
        - 30—40分钟：限时作答
        - 15分钟：自评和AI评分
        - 20分钟：定向修改
        - 10分钟：脱稿复现
        - 5分钟：记录唯一规则

        ## 版本二：大作文

        - 10分钟：审题立意和搭框架
        - 50—60分钟：限时写作
        """
        let task = makeTask(assistantContent: content)
        let assistant = try XCTUnwrap(task.inputMessages.first { $0.role == .assistant })
        let candidate = ChatConversationProposalAsset(
            id: "asset-list-1",
            segmentId: "segment-1",
            title: "每天标准流程",
            kind: .methodStrategy,
            subtype: "训练流程",
            uses: [.practice, .review],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: assistant.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )

        let version = try ChatStudyAssetMaterializer().materialize(
            candidate,
            task: task,
            createdAt: "2026-07-28T00:00:00Z"
        )

        XCTAssertEqual(version.textSnapshot, content)
        XCTAssertTrue(version.textSnapshot.contains("- 5分钟：审题和列框架\n- 30—40分钟：限时作答"))
        XCTAssertFalse(version.textSnapshot.contains("列框架30—40分钟"))
    }

    func testRejectsVerbatimWithDraftText() {
        let task = makeTask(assistantContent: "正文\n")
        let assistant = task.inputMessages.first { $0.role == .assistant }!
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: "模型抄写",
            sourceBlockIDs: assistant.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        XCTAssertThrowsError(try ChatStudyAssetMaterializer().materialize(candidate, task: task, createdAt: "t"))
    }

    func testRejectsMissingBlocks() {
        let task = makeTask(assistantContent: "正文\n")
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: ["missing"],
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        XCTAssertThrowsError(try ChatStudyAssetMaterializer().materialize(candidate, task: task, createdAt: "t"))
    }

    func testRejectsUserMessageBlocksForVerbatim() {
        let task = makeTask(assistantContent: "正文\n")
        let user = task.inputMessages.first { $0.role == .user }!
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: user.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        XCTAssertThrowsError(try ChatStudyAssetMaterializer().materialize(candidate, task: task, createdAt: "t"))
    }

    func testRejectsNonContiguousBlocks() {
        let task = makeTask(assistantContent: "A\nB\nC\n")
        let assistant = task.inputMessages.first { $0.role == .assistant }!
        let ids = assistant.sourceBlocks.map(\.id)
        guard ids.count >= 3 else {
            XCTFail("expected multiple blocks")
            return
        }
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: [ids[0], ids[2]],
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        XCTAssertThrowsError(try ChatStudyAssetMaterializer().materialize(candidate, task: task, createdAt: "t"))
    }

    func testRejectsEmptyDistilledText() {
        let task = makeTask(assistantContent: "正文\n")
        let assistant = task.inputMessages.first { $0.role == .assistant }!
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .methodStrategy,
            subtype: "策略",
            uses: [.practice],
            preservation: .distilled,
            draftText: "",
            sourceBlockIDs: assistant.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: nil,
            origin: .skill
        )
        XCTAssertThrowsError(try ChatStudyAssetMaterializer().materialize(candidate, task: task, createdAt: "t"))
    }

    func testRejectsReplaceOnLockedAsset() {
        let task = makeTask(assistantContent: "正文\n")
        let assistant = task.inputMessages.first { $0.role == .assistant }!
        let existingVersion = ChatStudyAssetVersion(
            id: "asset-locked-v1",
            textSnapshot: "old",
            textHash: ContentHasher.hash("old"),
            preservation: .distilled,
            origin: .userSelection,
            sourceMessages: [assistant.reference],
            sourceSpans: [],
            supersedesVersionId: nil,
            createdAt: "t"
        )
        let existing = ChatStudyAsset(
            id: "asset-locked",
            segmentId: "segment-1",
            title: "locked",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            versions: [existingVersion],
            currentVersionId: existingVersion.id,
            isUserLocked: true
        )
        let candidate = ChatConversationProposalAsset(
            id: "asset-2",
            segmentId: "segment-1",
            title: "new",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: assistant.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: "asset-locked",
            origin: .skill
        )
        XCTAssertThrowsError(
            try ChatStudyAssetMaterializer().materialize(
                candidate,
                task: task,
                createdAt: "t",
                existingAsset: existing
            )
        ) { error in
            XCTAssertEqual(error as? ChatConversationLedgerError, .lockedAsset("asset-locked"))
        }
    }

    func testReplaceAppendsVersionIdentity() throws {
        let task = makeTask(assistantContent: "新正文\n")
        let assistant = try XCTUnwrap(task.inputMessages.first { $0.role == .assistant })
        let existingVersion = ChatStudyAssetVersion(
            id: "asset-1-v1",
            textSnapshot: "old",
            textHash: ContentHasher.hash("old"),
            preservation: .verbatim,
            origin: .skill,
            sourceMessages: [assistant.reference],
            sourceSpans: [],
            supersedesVersionId: nil,
            createdAt: "old"
        )
        let existing = ChatStudyAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            versions: [existingVersion],
            currentVersionId: existingVersion.id
        )
        let candidate = ChatConversationProposalAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "t",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize],
            preservation: .verbatim,
            draftText: nil,
            sourceBlockIDs: assistant.sourceBlocks.map(\.id),
            sourceSpans: [],
            replacesAssetID: "asset-1",
            origin: .skill
        )
        let version = try ChatStudyAssetMaterializer().materialize(
            candidate,
            task: task,
            createdAt: "new",
            existingAsset: existing
        )
        XCTAssertEqual(version.id, "asset-1-v2")
        XCTAssertEqual(version.supersedesVersionId, "asset-1-v1")
        XCTAssertEqual(version.textSnapshot, assistant.content)
    }
}

private func makeTask(assistantContent: String) -> ChatConversationProcessingTask {
    let user = ChatConversationMessage(
        id: "user-1",
        role: .user,
        createdAt: "2026-07-27T00:00:00Z",
        content: "请写范文"
    )
    let assistant = ChatConversationMessage(
        id: "assistant-1",
        role: .assistant,
        createdAt: "2026-07-27T00:01:00Z",
        content: assistantContent
    )
    let builder = ChatConversationSourceBlockBuilder()
    let messages = [
        ChatConversationTaskMessage(
            conversationId: "conversation-1",
            message: user,
            contextOnly: false,
            sourceBlocks: builder.blocks(conversationId: "conversation-1", message: user)
        ),
        ChatConversationTaskMessage(
            conversationId: "conversation-1",
            message: assistant,
            contextOnly: false,
            sourceBlocks: builder.blocks(conversationId: "conversation-1", message: assistant)
        ),
    ]
    return ChatConversationProcessingTask(
        schemaVersion: 2,
        jobId: "job-1",
        createdAt: "2026-07-27T00:00:00Z",
        selectedConversationIDs: ["conversation-1"],
        inputMessages: messages,
        existingTopics: [],
        existingAssets: [],
        sourceDigest: "source",
        baseLedgerDigest: "ledger"
    )
}
