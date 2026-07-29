# BLOCKED

无

## 顺手记下（未做，非本轮失败）
- 完整旁注/批注体系：本轮明确不做，仅记需求。
- 会话工作区在「库中尚无任何正式片段」时，摘录无法绑定 segmentID（ledger 要求 segment 存在）；有片段后可用 preferredFormalSegmentID。若产品要「无片段也能摘录」，需另案设计默认片段创建（schema/产品语义），本轮不扩。
- MarkdownUI SPM 未引入：块级分段用本地 `MarkdownBodyView` 重做，满足「禁止无段墙」且不嵌 Obsidian 级整包。
