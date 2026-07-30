# 008 · Layout Document 中枢：Obsidian 级阅读 + 正常选区笔记

> **状态：** UI 路线已更新；ReadingNote 平行域仍保留。2026-07-29 的 Recogito 4.2.5 固定离线 Spike 通过字体/宽度改变后的标注恢复，作为唯一生产标注内核；版本、SHA256 和许可证见 `Resources/ObsidianReader/THIRD_PARTY.md`。
> **日期：** 2026-07-28  
> **分支：** `codex/chatgpt-conversation-ledger`  
> **关系：** 继承 [007-reading-notes-parallel.md](./007-reading-notes-parallel.md) 的**笔记域与 Tab 产品边界**；**作废 007 中「整页 NSTextView / MarkdownAttributedRenderer 当主阅读器」的 UI 路径**。正式生产链仍以 [005](./005-chatgpt-conversation-ledger.md) / [006](./006-hunan-selection-prep-assets.md) 为准。

> **2026-07-28 UI 真源：** 历史会话使用一个 `WKWebView`，消息作为带 `messageId` 的 section；正式资产使用同一 Reader 的单 section 形式。`markdown-it` 离线 HTML/CSS 负责阅读与系统选区，SwiftUI 只保留外壳和笔记 sheet。本文中 TextKit、分片 L1/L2 及其 `Layout Document` 主 UI 路线均为历史记录，不得重新接回主路径。

> **执行约束（2026-07-29）：** 当前 WKWebView 路线是唯一可执行路线；本文的 Layout Document、L1/L2/L3 与 2b 是历史决策记录，不得据此重新开启并行实现。

---

## 1. 目标

用户打开同一段历史会话/正式材料正文时：

1. **阅读**与用 Obsidian 打开**同一 Markdown 正文**的观感一致（标题层级、列表、引用竖线、代码块、段距、行内样式；无叠字、无源码标记裸奔）。
2. **选择**符合系统正常逻辑：拖选 → 选区旁浮层「写笔记｜划线｜复制」→ 再选替换、点空白清除；全局唯一选区。
3. **笔记**与正式库平行：原文与正式库可记；待确认不可记；笔记库统一找回并回跳。

**让步顺序（冲突时）：读对 > 选对 > 记全。**

---

## 2. 背景与已证伪路径

### 2.1 已验证有效

- `MarkdownStructure` + `MarkdownBodyView`：块级 SwiftUI 渲染，Obsidian 结构保真，**无叠字史**（commit 基线如 `21e1e35` 前后主路径）。
- `ReadingNote` + `chatgpt-reading-notes.json` + HubStore CRUD +「笔记库」Tab：数据平行层方向正确（007）。

### 2.2 已证伪（禁止再作为主路径）

| 路径 | 失败表现 |
| --- | --- |
| 多 `NSTextView` 分片拼阅读+选择 | 非唯一选区；浮层不跟手；难对齐 Obsidian |
| 整页自绘 `NSTextView` + `fittedHeight` 硬锁高 | 叠字、鬼影、标题糊；宽度/高度未稳定时排版 |
| 用「能选字」的近似渲染替换 `MarkdownBodyView` | 阅读回归；用户明确否定 |

### 2.3 根因（第一性原理）

- **阅读**需要稳定宽度下的块级版式引擎。  
- **选择**需要单一文字表面 + 选区几何。  
- **笔记**需要原文锚点。  
三者不应挤进「一个既画又选的脆弱 TextView」。缺 **Layout Document 中枢** 时，会在「好看选不了」和「能选但炸布局」之间横跳。

---

## 3. 目标架构

```text
归档/ledger 正文（唯一内容源）
        │
        ▼
┌───────────────────────┐
│  Layout Document      │  块序列 + 每块 sourceRange + 可选几何
│  (排版中枢，无 UI)      │  display 映射表（为 L2 服务）
└───────────┬───────────┘
            │
     ┌──────┴──────┐
     ▼             ▼
  L1 Painter    L2 Selector
  Obsidian 观感   唯一选区 + 浮层
     │             │
     └──────┬──────┘
            ▼
     L3 ReadingNote 域（平行持久化 + 笔记库）
```

