# CHANGELOG

本文件记录项目已经完成的实际历史变更、版本记录和验证摘要。

它只记录已经发生并完成的变化，不记录当前正在处理的任务。当前任务和项目当前状态写入 `PROJECT_STATE.md`。

## Unreleased

（空）

## 0.3.0 — 2026-07-12

### Added — V3 Personal Evolution Engine（本地 MVP）

- `Packages/EvolutionCore`：Context DTO、Collector 协议、SyncBatch、LinkingEngine、SourceAdapters、确定性复盘、Git 摘要。
- `EvolutionHub`：macOS 时间线 / 收件箱 / 复盘 / 设置；「同步今日上下文」；JSON 与 SyncBatch 导入。
- iOS `SyncEnvelopeExportService` + 导出入口（给 Mac Hub）。
- `scripts/build-evolution-hub-app`：Release 构建并安装/覆盖 `/Applications/Evolution Hub.app`。
- 文档：`docs/plans/003-personal-evolution-engine-v3.md`、`docs/evolution-hub-usage.md`。

### External（独立仓）

- `agent-session-archive/tools/collector_cli.py`：Codex/Claude CollectorResult JSON。
- `ai-chat-future-activity-archiver` companion：`POST /jobs/pee-sync`（waitingForBrowser）。

### Verified

- `Packages/EvolutionCore`：`swift test` 通过。
- `EvolutionHub`：`swift test` 通过；`/Applications/Evolution Hub.app` 可打开。
- iOS：`xcodebuild test`（iPhone 17）通过，含 SyncEnvelope 单测。
- collector_cli 实跑 Codex 返回 succeeded。

### Limits

- 无 Bonjour；ChatGPT 依赖浏览器扩展认领；明日调整文件回传，无 SwiftData 新模型。

## 0.2.0 — 2026-07-09

### Added — V2 ThoughtNote 思考卡片

- 新增 `ThoughtNote` SwiftData 模型（body/capturedAt/anchorAt/linkedEntryId/linkSource）。
- 新增 `ThoughtLinkingService`：quickCaptureThought、tryAutoLinkThought、linkThoughtsForEntry、relinkAutoThoughtsForDate、addThought、manuallyLinkThought、unlinkThought、thoughtsForEntry、thoughtsCapturedOnDate、updateThought、deleteThought。
- 新增 `Views/Thoughts/`：ThoughtQuickCaptureSheet、ThoughtDayView、ThoughtCardView、ThoughtEditView、ThoughtManualLinkView、ThoughtAddSheet。
- TodayView 增加"+ 想法"入口和"今日思考"导航入口。
- TimeListView 每条 TimeEntry 显示关联思考数量。
- TimeEntryEditView 显示关联思考列表（"当时想法"/"事后补充"标签）+ 添加思考按钮。
- 新建 TimeEntry 后自动吸附该时间段内未关联的 ThoughtNote。
- DailyReviewView 增加思考总数和每小时思考分布。
- JSON 导出包含 thoughtNotes。
- Markdown 日报包含关联思考、今日捕获的思考、未匹配思考。
- CSV 导出增加 linkedThoughtCount / linkedThoughts 列。

### Tests

- 新增 12 条 ThoughtLinkingService 单元测试。
- 新增 6 条导出增强测试。
- 全量回归：44 单元测试 + 3 UI 测试通过。
- 模拟器构建通过（iPhone 17, OS 26.5）。
- 真机构建通过并安装到 iPhone 16 plus。

### Changed

- `TimeLedgerApp.swift`：Schema 注册加 `ThoughtNote.self`。
- `TimeCursorService.swift`：quickRecord / recordSegment 后调用 `linkThoughtsForEntry`。
- `ExportService.swift`：重写，增加 thoughtNotes 到 JSON/Markdown/CSV。
- `TimeLedger.xcodeproj/project.pbxproj`：加 `DEVELOPMENT_TEAM = Y5ADUFM52Q`。

## 0.1.0 — 2026-07-08

### Added — V1 时间记录

- 使用 Xcode 创建 SwiftUI + SwiftData iOS App 工程。
- 接入项目规则、状态、变更记录、文档入口和路线图。
- 阶段 1：SwiftData 模型、时间游标服务、今日统计服务、首页项目列表、新增项目、快速记录和撤销。
- 阶段 2：时间调整 Sheet、时间列表、时间记录编辑器、草稿编辑/删除。
- 阶段 3：确认状态机、校验服务、批量确认、取消确认。
- 阶段 4：自然日统计、跨天 overlap 切分。
- 阶段 5：日/周/月 Review、CSV/JSON/Markdown 导出。
- 阶段 6：项目管理、空状态、错误提示、完整测试。

### Verified

- `xcodebuild build` 通过。
- `xcodebuild test` 32 条测试通过。
- `scripts/project-check` 通过。
