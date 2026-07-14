# TimeLedger

iOS 原生个人时间账本：SwiftUI + SwiftData 实现柳比谢夫时间记录法的低摩擦记录与思考卡片。  
V3 起作为 **Personal Evolution Engine** 的时间事实端；Mac 端工作台为 **Evolution Hub**。

## 项目地图

- iOS：`TimeLedger/`（`Models/`、`Services/`、`Views/`、`Utilities/`）；测试 `TimeLedgerTests/`、`TimeLedgerUITests/`
- 协议包：`Packages/EvolutionCore`（Codable DTO、关联、标准化、复盘、SyncBatch）
- Mac Hub：`EvolutionHub/`（SPM + SwiftUI）；产物 `/Applications/Evolution Hub.app`
- 计划：`docs/plans/initial-build.md`、`docs/plans/003-personal-evolution-engine-v3.md`
- 优先查看：`AGENTS.md`、`PROJECT_STATE.md`、`docs/project-overview.md`、`docs/evolution-hub-usage.md`
- 不要默认读取：`build/`、`dist/`、`*.xcuserstate`、DerivedData、`.build/`、日志与生成文件

核心不是“开始/结束计时器”，而是：连续时间流、`TimeCursor`、快捷打标、草稿修正、确认锁定、本地导出、ThoughtNote 按时间点自动关联 TimeEntry。  
V3 跨端：iOS 导出 SyncEnvelope 文件 → Hub 导入；Hub 调独立 Collector；不直接同步 SQLite/SwiftData 文件。

## 目录与规则源

- 项目文件放在本项目目录内；新目录先说明用途与清理边界。
- `AGENTS.md` 是唯一规则源；`CLAUDE.md` → `AGENTS.md` 符号链接，不双写。
- 修改规则时：先改 `AGENTS.md`，再按新规则执行。
- `.agentdesk/` 仅用于按需 Agent 临时工作文件；方案事实源放在 `docs/plans/`。
- 不把密钥、token、密码写入代码、日志或提交记录。
- App 源码在 `TimeLedger/` 下按 `Models/`、`Services/`、`Views/`、`Utilities/` 分层；`Views/Thoughts/` 存放思考卡片。
- Hub 与 EvolutionCore 用独立 SPM；**不手写或伪造 Xcode 工程文件**；iOS 工程由 Xcode 维护。
- 按当前任务读取最小上下文；验证优先最小充分证据；`xcodebuild` 过滤 `BUILD SUCCEEDED|BUILD FAILED|error:`。
- 本地优先；不加入登录、云账号、App Store、订阅、多端 CRDT、把全部原文塞进 SwiftData。
- `ThoughtNote`：`anchorAt` 自动关联；`linkSource = manual` 不被自动覆盖。
- `confirmed` TimeEntry 锁定时间段，仍可增删改关联 ThoughtNote。
- 时间统计用本地自然日；`duration` 由 `startAt`/`endAt` 计算。
- `draft` 可改可删；`confirmed` 须先取消确认再改时间/删除。
- 保存前校验：`endAt > startAt`、项目有效、时间不重叠；空档允许。
- EvidenceLink 手动确认/拒绝不被后续自动算法覆盖。
- Collector 独立仓调用；参数用 Process 数组，不拼不可信 shell 字符串。
- 删除用 `trash`，不用 `rm`（可进废纸篓）。

## 验证

```bash
# iOS
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS'

# EvolutionCore / Hub
cd Packages/EvolutionCore && swift test
cd EvolutionHub && swift test

# 安装/覆盖更新 Mac 应用 → /Applications/Evolution Hub.app
scripts/build-evolution-hub-app
```

本机无 iPhone 16 模拟器时用 `iPhone 17`。缺 Simulator runtime 先记阻塞，不改业务代码绕过。  
现场骨架检查（仅维护现场时）：`scripts/project-check`

## 现场文档

模板默认静默：未明确要求更新现场、交接、恢复、收尾时，不自动更新 `PROJECT_STATE.md`、`CHANGELOG.md`，不跑 `project-check`。  
只有用户明确要求更新现场、做交接、恢复现场、收尾或维护项目状态时，才维护这些现场文档。

## 方案

- `docs/plans/*.md` 是可执行方案目录。
- 需要跨 Agent 执行时，直接执行对应方案文件。
- `生成方案` / `执行方案` / `验收执行` 的细则由个人 `execution-plan` Skill 维护。
- `PROJECT_STATE.md` 只记录当前执行现场和方案来源，不保存方案正文。

## 红线

以下操作必须先获得用户明确确认：

- 删除文件、目录或 git 历史（删除用 `trash`，不用 `rm`）
- 修改 `.env`、密钥、token、CI/CD 配置
- 数据库 schema 变更或数据迁移
- `git push`、`git rebase`、`git reset --hard`、强制推送
- 安装新的全局依赖或修改系统配置
- 公开发布
