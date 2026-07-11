# TimeLedger

iOS 原生个人时间账本：SwiftUI + SwiftData 实现柳比谢夫时间记录法的低摩擦记录与思考卡片。

## 项目地图

- 主要代码：`TimeLedger/`（`Models/`、`Services/`、`Views/`、`Utilities/`）；测试在 `TimeLedgerTests/`、`TimeLedgerUITests/`
- 优先查看：`AGENTS.md`、`PROJECT_STATE.md`、`docs/project-overview.md`、`docs/plans/000-roadmap.md`
- 不要默认读取：`build/`、`*.xcuserstate`、DerivedData、日志与生成文件

核心不是“开始/结束计时器”，而是：连续时间流、`TimeCursor` 归档结束位置、常用项目右侧快捷打标、草稿修正、确认锁定、本地导出、ThoughtNote 按时间点自动关联 TimeEntry。

## 目录与规则源

- 项目文件放在本项目目录内；新目录先说明用途与清理边界。
- `AGENTS.md` 是唯一规则源；`CLAUDE.md` → `AGENTS.md` 符号链接，不双写。
- 修改规则时：先改 `AGENTS.md`，再按新规则执行。
- `.agentdesk/` 仅用于按需跨 Agent 交接；无 handoff 任务时不创建。
- 不把密钥、token、密码写入代码、日志或提交记录。
- App 源码在 `TimeLedger/` 下按 `Models/`、`Services/`、`Views/`、`Utilities/` 分层；`Views/Thoughts/` 存放思考卡片相关页面。
- 单元测试在 `TimeLedgerTests/`，UI 测试在 `TimeLedgerUITests/`。
- 不手写或伪造 Xcode 工程文件；工程结构由 Xcode 维护，必要时用 Xcode 或 `xcodebuild` 验证。
- 按当前任务读取最小上下文；验证优先最小充分证据（pass/fail、关键 error）；`xcodebuild` 默认管道过滤 `| rg 'BUILD SUCCEEDED|BUILD FAILED|error:'`。
- 感知通道按成本升级：CLI / 日志 / 测试报告优先于截图；能命令行完成的不截图。
- 涉及代码、配置或用户可见行为时，完成前运行必要验证；不为了跑通而注释报错或绕过失败。
- 本地优先；第一版不加入登录、云同步、订阅、AI 总结、复杂计划系统、多级分类树、小组件或 Apple Watch。
- `ThoughtNote` 通过 `anchorAt` 自动关联到覆盖该时间点的 `TimeEntry`；`linkSource = manual` 不被自动关联覆盖。
- `confirmed` TimeEntry 锁定时间段，但仍允许添加、编辑、删除关联 ThoughtNote。
- 时间统计一律使用本地自然日 `00:00:00 - 24:00:00`，跨天记录统计和导出必须按自然日 overlap 切分。
- `duration` 由 `startAt` / `endAt` 计算，不把保存的分钟数字作为唯一真实来源。
- `draft` 记录可改时间和删除；`confirmed` 记录普通模式下锁定时间且不可普通删除，必须先取消确认。
- 任何保存、编辑、确认前都要校验 `endAt > startAt`、项目有效、时间不重叠；时间空档允许存在。

## 验证

```bash
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS'
```

本机无 iPhone 16 模拟器，验证时用 `iPhone 17`。若缺少 iOS Simulator runtime，先记录阻塞，不要为绕过验证改业务代码。

现场骨架检查（仅在用户要求维护现场 / 新建验收时）：`scripts/project-check`

## 现场文档

模板默认静默：未明确要求更新现场、交接、恢复、收尾时，不自动更新 `PROJECT_STATE.md`、`CHANGELOG.md`，不跑 `project-check`。
只有用户明确要求更新现场、做交接、恢复现场、收尾或维护项目状态时，才维护这些现场文档。
事实来源表与细则：工作区 `.agents/guides/template-boundaries.md`（相对 `test/`）。

## 跨 Agent 交接

需要时创建 `.agentdesk/HANDOFF.md`。
入口：工作区 `.agents/templates/execution-handoff.md`；权威模板在个人 `execution-handoff` Skill。
handoff 须自包含；不替代 `PROJECT_STATE.md`、`CHANGELOG.md` 或 `docs/plans/`；小任务可用一句明确指令，不必建文件。

## 红线

以下操作必须先获得用户明确确认：

- 删除文件、目录或 git 历史（删除用 `trash`，不用 `rm`）
- 修改 `.env`、密钥、token、CI/CD 配置
- 数据库 schema 变更或数据迁移
- `git push`、`git rebase`、`git reset --hard`、强制推送
- 安装新的全局依赖或修改系统配置
- 公开发布
