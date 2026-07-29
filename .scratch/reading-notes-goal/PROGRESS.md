# Reading Notes Parallel — PROGRESS
日期：2026-07-28
分支：codex/chatgpt-conversation-ledger

## 目标
备考材料 vs 个人阅读笔记平行；原文/正式库可选区划线笔记；待确认禁笔记；删摘录袋主路径；笔记库回跳。

## 结果
- T0 基线：Core 124 / Hub 53 → 通过
- T1 领域+持久化：ReadingNote + Layout URL + FileStore + 单测 → 完成
- T2 Store：allNotes/过滤/CRUD/重启持久化 → 完成；ReviewView 无笔记创建
- T3 浮层+删摘录：ReadingSelectableTextBlock；rg 摘录此段|摘录袋 无匹配
- T4 笔记库 Tab + 回跳 → 完成
- T5 docs/plans/007-reading-notes-parallel.md（32 行）

## 最终机器验收
- Core：Executed 129 tests, 0 failures
- Hub：Executed 56 tests, 0 failures
- rg "摘录此段|摘录袋" EvolutionHub/Sources → exit 1
- ReadingNote 相关单测：Core 4 + Layout 1 + Hub 3 ≥ 6

## 人机 5 步
1. 原文划线：会话 Tab 打开消息 → 拖选 → 划线 → 黄底高亮
2. 原文笔记：拖选 → 写笔记 → 保存 body
3. 正式库笔记：正式库阅读正文 → 拖选写笔记/划线
4. 笔记库回跳：笔记库点条目 → 回会话或正式库
5. 待确认无入口：候选原文/阅读无写笔记浮层、无高亮列表

## 最大风险（已处理）
删 excerpt 牵动三视图；正式锚 versionId 取 currentVersion。

## 修正：Markdown 保真阅读
- MarkdownAttributedRenderer 字符级保真
- 原文/正式库笔记层叠在 Markdown 样式上，不再用纯文本框阅读
- Hub tests 58 全绿
