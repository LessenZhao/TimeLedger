import Foundation
import XCTest
@testable import EvolutionCore

final class ChatConversationSourceBlockBuilderTests: XCTestCase {
    func testSourceBlocksRecomposeChineseTextWithoutNormalization() {
        let message = ChatConversationMessage(
            id: "assistant-1",
            role: .assistant,
            createdAt: "2026-07-27T00:00:00Z",
            content: "标题\r\n\r\n第一段。\n第二段末尾保留空格  \n"
        )

        let blocks = ChatConversationSourceBlockBuilder().blocks(
            conversationId: "conversation-1",
            message: message
        )

        XCTAssertEqual(blocks.map(\.text).joined(), message.content)
        XCTAssertEqual(blocks.map(\.locationUTF16), blocks.map(\.locationUTF16).sorted())
        XCTAssertTrue(blocks.allSatisfy { ContentHasher.hash($0.text) == $0.textHash })
    }

    func testSchemaV2TaskAndAssetCodableRoundTrip() throws {
        let message = ChatConversationMessage(
            id: "assistant-1",
            role: .assistant,
            createdAt: "2026-07-27T00:00:00Z",
            content: "第一行\n第二行\n"
        )
        let blocks = ChatConversationSourceBlockBuilder().blocks(
            conversationId: "conversation-1",
            message: message
        )
        let taskMessage = ChatConversationTaskMessage(
            conversationId: "conversation-1",
            message: message,
            contextOnly: false,
            sourceBlocks: blocks
        )
        let task = ChatConversationProcessingTask(
            schemaVersion: 2,
            jobId: "job-1",
            createdAt: "2026-07-27T00:00:00Z",
            selectedConversationIDs: ["conversation-1"],
            inputMessages: [taskMessage],
            existingTopics: [],
            existingAssets: [
                ChatConversationTaskAsset(
                    id: "asset-1",
                    segmentId: "segment-1",
                    title: "范文",
                    kind: .finishedWork,
                    subtype: "范文",
                    uses: [.memorize, .imitate],
                    currentText: "正文",
                    isUserLocked: false
                ),
            ],
            sourceDigest: "source",
            baseLedgerDigest: "ledger"
        )
        let version = ChatStudyAssetVersion(
            id: "asset-1-v1",
            textSnapshot: "正文",
            textHash: ContentHasher.hash("正文"),
            preservation: .verbatim,
            origin: .skill,
            sourceMessages: [
                ChatConversationMessageReference(conversationId: "conversation-1", messageId: "assistant-1"),
            ],
            sourceSpans: [
                ChatConversationSourceSpan(
                    message: ChatConversationMessageReference(conversationId: "conversation-1", messageId: "assistant-1"),
                    contentHash: ContentHasher.hash(message.content),
                    locationUTF16: 0,
                    lengthUTF16: (message.content as NSString).length,
                    textHash: ContentHasher.hash(message.content)
                ),
            ],
            supersedesVersionId: nil,
            createdAt: "2026-07-27T00:00:00Z"
        )
        let asset = ChatStudyAsset(
            id: "asset-1",
            segmentId: "segment-1",
            title: "范文",
            kind: .finishedWork,
            subtype: "范文",
            uses: [.memorize, .imitate],
            versions: [version],
            currentVersionId: version.id,
            isHighlighted: false,
            note: nil,
            isUserLocked: false
        )
        let document = ChatConversationLedgerDocument(
            schemaVersion: 2,
            topics: [ChatConversationTopic(id: "topic-1", name: "主题")],
            segments: [
                ChatConversationSegment(
                    id: "segment-1",
                    conversationId: "conversation-1",
                    topicId: "topic-1",
                    title: "片段标题",
                    summary: "片段摘要",
                    sourceMessages: [
                        ChatConversationMessageReference(conversationId: "conversation-1", messageId: "assistant-1"),
                    ]
                ),
            ],
            assets: [asset],
            processedRevisions: [],
            receipts: [],
            updatedAt: "2026-07-27T00:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        let decodedTask = try decoder.decode(
            ChatConversationProcessingTask.self,
            from: try encoder.encode(task)
        )
        XCTAssertEqual(decodedTask.inputMessages.first?.sourceBlocks.map(\.id), blocks.map(\.id))
        XCTAssertEqual(decodedTask.existingAssets.first?.uses, [.memorize, .imitate])

        let decodedDocument = try decoder.decode(
            ChatConversationLedgerDocument.self,
            from: try encoder.encode(document)
        )
        XCTAssertEqual(decodedDocument.schemaVersion, 2)
        XCTAssertEqual(decodedDocument.assets.first?.versions.map(\.id), [version.id])
        XCTAssertEqual(decodedDocument.assets.first?.uses, [.memorize, .imitate])
    }

    func testEmptyMessageProducesNoBlocks() {
        let message = ChatConversationMessage(
            id: "empty",
            role: .assistant,
            createdAt: "2026-07-27T00:00:00Z",
            content: ""
        )
        XCTAssertTrue(
            ChatConversationSourceBlockBuilder().blocks(conversationId: "c", message: message).isEmpty
        )
    }
}
