# 06 — 检查、确认并查看 ChatGPT 账本

**What to build:** 用户回到 Mac App 后可以检查 Skill 候选、纠正主题归属或候选主题名称，再明确确认；确认后的同一批语义记录可按原会话或按跨会话主题查看，并能追溯每个片段和内容点的原始消息。

**Blocked by:** 04 — 增加 Mac ChatGPT 对话工作流; 05 — 实现显式 ChatGPT Ledger Skill.

**Status:** completed — automated verification passed; Task 7 real-material acceptance remains required.

- [x] 候选仅读取不自动应用；确认前清楚展示新主题、匹配、内容点、重复项和忽略消息，并支持主题归属纠正和候选主题重命名。
- [x] 确认后显示最终回执，用户可重命名或合并主题、移动片段、标记重点、添加备注；这些用户内容在刷新后不被候选覆盖。
- [x] 按会话与按主题投影解析到相同的主题、片段、内容点和来源身份，且每项均能打开对应来源消息。

**Verification:** `swift test --filter ChatConversation` passed in EvolutionCore (18 tests) and EvolutionHub (7 tests); full `swift test` passed in EvolutionCore (107 tests) and EvolutionHub (31 tests). `git diff --check` and the committed-diff check passed.
