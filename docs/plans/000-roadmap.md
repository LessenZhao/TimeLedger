# 项目主线

## 当前目标

完成 TimeLedger 第一版：本地 SwiftUI + SwiftData App，支持连续时间流、快捷记录、草稿修正、确认锁定、自然日统计和数据导出。

## 阶段

| 阶段 | 状态 | 目标 | 验收 |
| --- | --- | --- | --- |
| 0 | done | Xcode 工程、项目规则和路线图 | `scripts/project-check`；`xcodebuild -list` |
| 1 | blocked | 基础数据与首页快速记录 | 代码已落地；等待 iOS 26.5 platform 可用后构建/测试 |
| 2 | planned | 草稿编辑与时间页 | 长按调整、TimeListView、TimeEntryEditView、draft 删除和编辑 |
| 3 | planned | 确认状态机 | draft/confirmed 转换、取消确认、confirmed 锁定时间和禁止普通删除 |
| 4 | planned | 自然日统计与重叠校验 | overlap 统计正确；时间重叠禁止；时间空档允许 |
| 5 | planned | Review 和导出 | 日/周/月基础统计；CSV、JSON、Markdown 导出 |
| 6 | planned | 打磨与测试 | 空状态、错误提示、长时间未记录提醒、单元测试和构建验证 |

## 后续方向

- 在第一版稳定后，再评估是否需要小组件、Apple Watch、多设备同步或更复杂报表。

## 暂不做

- 登录、云同步、订阅系统、AI 总结。
- 复杂计划页、复杂二级分类树、OCR、社交分享。
- Apple Watch、小组件、多设备同步。
