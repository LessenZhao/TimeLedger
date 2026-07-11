# 项目总览

## 项目目标

TimeLedger 是面向个人使用的 iOS 原生时间账本。目标是用柳比谢夫时间记录法记录真实时间开销，但交互上避免传统"开始/结束计时器"的摩擦。第二版增加了"思考卡片"能力，把 App 从单纯时间开销记录升级为"时间线优先的个人记录入口"。

核心路径：
1. 时间记录：打开 App -> 看到当前未记录时长 -> 点项目右侧快捷按钮 -> 生成灰色草稿记录 -> 项目今日累计立即刷新 -> 在时间页修正 -> 确认转换为黑色正式记录 -> 导出复盘数据。
2. 思考记录：点灯泡按钮 -> 输入想法 -> 保存 -> 系统自动关联到覆盖该时间点的 TimeEntry -> 在时间线和复盘中查看"做了什么 + 想到了什么"。

## 当前结构

- `TimeLedger.xcodeproj`：Xcode 工程。
- `TimeLedger/`：App 源码。
  - `Models/`：SwiftData 模型（`Project`、`TimeCursor`、`TimeEntry`、`AppSettings`、`ThoughtNote`）。
  - `Services/`：业务服务（`TimeCursorService`、`TimeSummaryService`、`ValidationService`、`ExportService`、`DateRangeService`、`ThoughtLinkingService`）。
  - `Views/`：SwiftUI 页面。
    - `Today/`：首页、项目列表、时间列表、时间编辑、时间调整。
    - `Thoughts/`：快速想法输入、今日思考卡片流、思考编辑、手动关联、添加思考。
    - `Review/`：日/周/月复盘（含思考分布）。
    - `Settings/`：设置和导出。
    - `Projects/`：项目管理。
  - `Utilities/`：格式化与日期工具。
- `TimeLedgerTests/`：核心业务单元测试。
- `TimeLedgerUITests/`：基础 UI 测试。
- `docs/plans/`：分阶段路线图和实施计划。

## 运行方式

```bash
open TimeLedger.xcodeproj
```

在 Xcode 中选择 `TimeLedger` scheme，选择可用 iOS Simulator 或真机运行。真机运行需先在 Xcode Settings > Accounts 登录 Apple ID 并选择 Development Team。

## 验证方式

```bash
scripts/project-check
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS'
```

## 当前边界

- 本地优先，不做账号、服务器、云同步、订阅、AI 总结、标签系统、双链、知识图谱、富文本编辑器、图片/语音/文件附件。
- 分类只用 `categoryName: String`，不做复杂二级分类树。
- App 不做后台计时，只保存 `TimeCursor.cursorAt`，用当前时间动态计算未记录时长。
- 所有统计、Review 和导出按自然日计算，不使用生活日。
- `ThoughtNote` 通过 `anchorAt` 自动关联到覆盖该时间点的 `TimeEntry`；手动关联优先级高于自动关联。
- 真机签名使用免费 Apple ID Personal Team，签名有效期 7 天，过期后需在 Xcode 重新编译安装。
