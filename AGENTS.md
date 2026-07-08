# TimeLedger

## 项目定位

TimeLedger 是一个 iOS 原生个人时间账本，用 SwiftUI + SwiftData 实现柳比谢夫时间记录法的低摩擦记录流程。

核心不是“开始/结束计时器”，而是：

- 连续时间流
- `TimeCursor` 表示上一段时间归档结束位置
- 常用项目右侧快捷打标
- 草稿修正
- 确认锁定
- 本地导出复盘数据

## 目录规则

- 项目文件必须放在本项目目录内。
- 新目录先说明用途、命名和清理边界。
- `AGENTS.md` 是唯一规则源；`CLAUDE.md` 应指向 `AGENTS.md`，不单独维护内容。
- 不把密钥、token、密码写入代码、日志或提交记录。
- `.agentdesk/` 只用于按需跨 Agent 执行交接；没有 handoff 任务时不要创建或维护。
- App 源码放在 `TimeLedger/` 下，按 `Models/`、`Services/`、`Views/`、`Utilities/` 分层。
- 单元测试放在 `TimeLedgerTests/`，UI 测试放在 `TimeLedgerUITests/`。
- 不手写或伪造 Xcode 工程文件；工程结构由 Xcode 维护，必要时用 Xcode 或 `xcodebuild` 验证。

## 现场文档边界

本项目带有最小现场文档模板，但模板默认静默。

同一种信息只保留一个主要事实来源：

- 项目规则、红线、验证命令：`AGENTS.md`
- 当前项目阶段、当前任务、未完成项、接手恢复：`PROJECT_STATE.md`
- 已完成的历史变更、版本记录、验证摘要：`CHANGELOG.md`
- 当前系统结构、运行方式、架构说明：`docs/project-overview.md`
- 项目主线阶段地图：`docs/plans/000-roadmap.md`

用户未明确要求更新现场、交接或恢复时：

- 不自动更新 `PROJECT_STATE.md`。
- 不自动更新 `CHANGELOG.md`。
- 不自动运行 `scripts/project-check`。
- 不把普通任务包装成现场维护流程。

只有用户明确要求更新现场、做交接、恢复现场、收尾或维护项目状态时，才更新这些现场文档。

## 跨 Agent 执行交接

当任务需要由 Codex 规划、Claude Code 执行、再由 Codex 审核时，可以创建 `.agentdesk/HANDOFF.md`。

- `.agentdesk/HANDOFF.md` 是当前这一轮执行的临时 handoff contract。
- 它必须自包含，让执行 Agent 不依赖完整聊天记录也能执行。
- 它应包含目标、背景、已定决策、允许范围、禁止变更、执行步骤、验收标准、验证命令、停止条件和最终报告格式。
- 它不替代 `PROJECT_STATE.md`、`CHANGELOG.md` 或 `docs/plans/`。
- 小任务可以直接用一句明确指令交给执行 Agent，不必创建 handoff 文件。
- 任务完成后的长期事实，仍按本项目主要事实来源写回对应文件。

## 开发规则

- 按当前任务需要读取最小上下文。
- 修改规则时，先改 `AGENTS.md`，再按新规则执行。
- 涉及代码、配置或用户可见行为时，完成前运行必要验证。
- 不为了跑通而注释掉报错或绕过失败，先定位根因。
- 本 App 本地优先；第一版不加入登录、云同步、订阅、AI 总结、复杂计划系统、多级分类树、小组件或 Apple Watch。
- 时间统计一律使用本地自然日 `00:00:00 - 24:00:00`，跨天记录统计和导出必须按自然日 overlap 切分。
- `duration` 由 `startAt` / `endAt` 计算，不把保存的分钟数字作为唯一真实来源。
- `draft` 记录可改时间和删除；`confirmed` 记录普通模式下锁定时间且不可普通删除，必须先取消确认。
- 任何保存、编辑、确认前都要校验 `endAt > startAt`、项目有效、时间不重叠；时间空档允许存在。

## 验证

项目现场结构检查：

```bash
scripts/project-check
```

项目业务验证：

```bash
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS'
```

如果本机缺少 iOS Simulator runtime，先记录该阻塞；不要为了绕过验证而改业务代码。

## 红线

以下操作必须先获得用户明确确认：

- 删除文件、目录或 git 历史
- 修改 `.env`、密钥、token、CI/CD 配置
- 数据库 schema 变更或数据迁移
- `git push`、`git rebase`、`git reset --hard`、强制推送
- 安装新的全局依赖或修改系统配置
- 公开发布