- **正式库生产链**（AI → 待确认 → 正式库）与 L3 **平行**，不做笔记升级正式库。  
- **只允许一个 L1 主阅读渲染器**；会话原文、正式库正文、笔记回跳落地共用。

---

## 4. 领域与文件边界

### 4.1 保留（007，勿推翻）

- `Packages/EvolutionCore/.../ReadingNote.swift`（或现名）与 `ReadingNotesFileStore`
- `EvolutionLedgerLayout.chatConversationReadingNotesFileURL` → `records/chatgpt-reading-notes.json`
- HubStore：`allNotes` / byConversation / byAsset / addHighlight / addNote / update / delete
- Tab：`会话 | 待确认 | 正式库 | 笔记库`
- 禁区：待确认无笔记写入；笔记不进 `chatgpt-ledger` 资产结构；无「收入正式库」默认路径

### 4.2 新建（本方案核心）

| 单元 | 建议路径 | 职责 |
| --- | --- | --- |
| Layout Document 模型 | `EvolutionHubCore/Markdown/MarkdownLayoutDocument.swift` | 从源 Markdown 生成块序列、每块 `sourceUTF16` 范围、块内纯文本/行内 spans；**纯数据，不依赖 View** |
| L1 适配 | 优先复用并收敛到 `MarkdownBodyView` + `MarkdownStructure` | 只消费 Layout Document 或与之等价的 parse 结果绘画 |
| L2 选区控制器 | `EvolutionHub/.../MarkdownSelectionController.swift`（+ 必要时一个 NSViewRepresentable） | 唯一选区状态、选区矩形、浮层、display→source 映射提交 |
| 组合容器 | `EvolutionHub/.../AnnotatableMarkdownReader.swift` | L1+L2 组装；`allowsNotes: Bool` |

### 4.3 降级/删除

- **主阅读路径删除依赖：** `ReadingSelectableTextBlock` 整页 NSTextView 方案、`SelectableMarkdownDocumentView` 作为主阅读器、`fittedHeight` 锁死阅读高度。
- `MarkdownAttributedRenderer`：  
  - **不得**再作为 L1 主渲染；  
  - 若 L2 需要映射辅助，可降为 layout 测试工具或删除；以 Layout Document 为准。
- 禁止恢复「摘录此段 / 摘录袋」主路径。

### 4.4 白名单（执行时可写）

- `EvolutionHub/Sources/EvolutionHubCore/Markdown/**`
- `EvolutionHub/Sources/EvolutionHub/ChatConversations/**`（阅读/选区/笔记库 UI）
- `EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift`（仅笔记 API 接线，不改候选确认语义）
- `EvolutionHub/Tests/EvolutionHubCoreTests/**`、`Packages/EvolutionCore/Tests/**`（若模型下沉 Core）
- `docs/plans/008-*.md`、`.scratch/layout-document-goal/**`

**只读：** 005/006 生产链、iOS TimeLedger、CI、密钥。

---

## 5. Layout Document 契约

```swift
struct MarkdownLayoutDocument: Sendable, Equatable {
    var source: String
    var blocks: [Block]

    struct Block: Sendable, Equatable, Identifiable {
        var id: String
        var kind: Kind           // heading(level), paragraph, listItem, code, quote, thematicBreak
        var sourceRange: RangeUTF16   // 在 source 中的 UTF-16 范围（内容语义范围，不含可剥标记时见下）
        var text: String         // 用于该块展示的核心文本（与 MarkdownBodyView 块文本一致）
        var inlineSpans: [InlineSpan] // 可选：bold/italic/code/link 在 block.text 内的范围
        // 几何：首轮可不进模型，由 L1 布局后回写 SelectionHitTest 缓存
    }

    struct RangeUTF16: Sendable, Equatable {
        var location: Int
        var length: Int
    }
}
```

