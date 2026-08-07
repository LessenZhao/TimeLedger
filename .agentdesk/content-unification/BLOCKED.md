# Content Unification Blocked

## 置顶：真机发现与最终验收阻塞

- 首次命令失败：`XPCError 1001` / CoreDeviceService invalidated；遵守任务书未重启服务。
- 最终重试命令：`xcrun devicectl list devices`，退出码 0，已发现 iPhone 16 Plus `E4D90A96-E433-5DE3-9703-03BF7976E731`，但状态为 `unavailable`。
- 影响：无法安装 App，升级门禁、旧数据计数、四类随记、保存重开、取消、杀进程恢复和迁移重跑无副本等真机场景均未执行；完成条件不满足。

## Simulator 测试执行阻塞

- 2026-08-07 新增迁移测试首次红测命令：`xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TimeLedgerTests/ContentMigrationTests`。
- 结果：测试尚未编译即遇到 `CoreSimulatorService connection became invalid`、`simdiskimaged crashed or is not responding`、`Unable to discover any Simulator runtimes`。
- 处理：不重启服务；用 generic simulator `build-for-testing` 获取编译红/绿证据，设备恢复后再按规定顺序实际执行测试。
- 后续状态：Simulator 已自行恢复；单元 184 个全过、skipped 0。此项不再阻塞，仅保留首次红测环境证据。

## UI 验收三轮上限：时间线筛选

- 唯一一次全量中 `testTimelineFilterSheetShowsCorrectKinds` 失败；两次定向复验仍失败，第三次最终断言为 `TimeLedgerUITests.swift:351: XCTAssertFalse failed`。
- 根因证据：新加的“照片/视频”类型提示也显示在混合图文随记中；文字筛选保留混合记录后，这两个提示仍可见。
- 已做最小修正：类型提示只在纯媒体随记显示；遵守三轮上限，不再第四次运行该方法，因此此修正仅完成编译验证，UI 行为仍为未验证。
