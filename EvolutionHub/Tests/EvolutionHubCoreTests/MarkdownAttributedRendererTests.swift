import XCTest
@testable import EvolutionHubCore

final class MarkdownAttributedRendererTests: XCTestCase {
    func testDisplayHidesMarkersAndDistinguishesHeadingLevels() {
        let markdown = """
        # 标题一

        正文第一段，含 **加粗** 与 `code`。

        ## 标题二

        - 列表甲
        - 列表乙

        > 引用行
        """

        let result = MarkdownAttributedRenderer.render(source: markdown)
        let display = result.display.string
        XCTAssertTrue(display.contains("标题一"))
        XCTAssertTrue(display.contains("标题二"))
        XCTAssertFalse(display.contains("# 标题一"))
        XCTAssertFalse(display.contains("## 标题二"))
        XCTAssertFalse(display.contains("**加粗**"))
        XCTAssertTrue(display.contains("•"))
        XCTAssertFalse(result.quoteDisplayRanges.isEmpty)

        let ns = display as NSString
        let h1 = ns.range(of: "标题一")
        let h2 = ns.range(of: "标题二")
        let body = ns.range(of: "正文第一段")
        let h1Font = result.display.attribute(.font, at: h1.location, effectiveRange: nil) as? NSFont
        let h2Font = result.display.attribute(.font, at: h2.location, effectiveRange: nil) as? NSFont
        let bodyFont = result.display.attribute(.font, at: body.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(h1Font)
        XCTAssertNotNil(h2Font)
        XCTAssertNotNil(bodyFont)
        XCTAssertGreaterThan(h1Font!.pointSize, h2Font!.pointSize)
        XCTAssertGreaterThan(h2Font!.pointSize, bodyFont!.pointSize)
    }

    func testSelectionMapsBackToSourceAndIsContinuousDocument() {
        let markdown = """
        ## 版本一

        - 5分钟：审题和列框架
        - 30—40分钟：限时作答
        """
        let result = MarkdownAttributedRenderer.render(source: markdown)
        let displayNS = result.display.string as NSString
        let target = "5分钟：审题和列框架"
        let displayRange = displayNS.range(of: target)
        XCTAssertNotEqual(displayRange.location, NSNotFound)
        let sourceRange = result.sourceRange(forDisplay: displayRange)
        XCTAssertEqual((markdown as NSString).substring(with: sourceRange!), target)
    }

    func testBoldMapping() {
        let markdown = "请看 **重点表述** 结束"
        let result = MarkdownAttributedRenderer.render(source: markdown)
        let d = result.display.string as NSString
        XCTAssertEqual(d.range(of: "**").location, NSNotFound)
        let boldDisplay = d.range(of: "重点表述")
        let src = result.sourceRange(forDisplay: boldDisplay)
        XCTAssertEqual((markdown as NSString).substring(with: src!), "重点表述")
    }
}