**规则：**

1. `source` 与归档/消息/资产版本正文**字节级一致**（仅允许与现 parse 相同的换行规范化策略，且必须在 document 内记录）。  
2. 每个可见文本块能回答：`block.text` 在 `source` 中的定位（heading 对应标题词范围；list item 对应 item 正文；quote 对应 `>` 后正文）。  
3. L2 选区最终提交的是 **source 上的 UTF-16 range + quoteSnapshot**，不是 display 控件私有 offset。  
4. 跨消息选区 **不做**（与 007 一致）。跨 block 选区：阶段 2 先做**单 block 内**选区即可验收；阶段 2b 再做同消息多 block 连续选（可选）。

**解析实现策略：**

- 以现有 `MarkdownStructure.parse` 为行为基线（列表不分家、代码围栏等测试必须继续绿）。  
- 扩展 parse **或**并行 `MarkdownLayoutBuilder.build(source:)` 产出带 `sourceRange` 的 document；禁止行为回归。  
- 单测：给定 fixture Markdown，断言 heading/list/quote/code 的 `text` 与 `source` 切片一致。

---

## 6. L1 阅读（阶段 1，必须先过）

### 6.1 做法

1. **主路径恢复/固定为** `MarkdownBodyView`（或 100% 视觉等价的块级 SwiftUI，数据来自 Layout Document）。  
2. 会话 `messageBlock`、正式库 `ChatStudyAssetReaderPane` 正文、待确认只读原文：**全部走 L1**。  
3. `allowsNotes == false` 时：**零**选区写入 UI，仅 L1。  
4. 去掉整页 NSTextView 主阅读；禁止叠字路径残留。

### 6.2 验收（阶段 1 出门条件）

- [ ] 与 Obsidian 并排同一段「遴选备考高价值任务」类长文：标题一/二级可辨、列表为 `•`、引用有左条、**无叠字/鬼影**。  
- [ ] `MarkdownStructureTests` 全绿；Hub/Core `swift test` ≥ 执行时基线且 0 fail。  
- [ ] 主路径 `rg` 不再把 `DocumentTextView`/`fittedHeight` 用作消息正文主渲染（可残留死代码但不得挂接；建议删除挂接）。  
- [ ] 人机：快速滚动长会话无错位叠加。

**阶段 1 未出门，禁止开工阶段 2 功能宣传性 UI。**

---

## 7. L2 选区（阶段 2）

### 7.1 交互规格（产品法）

| 动作 | 结果 |
| --- | --- |
| 在允许笔记的表面上拖选非空文本 | 出现浮层：写笔记、划线、复制 |
| 浮层位置 | 锚定选区 bounding rect 上方；触顶则翻到下方；水平夹在可读区内 |
| 再次拖选另一处 | **唯一选区**切换到新处；旧高亮选区消失；浮层跟随 |
| 点击空白/零长度选区 | 清除选区与浮层 |
| 复制 | 剪贴板 = 当前选区对应的 `quoteSnapshot`（源切片文本） |
| 划线 | 立即 `addHighlight`；清除选区浮层；L1 上显示单色高亮装饰 |
| 写笔记 | 轻量 sheet（引用只读 + 正文）；不要求 kind/subtype |
| 点击已有划线/笔记高亮 | 打开编辑/删除 |

### 7.2 推荐实现（阶段 2 默认）

**在 L1 块级结构上增加「单 block 选区」——用布局命中，而不是替换 L1。**

1. 每个文本块（heading/paragraph/listItem/quote/code）在 L1 仍用与 `MarkdownBodyView` 相同的视觉组件。  
2. 块内可选用**轻量** `NSTextView`/`TextEditor` **仅包裹该块 `block.text` 的展示 attributed 字符串**，字体/颜色/行距**抄** `MarkdownBodyView` 常量；或使用 SwiftUI selection + 自定义手势（若达不到选区矩形则用前者）。  
3. **关键约束：**  
   - 同一时间只有一个 block 持有 non-empty selection（SelectionStore 单例/环境对象）。  
   - 切换 block 时清除前一 block 的 selectedRange。  
   - 浮层由 SelectionStore 发布 `anchorRect`（全局坐标）渲染在 reader 外层 `overlay`，**不要**钉在卡片右上角。  
