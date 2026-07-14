# Personal Evolution Engine V3 实施计划

> 来源：`Personal_Evolution_Engine_V3_Implementation_Plan.md`  
> 目标仓库：TimeLedger（本仓）+ 外部 Collector 仓  
> 原则：不推倒重写 iOS App；按 V3.0→V3.6 分阶段；每阶段独立构建/测试/验收。

updated_at: 2026-07-12  
current_stage: V3.0–V3.6 implemented (local-first MVP)

---

## 0. 审计结论（2026-07-12）

### 0.1 TimeLedger（本仓）

| 项 | 现状 |
| --- | --- |
| 技术 | SwiftUI + SwiftData iOS App |
| 模型 | `Project`、`TimeCursor`、`TimeEntry`、`ThoughtNote`、`AppSettings` |
| 能力 | 连续时间流、草稿/确认、自然日统计、日/周/月 Review、CSV/JSON/Markdown 导出、ThoughtNote 时间点关联 |
| 导出 JSON | `version: 1`，含 projects / timeEntries / thoughtNotes / settings；时间为 ISO8601 |
| 测试 | `TimeLedgerTests` + `TimeLedgerUITests`；scheme 仅 `TimeLedger` |
| 缺失 | 无 macOS target、无 EvolutionCore、无 Context* 模型、无跨端同步、无 Collector 调用 |

**可复用：** TimeEntry / ThoughtNote 事实模型、自然日边界、`ExportService.exportJSON`、Validation / Summary 服务、现有测试基线。  
**不碰：** 现有 SwiftData schema（V3.0 不迁移）。

### 0.2 agent-session-archive

路径：`/Users/lessen/coding/test/agent-session-archive`

| 项 | 现状 |
| --- | --- |
| 入口 | `tools/archive_codex_clean_transcripts.py`、`tools/archive_claude_clean_transcripts.py` |
| 输出 | `events.jsonl`、`threads-index.jsonl`、`views/`、`assets/`、`_system/` cache |
| 元数据 | thread_id、cwd、created_at/updated_at、source_file、model（Codex） |
| 增量 | 源文件 cache；**输出 JSONL 为整文件覆盖写** |
| 时间窗 | 仅 `--since YYYY-MM`，无日级 ISO 区间；Codex/Claude 过滤语义不一致 |
| 时区 | Codex 多为 `Z`，Claude 多为 `+08:00`（文档与实现不完全一致） |
| Result | 人类 Markdown 报告，**无机器可读 CollectorResult** |

**可复用：** 解析内核、events/threads-index 形态、源 cache。  
**V3.3 需补：** 薄 CLI wrapper、`--start-at/--end-at`、result JSON、禁止 since 覆盖全量 vault。

### 0.3 ai-chat-future-activity-archiver

路径：`/Users/lessen/coding/test/ai-chat-future-activity-archiver`

| 项 | 现状 |
| --- | --- |
| 架构 | 浏览器扩展（登录态）+ companion `127.0.0.1:18795` |
| 输出 | `_archive-index.json` + `YYYY-MM-DD--title.md` + `images/` |
| 增量 | manifest + message id 差集 |
| Job | 单 current job，扩展主驱动 |
| 缺失 | pairing token、Hub 发起任务、按 job 指定 archiveRoot、CollectorResult |

**可复用：** companion 写盘、manifest、MD 格式。  
**V3.4 需补：** Hub→companion job 参数化、扩展认领、等待浏览器状态。

### 0.4 需要修改的仓库

| 阶段 | 仓库 |
| --- | --- |
| V3.0 | TimeLedger（文档 + EvolutionCore Package） |
| V3.1 | TimeLedger（macOS target + UI 壳） |
| V3.2 | TimeLedger（iOS 导出 SyncEnvelope + Hub 导入） |
| V3.3 | agent-session-archive + TimeLedger Hub 调用 |
| V3.4 | ai-chat-future-activity-archiver + TimeLedger Hub |
| V3.5–V3.6 | TimeLedger EvolutionCore + Hub |

