import XCTest
@testable import EvolutionHubCore

final class MarkdownLayoutDocumentTests: XCTestCase {
    func testHeadingListQuoteCodeRangesSliceSource() {
        let source = """
        # 标题一

        正文段。

        ## 标题二

        - 列表甲
        - 列表乙

        > 引用行

        ```
        keep
        lines
        ```
        """
        let doc = MarkdownLayoutBuilder.build(source: source)
        let ns = doc.source as NSString

        let h1 = doc.blocks.first { if case .heading(1) = $0.kind { return true }; return false }
        XCTAssertEqual(h1?.text, "标题一")
        XCTAssertEqual(ns.substring(with: h1!.sourceRange.nsRange), "标题一")

        let h2 = doc.blocks.first { if case .heading(2) = $0.kind { return true }; return false }
        XCTAssertEqual(h2?.text, "标题二")
        XCTAssertEqual(ns.substring(with: h2!.sourceRange.nsRange), "标题二")

        let items = doc.blocks.compactMap { block -> String? in
            if case .listItem = block.kind { return block.text }
            return nil
        }
        XCTAssertEqual(items, ["列表甲", "列表乙"])
        for block in doc.blocks {
            if case .listItem = block.kind {
                XCTAssertEqual(ns.substring(with: block.sourceRange.nsRange), block.text)
            }
        }

        let quote = doc.blocks.first { if case .quote = $0.kind { return true }; return false }
        XCTAssertEqual(quote?.text, "引用行")
        XCTAssertEqual(ns.substring(with: quote!.sourceRange.nsRange), "引用行")

        let code = doc.blocks.first { if case .code = $0.kind { return true }; return false }
        XCTAssertEqual(code?.text, "keep\nlines")
        XCTAssertEqual(ns.substring(with: code!.sourceRange.nsRange), "keep\nlines")
    }

    func testSelectionInsideBlockMapsToSource() {
        let source = "前言\n\n## 版本一\n\n- 5分钟：审题和列框架\n"
        let doc = MarkdownLayoutBuilder.build(source: source)
        let item = doc.blocks.first { if case .listItem = $0.kind { return true }; return false }!
        let textNS = item.text as NSString
        let sub = "审题和列框架"
        let local = textNS.range(of: sub)
        XCTAssertNotEqual(local.location, NSNotFound)
        let mapped = doc.sourceRange(blockID: item.id, textUTF16Range: local)
        XCTAssertNotNil(mapped)
        XCTAssertEqual((doc.source as NSString).substring(with: mapped!.nsRange), sub)
        XCTAssertEqual(doc.quote(blockID: item.id, textUTF16Range: local), sub)
    }

    func testCompatibleWithMarkdownStructureListSplit() {
        let source = """
        ## 版本一

        - 5分钟：审题和列框架
        - 30—40分钟：限时作答
        """
        let structure = MarkdownStructure.parse(source)
        let doc = MarkdownLayoutBuilder.build(source: source)
        let structureItems: [String] = structure.blocks.compactMap {
            if case .list(_, let items) = $0 { return items.map(\.text) }
            return nil
        }.flatMap { $0 }
        let layoutItems = doc.blocks.compactMap { block -> String? in
            if case .listItem = block.kind { return block.text }
            return nil
        }
        XCTAssertEqual(layoutItems, structureItems)
    }
}
