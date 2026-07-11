# 项目主线

## 当前目标

V1+V2 已交付：连续时间流、快捷记录、草稿修正、确认锁定、自然日统计、数据导出，以及 ThoughtNote 自动时间关联。当前无新主线开发。

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

## 后续方向

- 在 V2 稳定后，再评估是否需要小组件、Apple Watch、多设备同步或更复杂报表。

## 暂不做

- 登录、云同步、订阅系统、AI 总结。
- 标签系统、双链、知识图谱、富文本编辑器。
- 图片/语音/文件附件、OCR、社交分享。
- Apple Watch、小组件、多设备同步。
