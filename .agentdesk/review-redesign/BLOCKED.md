# Review Redesign Blocked

## 已解除：任务 2 UI 定向验收三次止损

- 命令：`xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TimeLedgerUITests/ReviewUITests`
- 第 1 次：2 通过、2 失败；事项日期标签缺失、Chart identifier 多匹配。
- 第 2 次：3 通过、1 失败；`testWeeklyBarDrillsIntoDay()` 点击后周期仍为“周”。
- 第 3 次：3 通过、1 失败；仍为 `testWeeklyBarDrillsIntoDay()`。
- 三轮均出现部分 simulator clone 的 `com.lessen.TimeLedgerUITests.xctrunner` 启动被 `SBMainWorkspace` 拒绝；主 clone 仍执行了 4 个测试。
- 恢复执行后的根因确认：Chart 外层的 `.accessibilityIdentifier("review.time.chart")` 覆盖了 7 个透明下钻按钮各自的 identifier/label，UI 测试因此找不到 `review.time.bucket.0`，并非统计、周期状态或产品路线错误。
- 最小修正：图表仅负责展示；`chartOverlay` 按钮对齐实际 `plotFrame`，单独负责交互与无障碍，不再保留第二条 `chartXSelection` 下钻路径。
- 恢复验收：`TEST SUCCEEDED`；4 通过、failed 0、skipped 0，含 `testWeeklyBarDrillsIntoDay()`。

## 已解除：原有午夜时段 fixture

- 全量命令于 2026-07-31 00:28 执行：`TEST FAILED`；逻辑测试 112 通过、1 失败、skipped 0。新增 8 个统计测试与 4 个复盘 UI 测试全部通过。
- 唯一失败为白名单外现有测试 `TimeLedgerUITests.testDraftAndConfirmedCardsUseTwoLevelExpansion()` 第 140 行，找不到“Fixture 已确认项目”。
- 失败层级显示当前页面日期为 `2026-07-31`，并显示“这天没有已确认记录”；白名单外 `UITestFixtureService` 在 00:30 使用 `now - 4h` 创建确认条目，实际落在 `2026-07-30`。
- 同时间把原始 `fd0a994` 导出到临时目录，定向运行同一现有测试，结果同样为 `TEST FAILED`；因此不是本任务回归，不触发任务改动回滚。
- 2026-07-31 13:27 原样全量运行中该测试已通过，确认午夜窗口阻塞解除。

## 已解除：磁盘空间耗尽

### 全量测试被本机磁盘空间耗尽阻塞

- 2026-07-31 13:27 原样全量测试仅失败于 `ReviewUITests.testTodayCompletedActionAppearsInReview()`；根因是白名单外 Today 页面已把事项完成交互从轻点改为长按，而新增 UI 测试仍调用 `tap()`。
- 已在白名单内把该测试改为 `press(forDuration: 0.25)`；随后定向 `ReviewUITests` 实际 4/4 通过并输出 `TEST SUCCEEDED`。
- 同次运行 Xcode 报 `mkstemp: No space left on device`，结果包未完整保存；`df -h` 显示数据卷仅余 `232 MiB`。
- `~/Library/Developer/XCTestDevices` 原显示占用 `56 GiB`，由 20 个已关机的测试克隆设备组成；用户授权后已通过 `simctl` 官方设备集命令全部删除。
- 该目录现为 `0B`，但 APFS 实际可用空间仅从 `232 MiB` 增至 `402 MiB`，说明此前数字主要是共享克隆的逻辑占用。
- 当前最小的可再生清理候选为 TimeLedger 自身 DerivedData 约 `751 MiB`，以及 Xcode 共享 ModuleCache 约 `604 MiB`；项目规则要求再次获得明确删除授权后才能清理并重跑原样全量测试。

### 已触发全量验收三次止损

- 用户授权后，TimeLedger DerivedData 与 Xcode ModuleCache 已按项目规则移入废纸篓，可用空间恢复到 `1.9 GiB`。
- 2026-07-31 13:50 第 3 次运行原样命令：`xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'`。
- 干净重编译成功，逻辑测试均通过；新增 `ReviewSummaryServiceTests` 的 8 个场景全部通过。
- UI 阶段安装 `TimeLedgerUITests-Runner` 时失败：`IXUserPresentableErrorDomain Code=11`，底层为 `NSPOSIXErrorDomain Code=28`、`No space left on device`。
- 运行中已看到新增复盘 UI 测试前三项通过；`testWeeklyBarDrillsIntoDay()` 未完成。还观察到现有 `testDraftAndConfirmedCardsUseTwoLevelExpansion()` 失败，但本轮因基础设施耗尽且被中断，不能作为可靠回归结论。
- 按“同一验收连续失败 3 次就停该项”规则终止卡住的 `xcodebuild`，最终输出 `** BUILD INTERRUPTED **`；不再重试。
- 未完成：可信的原样全量 `TEST SUCCEEDED`（failed 0、skipped 0）、当前工作树下的 generic build、最终声明/方法计数、`git diff --check` 与白名单路径核验。
- 恢复条件：先由用户在任务外释放足够的真实磁盘空间，再开启新的验收轮次；本轮已经止损。

### 用户恢复后的新验收轮次

- 用户明确要求继续，且 `df -h` 显示真实可用空间已增至 `14 GiB`，因此在环境发生实质变化后开启新验收轮次。
- 原样全量命令输出 `TEST SUCCEEDED`；xcresult 摘要为 `totalTestCount: 119`、`failedTests: 0`、`skippedTests: 0`。
- 新增 8 个 `ReviewSummaryServiceTests` 和 4 个 `ReviewUITests` 均通过；现有 UI 测试亦全部通过。
- generic iOS 命令输出 `BUILD SUCCEEDED`。
- 静态计数为 107 个 `@Test`、12 个 UI test 方法；`git diff --check` 为空且退出 0。

## 当前阻塞

### 工作树路径不满足任务白名单

- 当前 `git status --short` 中有 7 个白名单外修改：`TimeLedger/Models/ActionItem.swift`、`TimeLedger/Services/ActionCompletionService.swift`、`TimeLedger/Views/Actions/ActionEditView.swift`、`TimeLedger/Views/Actions/ActionListView.swift`、`TimeLedger/Views/Today/TodayView.swift`、`TimeLedgerTests/ActionCompletionServiceTests.swift`、`TimeLedgerUITests/TimeLedgerUITests.swift`。
- 这些修改在本任务执行期间由外部并行工作出现，本任务没有修改或回滚它们。
- 因此功能、测试、构建和 diff 格式已通过，但“`git diff --name-only` 仅出现白名单文件”这一完成条件在当前共享工作树下不能成立。
