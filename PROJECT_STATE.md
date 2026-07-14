# 项目状态

updated_at: 2026-07-12  
current_version: 0.3.1-mirror

## 当前阶段

V3 MVP 已落地。正在 **`feature/mac-mirror-sync`**：Mac 为手机镜像账本（未连接不可记账；连接后今天/思考同构；文件双向回写）。  
App 安装名：**`/Applications/TimeLedger.app`**。

## 当前任务

当前问题：Mac 镜像第一期可用；局域网实时同步未做。  
方案来源：用户确认「连接后镜像、不独立记账」。  
当前方案：MirrorLedgerEngine + 文件 SyncEnvelope 闭环；Bonjour 后续。  
已完成：镜像引擎与单测；Mac 侧边栏今天/思考/复盘/连接；iOS 导出含 TimeCursor + 导入 mac-to-phone；安装 TimeLedger.app。  
正在进行：暂无（本轮可交付试用）。  
下一步：真机局域网联调；手机改账自动推送增量（现支持全量推送 + Mac 改账回写）。  
涉及文件：

- `Packages/EvolutionCore/MirrorLedger*.swift`
- `EvolutionHub/` Mirror UI + `MirrorSessionController`
- `TimeLedger/Services/MirrorSyncImportService.swift`
- `scripts/build-evolution-hub-app`

验收清单：

| 项 | 状态 | 证据 |
| --- | --- | --- |
| V1 时间记录 | done | CHANGELOG 0.1.0 |
| V2 ThoughtNote | done | CHANGELOG 0.2.0 |
| V3 EvolutionCore/Hub | done | `swift test`；CHANGELOG 0.3.0 |
| Hub 系统应用 | done | `/Applications/Evolution Hub.app`；`scripts/build-evolution-hub-app` |
| iOS 回归 | done | xcodebuild test iPhone 17 |

状态：暂无活跃开发任务。

## 未完成项

- 无 Bonjour 局域网实时同步（文件交换为正式路径）。
- ChatGPT 扩展侧自动认领 pee job 可继续增强。
- 明日调整回手机为 Hub `sync/next-adjustment-*.json`，未进 SwiftData。
- GitHub 远程仓库尚未绑定。
- 真机需信任开发者证书。

## 接手恢复

1. 读 `AGENTS.md`、`docs/project-overview.md`、`docs/evolution-hub-usage.md`。  
2. 读本文件与 `docs/plans/003-personal-evolution-engine-v3.md`。  
3. `git status --short`；当前功能分支多为 `feature/v3.1-hub-shell`。  
4. 验证：  
   - iOS：`xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17'`  
   - Core：`cd Packages/EvolutionCore && swift test`  
   - Hub：`cd EvolutionHub && swift test`  
   - 更新 App：`scripts/build-evolution-hub-app`  
5. 打开 Hub：`open "/Applications/Evolution Hub.app"`  