### 0.5 Schema 风险

1. **TimeLedger SwiftData：** V3 不得直接改现有模型字段；新实体先 Codable DTO，绑定 SwiftData 另开确认。  
2. **Session 归档时区不一致：** 标准化层必须统一为带时区 ISO8601。  
3. **ChatGPT MD 无严格 schemaVersion：** 标准化适配器需兼容。  
4. **禁止同步 SQLite/SwiftData 文件：** 只用 SyncEnvelope。  
5. **去重：** 优先 `source + externalId`；缺失时 `source + sourcePath + sourceLine + contentHash`。

---

## 1. 产品边界（不重设计）

沿用总方案：

```text
目标 → 行动 → 事实证据 → 结果 → 复盘 → 调整 → 下一轮验证
```

- TimeLedger iOS：用户确认的时间事实与 ThoughtNote  
- Evolution Hub macOS：Collector 编排、Raw Vault、关联、复盘  
- Collector 独立仓：采集与稳定协议，不改 TimeLedger DB  
- AI 不得改写原始数据；结论可追溯证据  

V3 不做：云账号、App Store、商业化同步、浏览器全历史、知识图谱、因果自动证明。

---

## 2. 本地数据目录（约定）

默认：

```text
~/Library/Application Support/PersonalEvolutionEngine/
├── raw/{codex,claude,chatgpt}/
├── normalized/
├── database/
├── sync/
├── config/
└── logs/
```

- 可配置；不进 Git  
- 日志不写完整隐私正文  
- 单源失败不阻塞其他源  

---

## 3. EvolutionCore 协议（V3.0 落地）

Package 路径：`Packages/EvolutionCore`

### 3.1 DTO

- `ContextSource`
- `ContextThread` / `ContextMessage` / `ContextEvent`
- `EvidenceLink`（method / userState / confidence）
- `DailyReview`
- `SyncEnvelope`
- `CollectorRequest` / `CollectorResult`
- `RawVaultLayout`、`ContentHasher`、`DeduplicationKey`、`NaturalDayWindow`、`ISO8601Codec`

### 3.2 时间规则

- 内部统一 ISO 8601 **带时区**  
- 展示用本地时区  
- 每日同步按本地自然日  
- “当天会话”= 当天创建 **或** 当天更新 **或** 当天有新消息（不能只看文件 mtime / createdAt）  

### 3.3 去重规则

1. `source + externalId`  
2. `source + message externalId`  
3. 缺失：`source + sourcePath + sourceLine + contentHash`  

### 3.4 schemaVersion

当前 DTO：`schemaVersion = 1`（常量 `EvolutionSchema.current`）。

---

## 4. 分阶段路线（执行边界）

| 阶段 | 分支建议 | 目标 | 验收要点 |
| --- | --- | --- | --- |
| **V3.0** | `feature/v3.0-core-contracts` | 审计、协议、EvolutionCore | Package 单测绿；幂等/时间边界；iOS 回归绿 |
| **V3.1** | `feature/v3.1-hub-shell` | macOS 最小工作台 | 时间线/收件箱/复盘/设置；JSON 导入与手动关联 |
| **V3.2** | `feature/v3.2-device-sync` | iPhone↔Mac 文件交换→局域网 | SyncEnvelope；不直接拷 DB |
| **V3.3** | `feature/v3.3-codex-claude` | 一键 Codex/Claude | Process 调 CLI；result JSON；幂等 |
| **V3.4** | `feature/v3.4-chatgpt` | Hub 发起 ChatGPT job | 等待浏览器；不伪装完成 |
| **V3.5** | `feature/v3.5-linking` | 标准化与 EvidenceLink | 自动/建议/收件箱；手动不被覆盖 |
| **V3.6** | `feature/v3.6-review` | 有证据每日复盘 | 无 AI 也可用；证据可追溯 |

**禁止** 跨阶段并行大改；每阶段先测试再进入下一阶段。

---

## 5. V3.0 文件清单

