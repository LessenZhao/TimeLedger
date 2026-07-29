> **UI 以 [008-markdown-layout-document-reading-notes.md](./008-markdown-layout-document-reading-notes.md) 为准；本文保留笔记域边界。**

# 007 阅读笔记平行层

## 目标
把「备考材料生产」与「个人阅读笔记」拆成平行两层：选文即记、原文与正式库都能记、笔记库统一找回。

## 平行关系
- **正式库主路径不变**：AI 候选 → 待确认 → 确认写入 `chatgpt-ledger.json`。
- **阅读笔记旁路**：划线/写笔记写入 `records/chatgpt-reading-notes.json`，**不升级**为正式资产，也不写入 ledger 资产结构。
- `asset.note` 仍是整卡备注（只读兼容）；选区笔记不写该字段。

## 模型
- 一种 `ReadingNote`：`id / body? / isHighlight / quoteSnapshot / timestamps / anchor`。
- 互斥 `ReadingNoteAnchor`：
  - `sourceMessageSpan`：conversationId, messageId, contentHash, loc, len, textHash
  - `formalAssetSpan`：assetId, versionId, textHash, loc, len, quoteHash
- Document v1；原子写；坏文件 → empty。

## UI
- **阅读底座**：原文/正式库正文必须 Markdown 层级保真显示（与 Obsidian / `MarkdownBodyView` 同级观感）。
- 实现：`MarkdownAttributedRenderer` **按 Obsidian 方式渲染**（隐藏 `#`/`**`/列表符/代码围栏），并用 display→source 映射保证选区笔记仍锚定归档原文。
- 笔记/划线/复制是叠加层，不得退回纯文本框阅读。

- 原文与正式库正文：可选中；浮层仅 **写笔记｜划线｜复制**。
- 单色高亮叠加；点击高亮可编辑/删除。
- 顶部 Tab：会话｜待确认｜正式库｜**笔记库**；笔记库列表带回跳。
- 已删除「摘录此段 / 摘录袋」主路径；`addManualFormalAsset` API 保留但不作为笔记入口。

## 禁区
- 待确认：禁止创建/展示选区笔记。
- 笔记不得转入正式资产；不改 candidate 确认语义。
- 不做跨消息选区；不新依赖；不改 iOS。

## 验收要点
- Core / Hub `swift test` 全绿且不低于基线；ReadingNote 相关单测覆盖两锚点与持久化。
- `rg "摘录此段|摘录袋" EvolutionHub/Sources` 无匹配。
- 人机：原文划线、原文笔记、正式库笔记、笔记库回跳、待确认无入口。
