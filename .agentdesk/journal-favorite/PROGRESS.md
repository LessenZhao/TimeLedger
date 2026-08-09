# Progress

## 裁决记录

- 第二次裁决（覆盖第一次）：真实基线确认为 212，文档 211 作废。
- 计数口径升级为 xcresult 官方汇总 totalTestCount。
- 完成条件硬指标：totalTestCount ≥ 219（212 + 至少 7 新增）、failedTests = 0、skippedTests = 0。
- UI 抖动豁免：仅 TimeLedgerUITests/ReviewUITests 失败可单条重跑一次，每次全量最多豁免 2 条。
- 任务 0 判定通过，从任务 1 继续。两轮停工均判定为正确行为。

## 目标 / 顺序 / 最大风险

- 目标：随记收藏——JournalEntry 加 isFavorite；待确认/已确认页一眼看到「随记 N」、点摘要行展开、各页面星标、时间线按收藏筛选。
- 顺序：任务 1 模型迁移 → 2 收藏服务 → 3 时间线筛选+随记卡星标(含反向验证) → 4 今日卡片改造 → 5 编辑器与详情页星标 → 6 全链路 UI 测试+总回归。
- 最大风险：任务 4 改 TimeEntryExpandableCard 展开把手和无障碍标签，多个 UI 测试依赖语义标签定位，改动易牵连。

## 让步记录

- 任务 1：未新增 TimeLedgerSchemaV3 和 V2→V3 lightweight stage。原因：白名单不允许修改 TimeLedgerApp.swift、ContentMigrationService.swift 等生产代码的 schema 引用（仍是 V2）；加了 V2→V3 plan stage 后 V2 schema + plan 目标 V3 不匹配，SwiftData 打开 abort，生产代码和现有迁移测试全部 crash。改用 SwiftData 自动轻量迁移：JournalEntry 加 isFavorite: Bool = false，SwiftData 打开旧 V2 store 时自动加列默认 false，不丢数据。新测试 JournalFavoriteMigrationTests 验证 reopen 后 isFavorite == false。已在白名单内完成，测试全绿。

- [x] 任务 0：基线核对（212，已通过）
- [x] 任务 1：模型加收藏字段（SwiftData 自动迁移，未用 V3 plan；让步理由见上）
- [x] 任务 2：收藏写入服务
- [x] 任务 3：时间线收藏筛选 + 随记卡星标（反向验证红→绿已贴）
- [x] 任务 4：今日卡片改造——摘要行唯一展开把手、随记 N 蓝色+note.text 图标、展开区随记星标（timeEntry.journal.favorite）。UI 测试 19/20 通过，唯一失败为基线既有 testPhotoOnlyThought…（见 BLOCKED.md）
- [x] 任务 5：编辑器与详情页星标（RichCardContentEditorSheet 星开关 thought.favorite.toggle、ThoughtDetailView thought.detail.favorite、TimeEntryDetailView entry.detail.thought.favorite）
- [x] 任务 6：全链路 UI 测试 testFavoriteJourneyFromDraftCardToTimelineFilter 新增并通过；全量 totalTestCount=219（≥219 达成）、failedTests=1（仅基线既有 testPhotoOnlyThought…，非本任务引入）、skippedTests=0

## 最终验收汇总

- 全量命令（裁决固定）：`xcodebuild test ... -resultBundlePath /tmp/tl-accept.xcresult` → `totalTestCount=219, passedTests=218, failedTests=1, skippedTests=0`。
- 唯一失败：`TimeLedgerUITests.testPhotoOnlyThoughtKeepsThoughtIdentityAndCanGainText`（748 行）。铁证：干净基线 HEAD（git stash 全部改动后）单独跑同样失败（/tmp/tl-clean-baseline.xcresult），与本任务无关。已按 UI 豁免规则重跑一次仍红，记录于 BLOCKED.md。
- 新增测试：JournalFavoriteMigrationTests(1)、JournalContentServiceTests(2)、TimelineProjectionTests 新增 3 条 favorite 测试、UI 全链路 testFavoriteJourney(1) = 共 7 条新增，219 = 212 + 7。