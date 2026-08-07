# Timeline Semantics — PROGRESS

## 任务 0 基线（2026-08-06）
- 分支 `codex/ios/rich-media-timeline`，HEAD `71759fb`，ahead 1，工作树干净
- 单元 140 passed / 0 failed；UI `testTimelineFilterSheetShowsCorrectKinds` passed；generic build SUCCEEDED

## 目标
时间线恢复“事情发生在哪段时间就出现在哪段时间”；备注与思考可分看/合看；取消关联可反悔。

## 顺序
1. 投影：语义时间 + note/thought 类型（先红测 ≥5 再实现）
2. 三模式 UI：备注｜思考｜合并 + 标签/关联标记（先红 UI 断言）
3. 取消关联确认对话框 + a11y + UI 验证

## 最大风险
- 备注附件与 ThoughtMediaLink 边界易混；手动关联 vs 自动关联展示时间分叉
- 合并模式双卡关联标记与排序一致性
- UI 测试 runner 偶发系统拒绝启动

## 状态
- [x] 任务 0 基线
- [x] 任务 1 投影 + 单元测试（140→150，语义时间 10 条新测全绿）
- [x] 任务 2 三模式 UI（备注｜思考｜合并 + AppStorage + 标签/关联标记 + 7/20 归组）
- [x] 任务 3 取消关联确认（三入口确认框；UI 验证保留/确认）

## 验收证据（终态）
- 单元：`TimeLedgerTests` **150 passed / 0 failed** — TEST SUCCEEDED
- UI：`testTimelineFilterSheetShowsCorrectKinds` — TEST SUCCEEDED
- Build：generic iOS — BUILD SUCCEEDED
- `git diff -- TimeLedger/Models TimeLedger/TimeLedgerApp.swift` 为空
- HEAD 仍 `71759fb`，未 commit / 未 push
- `git diff --check` 无问题

## 实现要点
- 单一投影 `TimelineProjection.records(..., entries:)`：备注卡=entry.note+noteAttachments；手动关联用 entry 时间段；自动/未关联/孤儿用自身 anchorAt
- `TimelineTypeMode` + `@AppStorage("timeline.typeMode")` 默认 merged
- `TimeEntryNoteCard` 新建；思考/媒体卡加「思考」标签与关联标记
- 取消关联：ThoughtCardView / ThoughtEditView / MediaMomentCard 先确认（保留关联 / 确认取消关联）
