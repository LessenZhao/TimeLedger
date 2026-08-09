# BLOCKED

## 2026-08-08 最终验收：testPhotoOnlyThoughtKeepsThoughtIdentityAndCanGainText 基线既有失败（唯一阻塞项）

- 现象：全量测试 `totalTestCount=219`、`passedTests=218`、`failedTests=1`、`skippedTests=0`。唯一失败为 `TimeLedgerUITests.testPhotoOnlyThoughtKeepsThoughtIdentityAndCanGainText`（748 行 `timeline.typeMode.picker` 无「随记」按钮）。
- 根因（UI hierarchy 铁证）：失败瞬间 app 仍停在「今天」页，「记录随记」sheet 未关闭——`thought.composer.save` 按钮处于 Disabled，tap 无效。Disabled 条件是 `isSaving || session?.hasContent != true`（RichCardContentDetail.swift:259）。「1 个附件」已显示但保存仍禁用，说明相机 fixture 添加照片后 UI 显示与 ContentEditor session 状态存在异步竞态。
- 铁证：`git stash` 全部改动、移走新增测试后，在干净基线 HEAD 下单独跑同一测试，**同样在第 748 行失败**（/tmp/tl-clean-baseline.xcresult）。该失败与本任务改动无关，是既有 flaky/产品异步竞态。
- 豁免处理：已按裁决第 4 条对 TimeLedgerUITests 失败单条重跑一次（/tmp/tl-task6-photo-exempt.xcresult），仍红。重跑仍红即停。
- 影响：总测试数 ≥219 达成、skipped=0 达成；唯一未达成为 failedTests=0（1 条基线既有失败，非本任务引入）。
- 建议：该竞态在 ContentEditor.swift（白名单外），需产品侧修复「保存按钮 Disabled 直到媒体持久化完成」或在测试中等保存按钮 enabled 后再 tap。
