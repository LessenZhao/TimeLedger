import XCTest
@testable import EvolutionHubCore

final class MarkdownStructureTests: XCTestCase {
    func testDailyFlowListsStaySeparateItems() {
        let markdown = """
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
        - 15分钟：评分诊断
        - 20—30分钟：重写核心部分
        - 5分钟：记录规则

        如果时间只有30分钟，也不要改成看资料，而应完成缩小版闭环：

        **列一道题的框架 → 接受反馈 → 重搭框架。**
        """

        let structure = MarkdownStructure.parse(markdown)

        // Headings preserved
        guard case .heading(1, let h1) = structure.blocks[0] else {
            return XCTFail("expected h1, got \(structure.blocks[0])")
        }
        XCTAssertEqual(h1, "三、每天的标准流程")

        // First list has 6 separate items, not one glued paragraph
        let lists = structure.blocks.compactMap { block -> [MarkdownStructure.ListItem]? in
            if case .list(_, let items) = block { return items }
            return nil
        }
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists[0].map(\.text), [
            "5分钟：审题和列框架",
            "30—40分钟：限时作答",
            "15分钟：自评和AI评分",
            "20分钟：定向修改",
            "10分钟：脱稿复现",
            "5分钟：记录唯一规则",
        ])
        XCTAssertEqual(lists[1].count, 5)
        XCTAssertEqual(lists[1][0].text, "10分钟：审题立意和搭框架")

        // No block should be a single paragraph containing glued list markers
        for block in structure.blocks {
            if case .paragraph(let text) = block {
                XCTAssertFalse(text.contains("列框架30—40"), "paragraph collapsed list: \(text)")
                XCTAssertFalse(text.contains("- 5分钟：审题和列框架- 30"), "paragraph glued markers: \(text)")
            }
        }
    }

    func testOrderedListAndCodeFence() {
        let markdown = """
        步骤：

        1. 先审题
        2. 再列框架

        ```
        keep
        lines
        ```
        """
        let structure = MarkdownStructure.parse(markdown)
        XCTAssertTrue(structure.blocks.contains { block in
            if case .list(true, let items) = block {
                return items.map(\.text) == ["先审题", "再列框架"]
            }
            return false
        })
        XCTAssertTrue(structure.blocks.contains { block in
            if case .code(let text) = block {
                return text == "keep\nlines"
            }
            return false
        })
    }
}