4. 映射：`block.sourceRange.location + 块内 selected UTF16` → 全文 source range（块内字符串与 source 切片一致时最简单；不一致则用 LayoutDocument.inline map）。  
5. 高亮装饰：按 note 的 source range 落在哪些 block，在该 block 内对对应子 range 画背景。

> 若单 block 选区验收通过但用户强要求「跨标题连续拖选」，再开 **阶段 2b：同消息 Web 壳或真 Layout 共享引擎**；不要在阶段 2 重做整页 TextView 主阅读。

### 7.3 阶段 2b（可选终局，仅当 2 不够）

- WKWebView：Markdown → HTML+接近 Obsidian 的 CSS；`getSelection` + sourcemap data 属性回 source range。  
- L1/L2 合并进 Web；L3 不变。  
- 单独里程碑，不与阶段 1 打包。

### 7.4 验收（阶段 2）

- [ ] 选区行为表（§7.1）全过。  
- [ ] 浮层跟选区，不跟卡片角落。  
- [ ] 换选/点空白无残留多选区。  
- [ ] 无叠字回归（阶段 1 验收重跑）。  
- [ ] 待确认 `allowsNotes: false`：无浮层、无写入（含次级原文入口）。

---

## 8. L3 笔记与表面接线（阶段 3）

### 8.1 接线

| 表面 | L1 | L2 |
| --- | --- | --- |
| 会话原文 | ✅ | ✅ `sourceMessageSpan` |
| 正式库当前版本正文 | ✅ | ✅ `formalAssetSpan`（assetId+versionId） |
| 待确认 | ✅ | ❌ |
| 笔记库 | 列表 | 回跳打开对应表面并尽量闪选区 |

### 8.2 笔记库

- 已有 `ChatReadingNotesLibraryView`：保留；回跳必须落到 **L1 reader**，不是旧 NSTextView。  
- 筛选：全部 / 划线 / 笔记 / 会话；搜索 quote|body。  
- 徽章：原文 | 正式。

### 8.3 验收（阶段 3）

- [ ] 原文划线、原文笔记、正式库笔记、笔记库回跳、待确认无入口（007 五步）。  
- [ ] 笔记只在 `chatgpt-reading-notes.json`；ledger 无笔记 body 污染（已有单测保持）。  
- [ ] Hub/Core tests 全绿；ReadingNote 相关单测 ≥ 6（两锚点+持久化）。

---

## 9. 分阶段执行顺序（强制）

| 阶段 | 名称 | 交付 | 出门门禁 |
| --- | --- | --- | --- |
| **0** | 基线与清场清单 | 记录当前 `swift test` 数；列出将断开的 NSTextView 主路径挂接点 | 基线数字写入 PROGRESS |
| **1** | 只恢复 L1 | 主阅读 100% MarkdownBodyView（或等价）；无叠字 | §6.2 |
| **2** | L2 选区 | SelectionStore + 浮层 + 单 block 选区 + 映射写入笔记 API | §7.4 + 重跑 §6.2 |
| **3** | L3 打磨 | 双表面接线、回跳闪动、死代码清理、007 文档指针更新 | §8.3 |
| **2b** | 可选 Web 终局 | 仅当 1+2 仍达不到 Obsidian 像素级 | 单独验收 |

**禁止**并行「重写阅读器 + 新选区」同一 PR 而不分阶段验收。

---

## 10. 任务拆解（执行 agent 可直接当 checklist）

### T0 基线

```bash
cd Packages/EvolutionCore && swift test 2>&1 | tee /tmp/core-base.txt | tail -5
cd EvolutionHub && swift test 2>&1 | tee /tmp/hub-base.txt | tail -5
```

