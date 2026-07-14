# 项目主线

status: active
plan_type: initial
updated_at: 2026-07-13

## 当前目标

V1+V2+V3 本地 MVP 已交付。日常用 iOS 记事实 + `/Applications/Evolution Hub.app` 同步上下文与复盘。  
细节：`003-personal-evolution-engine-v3.md`、`docs/evolution-hub-usage.md`。

## 阶段

### V1

| 阶段 | 状态 | 目标 | 验收 |
| --- | --- | --- | --- |
| 0 | done | Xcode 工程、项目规则和路线图 | `scripts/project-check`；`xcodebuild -list` |
| 1 | done | 基础数据与首页快速记录 | 模型、服务、首页、快速记录、撤销 |
| 2 | done | 草稿编辑与时间页 | 长按调整、TimeListView、TimeEntryEditView、draft 删除和编辑 |
| 3 | done | 确认状态机 | draft/confirmed 转换、取消确认、confirmed 锁定时间 |
| 4 | done | 自然日统计与重叠校验 | overlap 统计正确；时间重叠禁止；时间空档允许 |
| 5 | done | Review 和导出 | 日/周/月统计；CSV、JSON、Markdown 导出 |
| 6 | done | 打磨与测试 | 空状态、错误提示、项目管理、单元测试和构建验证 |

### V2 — ThoughtNote 思考卡片

| 阶段 | 状态 | 目标 |
| --- | --- | --- |
| 0 | done | 项目审计、schema 风险评估、git 分支 |
| 1 | done | ThoughtNote 模型 + ThoughtLinkingService 基础服务 + 12 条单元测试 |
| 2 | done | TodayView 想法入口 + ThoughtQuickCaptureSheet |
| 3 | done | 新建 TimeEntry 后自动吸附 ThoughtNote |
| 4 | done | TimeListView 思考数量 + TimeEntryEditView 关联思考区 |
| 5 | done | ThoughtDayView 今日思考卡片流 |
| 6 | done | 导出增强（JSON/Markdown/CSV 包含 ThoughtNote） |
| 7 | done | ReviewView 今日思考分布 |
| 8 | done | 回归测试：44 单元 + 3 UI 全部通过 |

### V3 — Personal Evolution Engine

| 阶段 | 状态 | 目标 |
| --- | --- | --- |
| 0 | done | 仓库审计、协议与 EvolutionCore Codable 契约 |
| 1 | done | Evolution Hub macOS 最小工作台 |
| 2 | done | iPhone ↔ Mac 文件 SyncEnvelope 交换 |
| 3 | done | 一键同步 Codex / Claude（collector_cli） |
| 4 | done | ChatGPT companion /jobs/pee-sync + 等待浏览器 |
| 5 | done | 标准化与 EvidenceLink 自动/建议/手动 |
| 6 | done | 确定性有证据每日复盘 + Git 摘要 |

### Mac 镜像（进行中 · `feature/mac-mirror-sync`）

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 连接门控 + 镜像引擎 | done | 未连接不可记账；断开清空镜像 |
| 今天 项目/草稿/已确认 | done | Mac 布局同构；草稿可编辑时间 |
| 文件双向回写 | done | SyncEnvelope + mac-to-phone 导入 |
| 局域网镜像 | done | Bonjour `_timeledger-mirror._tcp` + 配对码 |

## 后续方向

- 完成局域网自动镜像；再评估 V4 目标与周期、更多 Collector 等。

## 暂不做（V3 边界）

- 登录、云同步、订阅系统、App Store、商业化。
- 标签系统、双链、知识图谱、富文本编辑器。
- 图片/语音/文件附件、OCR、社交分享。
- Apple Watch、小组件（V3 不做）。
- 直接同步 SQLite / 整仓复制归档项目进 TimeLedger。
