# CHANGELOG

本文件记录项目已经完成的实际历史变更、版本记录和验证摘要。

它只记录已经发生并完成的变化，不记录当前正在处理的任务。当前任务和项目当前状态写入 `PROJECT_STATE.md`。

## Unreleased

尚未形成正式版本发布、但已经完成并验证的变更。

### Changed

- 使用 Xcode 创建 SwiftUI + SwiftData iOS App 工程 `TimeLedger`。
- 接入项目规则、状态、变更记录、文档入口和路线图。
- 新增阶段 1 基础实现：SwiftData 模型、时间游标服务、今日统计服务、首页项目列表、新增项目、快速记录和撤销入口。

### Verified

- `xcodebuild -list -project TimeLedger.xcodeproj` 可识别 app、unit test、UI test targets 和 `TimeLedger` scheme。
- `scripts/project-check` 通过。
- `xcodebuild build` 当前被 Xcode platform 状态阻塞：`iOS 26.5 is not installed` / `Found no destinations for the scheme`。