写入 `.scratch/layout-document-goal/PROGRESS.md`：Core/Hub 测试数、日期。  
`BLOCKED.md` 初始「无」。

### T1 Layout Document

- 实现 `MarkdownLayoutBuilder` / 扩展 parse，带 sourceRange。  
- 测试：heading/list/quote/code 切片 == source 子串；与 `MarkdownStructureTests` 行为兼容。  
- 验收：相关 test 绿。

### T2 L1 挂接

- `AnnotatableMarkdownReader(allowsNotes:)`：`allowsNotes false` → 纯 `MarkdownBodyView`。  
- SourceView / AssetReader / Review 只读入口全部改走该容器。  
- 拆除整页 NSTextView 主路径挂接。  
- 验收：§6.2；`scripts/build-evolution-hub-app` 可装。

### T3 SelectionStore + 浮层

- 环境对象/Observable：`activeSelection: (messageOrAsset, sourceRange, quote, anchorRect)?`  
- 唯一性、清除、浮层 overlay。  
- 验收：§7.1 人机。

### T4 块内选区 → 笔记 API

- 块内选区 → Layout 映射 → `addHighlight` / `addNote`。  
- 高亮回绘。  
- 验收：划线/笔记持久化 + 重启仍在。

### T5 正式库 + 待确认闸门

- 正式库 `allowsNotes true` + formal anchor。  
- Review 全部 `false`（含次级 SourceView）。  
- 验收：rg/审查 + 人机。

### T6 笔记库回跳

- 跳会话/正式库 + 闪 range。  
- 验收：007 五步。

### T7 清理与文档

- 删除未使用的整页 TextView 阅读死路径（若无引用）。  
- 007 文首注明 UI 以 008 为准。  
- 安装 App。

---

## 11. 测试与防回归

### 11.1 自动

```bash
cd Packages/EvolutionCore && swift test
cd EvolutionHub && swift test
```

- 测试数 ≥ T0 基线；failures = 0；禁止 skip 凑绿。  
- 必保：`MarkdownStructureTests`、`ReadingNotesStoreTests`、LayoutDocument 新测。  
- `rg "摘录此段|摘录袋" EvolutionHub/Sources` 退出码 1。

### 11.2 人机（每阶段）

1. Obsidian 并排：无叠字、H1/H2 可辨。  
2. 拖选 → 浮层在选区旁。  
3. 换选 → 只一处选中。  
4. 划线/笔记/复制。  
5. 正式库同样。  
6. 待确认无笔记。  
7. 笔记库回跳。

### 11.3 安装

```bash
scripts/build-evolution-hub-app
# 完全退出后
open "/Applications/TimeLedger.app"
```

---

## 12. 非目标

- 跨消息选区、多色标注体系、AI 自动笔记、笔记→正式库、iOS 同步、新全局依赖、改 candidate 确认语义、push/rebase。

---

## 13. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 块内选区无法跨标题 | 阶段 2 接受；2b Web |
| 块 text 与 source 切片不对齐 | Layout 单测锁切片；映射失败则不弹出写入 |
| 又用 TextView 画整页 | 门禁 §6.2；CR 拒绝 |
| 浮层坐标系错 | 统一 window 坐标；用 selection rect 测试辅助 |

---

## 14. 完成定义（整方案）

1. 阅读：Obsidian 并排无叠字，层级清楚（阶段 1 持续成立）。  
2. 选择：§7.1 全过。  
3. 笔记：007 平行域 + 五步人机 + 自动测试门禁。  
4. 架构：存在 Layout Document（或等价 builder）；L1/L2/L3 边界清晰；主路径无整页自绘 TextView 阅读器。

---

## 15. 执行时进度文件

- `.scratch/layout-document-goal/PROGRESS.md`  
- `.scratch/layout-document-goal/BLOCKED.md`  

每完成 Ti 更新 PROGRESS；阻塞只写 BLOCKED，不中断无关任务。