```text
docs/plans/003-personal-evolution-engine-v3.md   # 本文件
Packages/EvolutionCore/
  Package.swift
  Sources/EvolutionCore/
    EvolutionSchema.swift
    ContextSource.swift
    ContextThread.swift
    ContextMessage.swift
    ContextEvent.swift
    EvidenceLink.swift
    DailyReview.swift
    SyncEnvelope.swift
    CollectorRequest.swift
    CollectorResult.swift
    ISO8601Codec.swift
    NaturalDayWindow.swift
    ContentHasher.swift
    DeduplicationKey.swift
    ImportDeduper.swift
    RawVaultLayout.swift
  Tests/EvolutionCoreTests/
    DTOCodingTests.swift
    NaturalDayWindowTests.swift
    DeduplicationTests.swift
    SyncEnvelopeTests.swift
    RawVaultLayoutTests.swift
```

**不修改：** 现有 `TimeLedger/` SwiftData 模型、Xcode 工程 targets（V3.0 不手写 pbxproj；Package 独立 `swift test`）。

---

## 6. 验证命令

### EvolutionCore

```bash
cd Packages/EvolutionCore && swift test
```

### iOS 回归（不得退化）

```bash
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS'
```

---

## 7. 红线（执行前确认）

- 删除文件/历史  
- 数据库 schema 变更或迁移  
- 改密钥 / CI  
- `git push` / rebase / reset --hard  
- 安装全局依赖  
- 公开发布  

V3.0 **不涉及** schema 迁移与删除。

---

## 8. V3.1 落地说明

独立 SPM macOS App（避免手写主工程 pbxproj）：

```text
EvolutionHub/
  Package.swift
  Sources/EvolutionHubCore/   # 导入、手动关联、HubStore
  Sources/EvolutionHub/       # SwiftUI 四页
  Tests/EvolutionHubCoreTests/
  SampleData/                 # 手工导入样例
```

运行：

```bash
cd EvolutionHub && swift run EvolutionHub
cd EvolutionHub && swift test
```

验收已满足：时间线 / 收件箱 / 复盘 / 设置；TimeLedger JSON + ContextEvent JSON 导入；手动关联并展示 rawReference。

## 9. V3.2–V3.6 落地摘要（2026-07-12）

| 阶段 | 落地 |
| --- | --- |
| V3.2 | iOS `SyncEnvelopeExportService` + 导出 UI；Hub 导入 SyncBatch + revision 幂等合并；冲突记日志；无 SQLite 直拷；局域网 Bonjour **未做**（文件交换为正式路径） |
| V3.3 | `agent-session-archive/tools/collector_cli.py`；Hub `SessionCollectorClient` Process 调用 |
| V3.4 | companion `POST /jobs/pee-sync`（waitingForBrowser + archiveRoot）；Hub 不伪装完成 |
| V3.5 | Codex/Claude/ChatGPT adapters；LinkingEngine；手动优先不被覆盖 |
| V3.6 | DeterministicReviewProvider；事实等级；GitEvidenceAdapter 轻量摘要；明日调整写 `sync/next-adjustment-*.json` |

### 运行

```bash
# 构建并安装/覆盖更新系统应用（/Applications/Evolution Hub.app）
scripts/build-evolution-hub-app
open "/Applications/Evolution Hub.app"

# 开发/测试
cd Packages/EvolutionCore && swift test
cd EvolutionHub && swift test
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 已知限制

- 无 Bonjour 局域网实时同步（V3.2 第二段未做）
- ChatGPT 仍需浏览器扩展认领 job；扩展侧认领逻辑为最小 API，完整自动认领可继续增强
- 明日调整回手机为文件交换，非 SwiftData 新模型（避免 schema 迁移红线）
- AI ReviewProvider 接口已预留，默认仅确定性报告

## 10. 明确不做（V3 全文）

全量人生监控、自动因果、复杂图谱、整仓复制归档项目进 TimeLedger、直接同步 SQLite、依赖单一 AI 模型、无价值聊天框。
