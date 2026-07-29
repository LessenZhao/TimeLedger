import Foundation
import XCTest
@testable import EvolutionHubCore

final class ObsidianMarkdownDocumentTests: XCTestCase {
    func testAcceptsVisibleCrossFormatSelectionAsOneContinuousSourceRange() throws {
        let source = "普通 **加粗** 与 [链接](https://example.com)"
        let document = try ObsidianMarkdownDocument(sections: [
            .init(id: "message-1", markdown: source)
        ])
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)

        let selection = try document.validatedSelection(
            sectionID: "message-1",
            sourceRange: range,
            quote: "普通 加粗 与 链接"
        )

        XCTAssertEqual(selection.sectionID, "message-1")
        XCTAssertEqual(selection.sourceRange, range)
        XCTAssertEqual(selection.quote, "普通 加粗 与 链接")
    }

    func testRejectsZeroLengthOutOfBoundsAndUnknownSectionSelections() throws {
        let document = try ObsidianMarkdownDocument(sections: [
            .init(id: "asset-1", markdown: "正文")
        ])

        XCTAssertThrowsError(try document.validatedSelection(
            sectionID: "asset-1",
            sourceRange: NSRange(location: 0, length: 0),
            quote: ""
        ))
        XCTAssertThrowsError(try document.validatedSelection(
            sectionID: "asset-1",
            sourceRange: NSRange(location: 1, length: 3),
            quote: "越界"
        ))
        XCTAssertThrowsError(try document.validatedSelection(
            sectionID: "missing",
            sourceRange: NSRange(location: 0, length: 1),
            quote: "正"
        ))
    }

    func testRejectsOneUTF16OffsetWhenVisibleQuoteNoLongerMatchesSource() throws {
        let source = "普通 **加粗** 与 [链接](https://example.com)"
        let document = try ObsidianMarkdownDocument(sections: [.init(id: "message-1", markdown: source)])
        let fullLength = (source as NSString).length

        XCTAssertThrowsError(try document.validatedSelection(
            sectionID: "message-1",
            sourceRange: NSRange(location: 1, length: fullLength - 1),
            quote: "普通 加粗 与 链接"
        ))
    }

    func testPreservesTheSecondRepeatedTextSourceRange() throws {
        let source = "前段 repeat，后段 repeat"
        let document = try ObsidianMarkdownDocument(sections: [.init(id: "message-1", markdown: source)])
        let secondLocation = (source as NSString).range(of: "repeat", options: [], range: NSRange(location: 0, length: (source as NSString).length)).location
        let laterRange = (source as NSString).range(of: "repeat", options: [], range: NSRange(location: secondLocation + 1, length: (source as NSString).length - secondLocation - 1))

        let selection = try document.validatedSelection(
            sectionID: "message-1",
            sourceRange: laterRange,
            quote: "repeat"
        )

        XCTAssertEqual(selection.sourceRange, laterRange)
    }

    func testAcceptsCrossParagraphSelectionWhenSourceContainsBlockMarkersBetweenVisibleText() throws {
        let source = "# 标题\n\n- 第一项\n- 第二项\n\n> 引用内容"
        let document = try ObsidianMarkdownDocument(sections: [.init(id: "message-1", markdown: source)])
        let ns = source as NSString
        let start = ns.range(of: "标题").location
        let end = ns.range(of: "引用内容")
        let range = NSRange(location: start, length: end.location + end.length - start)

        let selection = try document.validatedSelection(
            sectionID: "message-1",
            sourceRange: range,
            quote: "标题 第一项 第二项 引用内容"
        )

        XCTAssertEqual(selection.sourceRange, range)
    }

    func testAcceptsCrossTableSelectionWithoutCountingPipesOrDividerRow() throws {
        let source = "| 甲 | 乙 |\n| - | - |\n| 丙 | 丁 |"
        let document = try ObsidianMarkdownDocument(sections: [.init(id: "message-1", markdown: source)])
        let ns = source as NSString
        let start = ns.range(of: "甲").location
        let end = ns.range(of: "丁")
        let range = NSRange(location: start, length: end.location + end.length - start)

        let selection = try document.validatedSelection(
            sectionID: "message-1",
            sourceRange: range,
            quote: "甲 乙 丙 丁"
        )

        XCTAssertEqual(selection.sourceRange, range)
    }

    func testAcceptsSelectionAcrossQuoteAndFencedCodeWithoutFenceMarkers() throws {
        let source = "> 引用内容\n\n```swift\nlet value = 1\n```"
        let document = try ObsidianMarkdownDocument(sections: [.init(id: "message-1", markdown: source)])
        let ns = source as NSString
        let start = ns.range(of: "引用内容").location
        let end = ns.range(of: "let value = 1")
        let range = NSRange(location: start, length: end.location + end.length - start)

        let selection = try document.validatedSelection(
            sectionID: "message-1",
            sourceRange: range,
            quote: "引用内容 let value = 1"
        )

        XCTAssertEqual(selection.sourceRange, range)
    }
}
