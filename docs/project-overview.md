# 项目总览

## 项目目标

TimeLedger 是面向个人使用的 iOS 原生时间账本。目标是用柳比谢夫时间记录法记录真实时间开销，但交互上避免传统“开始/结束计时器”的摩擦。

第一版核心路径：

打开 App -> 看到当前未记录时长 -> 点项目右侧快捷按钮 -> 生成灰色草稿记录 -> 项目今日累计立即刷新 -> 在时间页修正 -> 确认转换为黑色正式记录 -> 导出复盘数据。

## 当前结构

- `TimeLedger.xcodeproj`：Xcode 工程。
- `TimeLedger/`：App 源码。
  - `Models/`：SwiftData 模型。
  - `Services/`：时间游标、统计、校验、导出等业务服务。
  - `Views/`：SwiftUI 页面。
  - `Utilities/`：格式化与日期工具。
- `TimeLedgerTests/`：核心业务单元测试。
- `TimeLedgerUITests/`：基础 UI 测试。
- `docs/plans/000-roadmap.md`：第一版分阶段路线图。

## 运行方式

```bash
open TimeLedger.xcodeproj
```

在 Xcode 中选择 `TimeLedger` scheme，选择可用 iOS Simulator 或真机运行。

## 验证方式

```bash
scripts/project-check
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS'
```

## 当前边界

- 本地优先，不做账号、服务器、云同步、订阅或 AI 总结。
- 第一版分类只用 `categoryName: String`，不做复杂二级分类树。
- App 不做后台计时，只保存 `TimeCursor.cursorAt`，用当前时间动态计算未记录时长。
- 所有统计、Review 和导出按自然日计算，不使用生活日。
- 已知风险：当前 Xcode 提示 iOS 26.5 runtime 未安装，Simulator 运行可能阻塞。
