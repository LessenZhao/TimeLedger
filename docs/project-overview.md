# 项目总览

## 项目目标

**TimeLedger** 是个人时间事实入口（iOS）：柳比谢夫式低摩擦时间记录 + `JournalEntry`。
**Personal Evolution Engine (V3)** 在 Mac 上用 **Evolution Hub** 把时间事实与 Codex / Claude / ChatGPT 等上下文对齐，做有证据的每日复盘。

核心闭环：目标 → 行动 → 事实证据 → 结果 → 复盘 → 调整 → 下一轮验证。

## 日常路径

1. **手机**：打时间块、写思考；设置 → 导出 **SyncEnvelope（给 Mac Hub）**。  
2. **Mac**：打开 `/Applications/Evolution Hub.app` → 导入 SyncEnvelope → **同步今日上下文**。  
3. 收件箱确认/拒绝关联 → 每日复盘填偏差与明日调整 → 确认。  

更细步骤见 `docs/evolution-hub-usage.md`。

## 当前结构

```text
TimeLedger/                 # iOS SwiftUI + SwiftData
Packages/EvolutionCore/     # 跨端协议与纯逻辑（SPM）
EvolutionHub/               # macOS Hub（SPM SwiftUI）
  AppBundle/Info.plist
  SampleData/               # 练手 JSON
scripts/build-evolution-hub-app   # 构建并安装到 /Applications
docs/plans/003-…            # V3 实施与审计
```

### iOS（`TimeLedger/`）

- V3 生产模型：`Project`、`TimeCursor`、`TimeEntry`、`AppSettings`、`JournalEntry`、`ContentDocument`、`ContentAttachment`
- 冻结迁移输入：`ThoughtNote`、`ThoughtMediaLink`，不再承担生产业务
- 服务：`TimeLedgerEngine` 是唯一业务写入入口；另有时间游标、统计、校验、导出和 `SyncEnvelopeExportService`
- 页面：Today / Thoughts / Review / Settings / Projects

### EvolutionCore

Context* DTO、CollectorRequest/Result、SyncBatch、LinkingEngine、SourceAdapters、DeterministicReview、GitEvidence 摘要。

### Evolution Hub

时间线、上下文收件箱、每日复盘、设置；调用外部 Collector；不写 iOS SwiftData。

### 外部 Collector（独立仓，不整仓复制进本仓）

| 仓 | 对接 |
| --- | --- |
| `agent-session-archive` | `tools/collector_cli.py`（codex/claude） |
| `ai-chat-future-activity-archiver` | companion `POST /jobs/pee-sync`（127.0.0.1） |

## 运行

```bash
# iOS
open TimeLedger.xcodeproj

# Mac Hub（安装/更新后双击）
scripts/build-evolution-hub-app
open "/Applications/Evolution Hub.app"
```

## 验证

```bash
scripts/project-check
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
cd Packages/EvolutionCore && swift test
cd EvolutionHub && swift test
```

## 边界

- 本地优先；无账号/云同步/订阅/App Store（V3）。
- 不同步 SQLite；跨端用 SyncEnvelope 文件交换（Bonjour 未做）。
- AI 复盘仅接口预留；默认确定性报告。
- iOS 生产启动、迁移协调器与 `TimeLedgerModels` 统一采用 `TimeLedgerSchemaV3`；跨端仍只交换 SyncEnvelope，不同步数据库。
- 真机签名免费 Personal Team，约 7 天有效。
