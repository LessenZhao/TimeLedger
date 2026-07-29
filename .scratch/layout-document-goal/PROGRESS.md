# 008 Layout Document — PROGRESS
日期：2026-07-28

## T0 基线
- Core 129 / Hub 59

## 已完成
- T1 MarkdownLayoutDocument + Builder + 3 tests
- T2 L1: allowsNotes=false → 纯 MarkdownBodyView；true → AnnotatableMarkdownReader（块级同 MarkdownBodyView 常量）
- T3/T4 SelectionStore 唯一选区 + 浮层 + 块内选区映射笔记 API
- T5 Review 仍 allowsNotes:false（既有）
- SourceView / AssetReader 挂接 AnnotatableMarkdownReader
- Hub tests: 62, 0 fail

## 待人机
- Obsidian 并排无叠字、H1/H2、选区浮层、换选、正式库、待确认无笔记、笔记库回跳

## 安装
- /Applications/TimeLedger.app 已更新（008）
- Hub 62 / 需确认 Core 仍 ≥129

## 空白修复
- L1 永远 MarkdownBodyView（正文可见）
- L2 选区改为下方独立层，GeometryReader 强制宽度≥120
- 已装 App
