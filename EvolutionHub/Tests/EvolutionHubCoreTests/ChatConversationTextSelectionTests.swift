import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class ChatConversationTextSelectionTests: XCTestCase {
    func testSelectionCapturesExactUTF16RangeAndHash() throws {
        let message = ChatConversationMessage(
            id: "assistant-1",
            role: .assistant,
            createdAt: "2026-07-27T00:00:00Z",
            content: "前文🙂需要背诵的规范表述。\n后文"
        )
        let source = message.content as NSString
        let range = source.range(of: "需要背诵的规范表述。")

        let selection = try ChatConversationTextSelection.make(
            conversationID: "conversation-1",
            message: message,
            rangeUTF16: range
        )

        XCTAssertEqual(selection.textSnapshot, "需要背诵的规范表述。")
        XCTAssertEqual(selection.span.locationUTF16, range.location)
        XCTAssertEqual(selection.span.lengthUTF16, range.length)
        XCTAssertEqual(selection.span.textHash, ContentHasher.hash(selection.textSnapshot))
    }

    func testRejectsEmptyAndOutOfBoundsRanges() {
        let message = ChatConversationMessage(
            id: "assistant-1",
            role: .assistant,
            createdAt: "2026-07-27T00:00:00Z",
            content: "正文"
        )
        XCTAssertThrowsError(
            try ChatConversationTextSelection.make(
                conversationID: "c",
                message: message,
                rangeUTF16: NSRange(location: 0, length: 0)
            )
        )
        XCTAssertThrowsError(
            try ChatConversationTextSelection.make(
                conversationID: "c",
                message: message,
                rangeUTF16: NSRange(location: 0, length: 99)
            )
        )
    }
}
