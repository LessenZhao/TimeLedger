# TimeLedger Mac（镜像账本）使用说明

Mac 端 **不能独立记账**。必须先与 iPhone **建立镜像连接**，之后两边是同一本账（项目 / 草稿 / 已确认 / 思考 / 未记录时长）。

开发约定见 `AGENTS.md`；V3 进化能力见 `003-personal-evolution-engine-v3.md`。  
分支：`feature/mac-mirror-sync`。

## 打开 / 更新

| 动作 | 做法 |
| --- | --- |
| 打开 | 应用程序 → **TimeLedger** |
| 命令行 | `open "/Applications/TimeLedger.app"` |
| 更新 | 仓库根执行 `scripts/build-evolution-hub-app`（覆盖安装） |

## 镜像连接（必须先做）

### 方式 A：局域网（推荐）

1. **Mac** 与 **iPhone** 同一 Wi‑Fi  
2. Mac：侧边栏 **连接 iPhone** → **开始等待 iPhone** → 记下 **6 位配对码**  
3. 手机：设置 → **连接 Mac 镜像** → 输入配对码 → **连接 Mac**  
4. 首次允许「本地网络」权限  
5. 成功后 Mac 显示已连接；手机可点 **立即推送全量到 Mac**  

之后：Mac「今天」记账会经局域网回写手机；手机可再推送全量刷新。

### 方式 B：文件（备用）

1. 手机：导出 **SyncEnvelope** → 传到 Mac  
2. Mac：从 SyncEnvelope 连接  
3. Mac 改账后导出回写 / 同步目录 → 手机 **导入 Mac 回写**  

断开连接会清空 Mac 本地镜像并锁定记账（避免第二本账）。

## 侧边栏结构

| 分区 | 内容 |
| --- | --- |
| 连接 iPhone | 连接/断开、同步目录、拉取/导出 |
| 今天 | 项目 / 草稿 / 已确认（与手机同构；未连接锁定） |
| 思考 | 快速记录思考（未连接锁定） |
| 复盘 | 当日统计（镜像数据） |
| 上下文 / 证据复盘 | Mac 进化能力（Collector、关联） |
| 设置 | Collector 路径 + 镜像状态 |

## 每天建议流程

```text
手机导出 SyncEnvelope → Mac 连接
  → Mac「今天」打标/确认（可选）
  → 导出或同步目录回写 → 手机导入 mac-to-phone
  →（可选）上下文：同步今日上下文 / 证据复盘
```

## 相关命令

```bash
cd Packages/EvolutionCore && swift test
cd EvolutionHub && swift test
scripts/build-evolution-hub-app
```
