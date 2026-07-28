# 湖南省直遴选备考资产升级实施方案

> **供执行 Agent 使用：** 本方案只能在用户明确选择执行方式后实施。持久化账本从 schema v1 升级到 schema v2 前，必须再次取得用户对“备份并迁移现有数据”的明确确认。所有步骤使用复选框（`- [ ]`）跟踪。

**目标：** 将现有“ChatGPT 会话片段 + 结论账本”升级为只服务湖南省直遴选的备考资产系统：每个会话有清楚的片段目录；范文、背诵模块等内容能够逐字保存；策略和观点能够提炼；AI 候选和用户手动摘录进入同一正式备考库；所有资产可返回原文上下文并保留版本关系。

**架构：** 保留 `005-chatgpt-conversation-ledger.md` 已建立的结构化归档、用户选择、不可变任务、显式 Skill、候选确认、消息增量和回执链路。新方案把正式结果从单一 `finding` 升级为“片段目录 + 有类型的备考资产 + 不可变版本”；AI 只选择原文块或生成提炼候选，原文正文由 App 从不可变任务直接截取和校验，不能由模型重新誊写。

**技术栈：** Swift 5.9、Foundation、SwiftUI、AppKit `NSTextView`、Codable JSON、现有 `ContentHasher`、原子文件写入与文件锁、Markdown Skill、Python 3 标准库验证脚本。

## 全局约束

- 该工作区只服务湖南省直遴选；凡是用户主动选择进入处理任务的会话，都按本方案处理，不增加内容领域自动识别。
- “主题”“内容类型”“用途”“产生方式”是不同维度，不能混成一套标签。
- 一级内容类型固定为：`完整成品`、`表达模块`、`素材证据`、`方法策略`、`观点知识`；二级类型使用非空自由文本，例如“范文”“开头段”“湖南案例”。
- “待背诵、可仿写、可引用、待实践、重点复习”是用途，不是内容类型；一个资产可以有多个用途。
- “AI 识别、用户手动摘录、用户修改”是产生方式，不是内容类型。
- 保存策略只有 `原文` 和 `提炼`。`原文`必须逐字符等于任务中的来源范围；`提炼`必须保留来源引用。
- 原文资产的正文不能由 Skill 输出；Skill 只能返回不可变任务中的来源块 ID，App 负责直接截取、拼接、哈希和保存。
- schema v2 正式资产同时保存正文快照和来源定位。归档缺失或变化时仍显示已确认快照，并明确标记来源状态，不能静默替换。
- 同一资产的修改产生新版本；旧版本不删除。用户确认或修改后的资产锁定，后续 Skill 不能覆盖。
- 一个候选资产必须直接属于一个会话片段；主题从片段推导，不在资产中重复保存。
- 跨会话汇总只做视图投影。V1 不生成跨会话综合结论，不把多个会话自动合成为一个新资产。
- AI 候选必须逐项可接受、拒绝或修改；用户在原文中手动选择的内容可以作为用户权威直接写入正式备考库。
- 所有输入消息仍必须由一个会话片段覆盖，或者被明确忽略并说明原因；资产数量可以为零。
- 只有正式账本与回执都成功写入后，消息版本才算已处理；失败、拒绝和重复执行不得污染增量状态。
- App 不调用 Codex CLI/API；用户继续在 Codex 中显式执行 `$chatgpt-ledger process <job-id>`。
- 不修改 `ai-chat-future-activity-archiver`。它现有的 `conversationId + messageId + content + contentHash` 能满足本次升级。
- 不引入数据库、SwiftData、向量库、Embedding、知识图谱、自动背诵计划、自动事实核验、iPhone 页面或多领域规则系统。
- 未经单独确认，不迁移正式数据、不安装覆盖 `/Applications/TimeLedger.app`、不 push、不公开发布。

---

## 与旧方案的关系

- 旧方案：[005-chatgpt-conversation-ledger.md](./005-chatgpt-conversation-ledger.md)。
- 旧方案继续作为以下基础能力的事实源：
  - 结构化 ChatGPT 归档；
  - 用户选择会话；
  - 只处理新增或变化的消息版本；
  - App 生成不可变任务；
  - 用户显式运行 Skill；
  - Skill 只写候选；
  - App 确认后原子写正式账本和回执；
  - 按会话和按主题使用同一份正式数据。
- 本方案只替代旧方案中的以下语义和实现：
  - `findings` 单一结论模型；
  - 片段只有消息引用、没有目录标题和说明；
  - 所有结果都要求“简洁结论”；
  - 只能给结论加重点和备注；
  - 只能按会话和主题查看，不能按资产类型与用途查看；
  - 原文查看器只能阅读，不能手动选择并加入备考库。
- 若两份方案冲突，归档、增量、任务、回执边界按旧方案；片段目录、备考资产、原文保存、版本、人工摘录和备考库界面按本方案。

## 已核对的实施基线

核对日期：2026-07-27。执行时必须重新检查，不得把下列状态当成永久事实。

- TimeLedger 当前分支为 `codex/chatgpt-conversation-ledger`，已有会话读取、任务、候选、正式账本、来源查看和两种投影。
- `agent-skill-governance` 当前分支为 `codex/chatgpt-ledger-skill`，`chatgpt-ledger` 仍是显式调用 Skill。
- 归档器当前分支有用户未提交改动；本方案不修改该仓库。
- 本机正式账本当前是 schema v1，含 3 个主题、3 个片段、3 条结论和 1 条 accepted 回执。
- 当前 schema v1 的片段没有标题和摘要；`finding` 只有正文和消息级来源；原文页只有文本选择能力，没有持久化选择。

## 领域与数据契约

### 分类维度

| 维度 | 固定值或规则 | 示例 |
| --- | --- | --- |
| 一级内容类型 `kind` | `finishedWork`、`expressionModule`、`sourceMaterial`、`methodStrategy`、`viewpointKnowledge` | 完整成品 |
| 二级类型 `subtype` | 非空自由文本，用户可修改 | 范文、开头段、湖南案例 |
| 用途 `uses` | `memorize`、`imitate`、`quote`、`practice`、`review`，可多选 | 待背诵、可仿写 |
| 保存策略 `preservation` | `verbatim` 或 `distilled` | 原文、提炼 |
| 产生方式 `origin` | `skill`、`userSelection`、`userEdited` | AI识别、人工摘录 |

### 核心正式对象

```swift
public enum ChatStudyAssetKind: String, Codable, Sendable, Hashable, CaseIterable {
    case finishedWork
    case expressionModule
    case sourceMaterial
    case methodStrategy
    case viewpointKnowledge
}

public enum ChatStudyAssetUse: String, Codable, Sendable, Hashable, CaseIterable {
    case memorize
    case imitate
    case quote
    case practice
    case review
}

public enum ChatStudyAssetPreservation: String, Codable, Sendable, Hashable {
    case verbatim
    case distilled
}

public enum ChatStudyAssetOrigin: String, Codable, Sendable, Hashable {
    case skill
    case userSelection
    case userEdited
}

public enum ChatConversationSourceStatus: String, Sendable, Hashable {
    case current
    case changed
    case unavailable
    case legacyUnscoped
}

public struct ChatConversationSourceSpan: Codable, Sendable, Hashable {
    public var message: ChatConversationMessageReference
    public var contentHash: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var textHash: String
}

public struct ChatStudyAssetVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var textSnapshot: String
    public var textHash: String
    public var preservation: ChatStudyAssetPreservation
    public var origin: ChatStudyAssetOrigin
    public var sourceMessages: [ChatConversationMessageReference]
    public var sourceSpans: [ChatConversationSourceSpan]
    public var supersedesVersionId: String?
    public var createdAt: String
}

public struct ChatStudyAsset: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var segmentId: String
    public var title: String
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var versions: [ChatStudyAssetVersion]
    public var currentVersionId: String
    public var isHighlighted: Bool
    public var note: String?
    public var isUserLocked: Bool
}

public struct ChatConversationLedgerDocument: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var topics: [ChatConversationTopic]
    public var segments: [ChatConversationSegment]
    public var assets: [ChatStudyAsset]
    public var processedRevisions: [ChatConversationProcessedRevision]
    public var receipts: [ChatConversationReceipt]
    public var updatedAt: String
}
```

以上所有 public struct 都必须提供覆盖全部字段的 public initializer；`ChatConversationLedgerDocument.empty` 固定创建 `schemaVersion == 2` 的空文档。

### 片段目录

`ChatConversationSegment` 增加：

```swift
public var title: String
public var summary: String
```

片段标题回答“这一段做了什么”，主题回答“它属于哪个长期主题”。后续回到同一主题时建立新片段，不覆盖旧片段。

### 原文来源块

每条不可变任务消息增加按原始换行切分的来源块：

```swift
public struct ChatConversationTaskSourceBlock: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var locationUTF16: Int
    public var lengthUTF16: Int
    public var text: String
    public var textHash: String
}
```

块的 `text` 必须包含原来的换行字符。按顺序拼接一条消息的所有块，必须逐字符等于原消息正文。

任务中的现有资产只暴露匹配和版本判断所需信息：

```swift
public struct ChatConversationTaskAsset: Codable, Sendable, Hashable {
    public var id: String
    public var segmentId: String
    public var title: String
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var currentText: String
    public var isUserLocked: Bool
}

public struct ChatConversationTaskMessage: Codable, Sendable, Hashable {
    public var conversationId: String
    public var messageId: String
    public var role: ChatConversationRole
    public var createdAt: String
    public var content: String
    public var contentHash: String
    public var contextOnly: Bool
    public var sourceBlocks: [ChatConversationTaskSourceBlock]
}

public struct ChatConversationProcessingTask: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var jobId: String
    public var createdAt: String
    public var selectedConversationIDs: [String]
    public var inputMessages: [ChatConversationTaskMessage]
    public var existingTopics: [ChatConversationTaskTopic]
    public var existingAssets: [ChatConversationTaskAsset]
    public var sourceDigest: String
    public var baseLedgerDigest: String
}
```

### 候选资产

```swift
public struct ChatConversationProposalAsset: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var segmentId: String
    public var title: String
    public var kind: ChatStudyAssetKind
    public var subtype: String
    public var uses: Set<ChatStudyAssetUse>
    public var preservation: ChatStudyAssetPreservation
    public var draftText: String?
    public var sourceBlockIDs: [String]
    public var sourceSpans: [ChatConversationSourceSpan]
    public var replacesAssetID: String?
    public var origin: ChatStudyAssetOrigin
}

public struct ChatConversationProposalSegment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var topicTarget: ChatConversationTopicTarget
    public var sourceMessages: [ChatConversationMessageReference]
}

public struct ChatConversationDuplicateAssetMatch: Codable, Sendable, Hashable {
    public var existingAssetId: String
    public var sourceBlockIDs: [String]
}

public struct ChatConversationProposal: Codable, Sendable, Hashable {
    public var jobId: String
    public var sourceDigest: String
    public var baseLedgerDigest: String
    public var segments: [ChatConversationProposalSegment]
    public var assets: [ChatConversationProposalAsset]
    public var duplicateMatches: [ChatConversationDuplicateAssetMatch]
    public var ignoredMessages: [ChatConversationIgnoredMessage]
}
```

- Skill 生成的 `verbatim`：`draftText == nil`、`sourceSpans` 为空，来源块必须来自同一条 assistant 消息中的连续范围。
- App 中的人工选择：`draftText == nil`、`sourceBlockIDs` 为空、`sourceSpans` 只包含用户刚刚确认的精确选择。
- `distilled`：`draftText` 非空，来源块非空；正文可以与来源不同。
- Skill 只能输出 `origin == .skill`。
- 用户编辑提炼正文后，App 改为 `origin == .userEdited` 并锁定正式资产。
- 用户手动选择原文时，App 直接构造 `origin == .userSelection`。
- `replacesAssetID` 只表示建议的新版本；旧版本不会被删除。
- Skill inbox 文件中的 `sourceSpans` 必须为空，防止模型伪造“用户手动选择”；只有 App 内存中的用户操作可以增加精确人工范围。

## 文件职责图

### TimeLedger / EvolutionCore

- 修改 `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationDomain.swift`
  - schema v2 正式对象、资产分类、版本和精确来源范围。
- 修改 `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationExchange.swift`
  - schema v2 任务来源块、现有资产摘要、候选片段和候选资产。
- 新建 `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationSourceBlockBuilder.swift`
  - 从原消息生成可逆的 UTF-16 来源块。
- 新建 `Packages/EvolutionCore/Sources/EvolutionCore/ChatStudyAssetMaterializer.swift`
  - 从任务来源块确定性生成原文快照和来源范围。
- 新建 `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedgerMigration.swift`
  - schema v1 检测、备份路径和 v1 → v2 纯函数迁移。
- 修改 `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedger.swift`
  - schema v2 任务、候选校验、资产应用、版本追加、用户资产写入和幂等回执。
- 新建对应测试：
  - `ChatConversationSourceBlockBuilderTests.swift`
  - `ChatStudyAssetMaterializerTests.swift`
  - `ChatConversationLedgerMigrationTests.swift`
- 修改 `ChatConversationLedgerTests.swift`。

### TimeLedger / EvolutionHubCore

- 修改 `EvolutionHub/Sources/EvolutionHubCore/Models/ChatConversationEvidencePresentation.swift`
  - 解析来源范围、来源变化状态、片段到资产关系。
- 新建 `EvolutionHub/Sources/EvolutionHubCore/Models/ChatStudyAssetPresentation.swift`
  - 会话、主题、类型三种投影和过滤。
- 修改 `EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift`
  - 候选逐项编辑、排除、确认、迁移状态、人工资产和版本操作。
- 修改对应 Store 与 Presentation 测试。

### TimeLedger / EvolutionHub

- 修改 `ChatConversationReviewView.swift`
  - 候选片段目录、候选资产类型、用途、保存策略和逐项接受。
- 修改 `ChatConversationLedgerView.swift`
  - “正式账本”改为“湖南省直遴选备考库”，增加按类型投影和版本查看。
- 修改 `ChatConversationSourceView.swift`
  - 返回上下文、来源高亮和手动加入备考库。
- 新建 `SelectableSourceTextView.swift`
  - AppKit 文本选择和 UTF-16 范围回传。
- 新建 `ChatStudyAssetCard.swift`
  - 候选与正式资产共用的正文、标签、用途、来源和版本展示。
- 新建 `ChatStudyAssetEditorSheet.swift`
  - 手动摘录和用户修改时填写标题、类型、二级类型和用途。

### agent-skill-governance

- 修改 `skills/chatgpt-ledger/SKILL.md`
  - 湖南省直遴选分类、片段目录、原文块选择、提炼资产、版本建议和覆盖规则。
- 修改 `skills/chatgpt-ledger/agents/openai.yaml`
  - 展示说明改为“生成可核查的湖南省直遴选备考资产候选”。
- 新建 `skills/chatgpt-ledger/scripts/validate_candidate.py`
  - 使用 Python 标准库验证 schema v2 候选。
- 新建 `tests/test_chatgpt_ledger_candidate.py`
  - 验证原文资产不能携带模型生成正文、来源块必须真实存在、输入覆盖完整。

### 测试夹具约定

计划中的测试辅助函数使用以下固定签名，放在各自测试文件底部，不能在生产 target 中增加测试专用 API：

```swift
private func makeTask(assistantContent: String) -> ChatConversationProcessingTask
private func makeLegacyLedgerData() throws -> Data

private extension ChatConversationHubFixture {
    func makeStoreWithCandidate(assetCount: Int) throws -> ChatConversationHubStore
    func makeStoreWithAcceptedAsset(kind: ChatStudyAssetKind) throws -> ChatConversationHubStore
}
```

- `makeTask` 固定生成一条 user 输入和一条 assistant 回复，两条都是 non-context，assistant 的 `sourceBlocks` 由正式 builder 生成。
- `makeLegacyLedgerData` 使用测试文件内的 private schema v1 Codable fixture 生成一套主题、片段、finding、mark、processed revision 和 accepted receipt。
- `makeStoreWithCandidate` 写入一条会话、一个任务、一个片段和指定数量的候选资产，再刷新并选中该候选。
- `makeStoreWithAcceptedAsset` 复用前一个 helper，确认候选后返回 store。
- Python 测试在 `tests/test_chatgpt_ledger_candidate.py` 中定义 `make_task()` 和 `make_candidate()`；二者返回完整 schema v2 dict，不从真实用户目录读取数据。

## 执行前硬闸门

- [ ] **Step 1：重新核对三个仓库**

```bash
git -C /Users/lessen/coding/test/TimeLedger status --short --branch
git -C /Users/lessen/coding/test/ai-chat-future-activity-archiver status --short --branch
git -C /Users/lessen/coding/test/agent-skill-governance status --short --branch
```

预期：TimeLedger 和 Skill 位于各自现有功能分支；归档器的用户改动保持原样且不进入本方案 diff。

- [ ] **Step 2：只读取正式账本元数据**

```bash
jq '{schemaVersion, topicCount: (.topics|length), segmentCount: (.segments|length), findingCount: ((.findings // [])|length), receiptCount: (.receipts|length)}' '/Users/lessen/Documents/Personal Evolution/records/chatgpt-ledger.json'
```

预期：得到可记录的迁移前计数，不输出会话正文。

- [ ] **Step 3：核对是否存在非终态候选**

读取 inbox 文件名、对应任务 ID 和正式回执状态，不读取与本任务无关的原文。accepted、rejected 或 noOp 对应的残留 inbox 文件不是待确认候选。

- [ ] **Step 4：取得持久化迁移授权**

在用户明确同意前，只实现和测试迁移代码，不对 `/Users/lessen/Documents/Personal Evolution/records/chatgpt-ledger.json` 执行备份或写入。

---

## Task 1：建立分类、版本和可逆来源块

**阶段结果：** Core 能表达片段目录和备考资产；任意消息切成来源块后可以逐字符重组，不改变空格、标点或换行。

**Files:**
- Modify: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationDomain.swift`
- Modify: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationExchange.swift`
- Create: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationSourceBlockBuilder.swift`
- Create: `Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationSourceBlockBuilderTests.swift`

**Interfaces:**
- Produces: `ChatStudyAssetKind`、`ChatStudyAssetUse`、`ChatStudyAssetPreservation`、`ChatStudyAssetOrigin`
- Produces: `ChatConversationSourceSpan`、`ChatStudyAssetVersion`、`ChatStudyAsset`
- Produces: `ChatConversationSourceBlockBuilder.blocks(conversationId:message:)`
- Produces: schema v2 `ChatConversationTaskMessage.sourceBlocks`

- [ ] **Step 1：写来源块失败测试**

```swift
func testSourceBlocksRecomposeChineseTextWithoutNormalization() {
    let message = ChatConversationMessage(
        id: "assistant-1",
        role: .assistant,
        createdAt: "2026-07-27T00:00:00Z",
        content: "标题\r\n\r\n第一段。\n第二段末尾保留空格  \n"
    )

    let blocks = ChatConversationSourceBlockBuilder().blocks(
        conversationId: "conversation-1",
        message: message
    )

    XCTAssertEqual(blocks.map(\.text).joined(), message.content)
    XCTAssertEqual(blocks.map(\.locationUTF16), blocks.map(\.locationUTF16).sorted())
    XCTAssertTrue(blocks.allSatisfy { ContentHasher.hash($0.text) == $0.textHash })
}
```

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test --filter ChatConversationSourceBlockBuilderTests
```

预期：FAIL，提示 `ChatConversationSourceBlockBuilder` 未定义。

- [ ] **Step 3：增加 schema v2 类型**

按本方案“领域与数据契约”中的完整声明修改 Domain；同时把 `ChatConversationSegment` 初始化器改为强制接收 `title` 和 `summary`，避免执行者遗漏目录信息。

- [ ] **Step 4：实现可逆来源块**

实现要求：

```swift
public struct ChatConversationSourceBlockBuilder: Sendable {
    public init() {}

    public func blocks(
        conversationId: String,
        message: ChatConversationMessage
    ) -> [ChatConversationTaskSourceBlock] {
        let source = message.content as NSString
        guard source.length > 0 else { return [] }

        var result: [ChatConversationTaskSourceBlock] = []
        var cursor = 0
        var index = 0

        while cursor < source.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0)
            )
            let range = NSRange(location: lineStart, length: lineEnd - lineStart)
            let text = source.substring(with: range)
            result.append(ChatConversationTaskSourceBlock(
                id: "\(conversationId):\(message.id):line-\(index)",
                locationUTF16: range.location,
                lengthUTF16: range.length,
                text: text,
                textHash: ContentHasher.hash(text)
            ))
            cursor = lineEnd
            index += 1
        }

        return result
    }
}
```

- [ ] **Step 5：补 Codable 往返测试并运行 Core 全测**

验证 schema v2 任务含来源块、资产 `uses` 能稳定编码、版本顺序保持不变。

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test
```

预期：全部 EvolutionCore 测试 PASS。

- [ ] **Step 6：本地提交**

```bash
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationDomain.swift
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationExchange.swift
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationSourceBlockBuilder.swift
git add Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationSourceBlockBuilderTests.swift
git commit -m "feat: model Hunan selection study assets"
```

---

## Task 2：提供可恢复的 schema v1 → v2 迁移

**阶段结果：** 现有结论账本可以先备份再无损迁移；主题、片段、结论正文、重点、备注、处理版本和回执全部保留。

**Files:**
- Create: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedgerMigration.swift`
- Modify: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedger.swift`
- Create: `Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationLedgerMigrationTests.swift`

**Interfaces:**
- Produces: `ChatConversationLedgerSchemaState`
- Produces: `ChatConversationLedgerMigrator.inspect(data:)`
- Produces: `ChatConversationLedgerMigrator.migrateV1(data:migratedAt:)`
- Produces: `ChatConversationLedger.migrateLegacyLedger(backupURL:)`

```swift
public enum ChatConversationLedgerSchemaState: Sendable, Equatable {
    case missing
    case current
    case requiresV1Migration
    case unsupported(Int)
}
```

- [ ] **Step 1：写迁移守恒失败测试**

测试夹具必须包含 1 个主题、1 个片段、1 条 finding、1 条 mark、1 条 processed revision 和 1 条 accepted receipt。

```swift
func testMigratesV1FindingToLockedDistilledAssetWithoutLosingReceipts() throws {
    let legacy = try makeLegacyLedgerData()
    let migrated = try ChatConversationLedgerMigrator().migrateV1(
        data: legacy,
        migratedAt: "2026-07-27T00:00:00Z"
    )

    XCTAssertEqual(migrated.schemaVersion, 2)
    XCTAssertEqual(migrated.topics.count, 1)
    XCTAssertEqual(migrated.segments.count, 1)
    XCTAssertEqual(migrated.assets.count, 1)
    XCTAssertEqual(migrated.assets[0].kind, .viewpointKnowledge)
    XCTAssertEqual(migrated.assets[0].subtype, "历史结论")
    XCTAssertEqual(migrated.assets[0].versions[0].textSnapshot, "旧版正式结论")
    XCTAssertEqual(migrated.assets[0].versions[0].preservation, .distilled)
    XCTAssertTrue(migrated.assets[0].isHighlighted)
    XCTAssertEqual(migrated.assets[0].note, "保留备注")
    XCTAssertEqual(migrated.processedRevisions.count, 1)
    XCTAssertEqual(migrated.receipts.map(\.status), [.accepted])
}
```

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test --filter ChatConversationLedgerMigrationTests
```

预期：FAIL，提示 migrator 未定义。

- [ ] **Step 3：实现纯函数迁移**

固定映射：

- v1 topic 原样保留。
- v1 segment 的 `title` 使用所属 topic 名称；`summary` 固定为“由旧版会话账本迁移；打开原文查看完整上下文。”
- 每条 v1 finding 生成一个 `viewpointKnowledge / 历史结论 / review` 资产。
- 资产第一版使用 finding 正文，`preservation = .distilled`，`origin = .skill`。
- v1 只有消息级引用，因此迁移版本保留 `sourceMessages`，`sourceSpans = []`，不得伪造精确范围。
- v1 mark 映射到资产的 `isHighlighted` 和 `note`。
- `processedRevisions`、`receipts`、`updatedAt` 原样保留。
- 不接受未知的 schemaVersion；遇到大于 2 的版本必须停止。

- [ ] **Step 4：实现显式备份后迁移**

`migrateLegacyLedger(backupURL:)` 的顺序必须是：

1. 读取原文件；
2. 判断确实为 v1；
3. 使用 `.atomic` 写入用户指定的备份文件；
4. 重新读取备份并确认哈希等于原文件；
5. 纯函数迁移并编码 v2；
6. 原子替换正式账本；
7. 重新加载并验证计数守恒。

任一步失败都不能删除原文件或备份。

- [ ] **Step 5：运行迁移测试与 Core 全测**

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test --filter ChatConversationLedgerMigrationTests
swift test
```

预期：迁移测试和 Core 全测 PASS；测试只使用临时目录，不接触真实账本。

- [ ] **Step 6：本地提交**

```bash
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedgerMigration.swift
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedger.swift
git add Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationLedgerMigrationTests.swift
git commit -m "feat: migrate chat ledger to study assets"
```

---

## Task 3：让任务、候选和正式写入支持原文资产

**阶段结果：** Skill 只能引用真实来源块；App 能确定性生成原文快照，拒绝伪造、错序、跨消息或被改写的原文候选。

**Files:**
- Modify: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationExchange.swift`
- Create: `Packages/EvolutionCore/Sources/EvolutionCore/ChatStudyAssetMaterializer.swift`
- Modify: `Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedger.swift`
- Modify: `EvolutionHub/Sources/EvolutionHubCore/Import/ChatConversationProposalInbox.swift`
- Create: `Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatStudyAssetMaterializerTests.swift`
- Modify: `Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationLedgerTests.swift`
- Modify: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationProposalInboxTests.swift`

**Interfaces:**
- Produces: schema v2 `ChatConversationProcessingTask.existingAssets`
- Produces: schema v2 `ChatConversationProposal.assets`
- Produces: `ChatStudyAssetMaterializer.materialize(_:task:createdAt:)`
- Produces: `ChatConversationLedger.appendUserVersion(assetID:text:sourceMessages:sourceSpans:)`

- [ ] **Step 1：写原文物化失败测试**

```swift
func testVerbatimAssetUsesTaskBlocksInsteadOfModelDraftText() throws {
    let task = makeTask(
        assistantContent: "申论范文\n第一段。\n第二段。\n"
    )
    let assistant = try XCTUnwrap(task.inputMessages.first { $0.role == .assistant })
    let candidate = ChatConversationProposalAsset(
        id: "asset-1",
        segmentId: "segment-1",
        title: "扩大内需范文",
        kind: .finishedWork,
        subtype: "范文",
        uses: [.memorize, .imitate],
        preservation: .verbatim,
        draftText: nil,
        sourceBlockIDs: assistant.sourceBlocks.map(\.id),
        sourceSpans: [],
        replacesAssetID: nil,
        origin: .skill
    )

    let version = try ChatStudyAssetMaterializer().materialize(
        candidate,
        task: task,
        createdAt: "2026-07-27T00:00:00Z"
    )

    XCTAssertEqual(version.textSnapshot, assistant.content)
    XCTAssertEqual(version.textHash, ContentHasher.hash(assistant.content))
    XCTAssertFalse(version.sourceSpans.isEmpty)
}
```

再增加拒绝测试：

- `verbatim` 带 `draftText`；
- 来源块不存在；
- 来源块来自 user 消息；
- 来源块来自两条不同消息；
- 来源块顺序错误或不连续；
- `distilled` 正文为空；
- 资产引用的 `segmentId` 不存在；
- `replacesAssetID` 指向用户锁定资产。

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test --filter ChatStudyAssetMaterializerTests
```

预期：FAIL，提示 materializer 未定义。

- [ ] **Step 3：实现物化器**

物化器必须：

- 只从 task 建立 `blockID → (message, block)` 索引；
- 对 `verbatim` 检查同一 assistant 消息、连续 UTF-16 范围、无重复块；
- 使用来源块 `text` 直接拼接正文；
- 对 App 添加的 `.userSelection` 候选使用 `sourceSpans` 从 task 消息重新截取；范围、contentHash 和 textHash 任一不匹配都拒绝；
- 不调用 `trimmingCharacters`、Markdown 渲染或模型；
- 为每个块生成包含消息 contentHash、UTF-16 范围和 textHash 的 `ChatConversationSourceSpan`；
- 对 `distilled` 使用用户确认后的 `draftText`，但仍保留来源消息和范围；
- 生成稳定版本 ID：新资产为 `<asset-id>-v1`，替换资产按现有版本数量递增。

- [ ] **Step 4：把现有 `finding` 流程替换为 `assets`**

关键验证关系：

```swift
for asset in proposal.assets {
    guard proposal.segments.contains(where: { $0.id == asset.segmentId }) else {
        throw ChatConversationLedgerError.missingSegment(asset.segmentId)
    }
}
```

`ChatConversationProposalInbox.readPending()` 必须额外拒绝任何 `origin != .skill` 或 `sourceSpans` 非空的磁盘候选。App 读取后在内存中进行的用户修改可以产生 `.userEdited` 或 `.userSelection`；Core apply 接受三种 origin，但仍重新校验正文和来源。

消息覆盖仍由 `segments + ignoredMessages` 决定。用户排除某个候选资产后，只要片段仍覆盖输入消息，就允许确认任务。

- [ ] **Step 5：验证替换只追加版本**

测试必须证明：

- 新版本 `supersedesVersionId` 指向旧 current version；
- 旧版本仍在 `versions`；
- `currentVersionId` 只在确认成功后更新；
- 重复 apply 返回 noOp，不追加第二个版本；
- 用户锁定资产拒绝 Skill 自动替换。

- [ ] **Step 6：运行 Core 全测**

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test
```

预期：全部 PASS。

- [ ] **Step 7：本地提交**

```bash
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationExchange.swift
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatStudyAssetMaterializer.swift
git add Packages/EvolutionCore/Sources/EvolutionCore/ChatConversationLedger.swift
git add EvolutionHub/Sources/EvolutionHubCore/Import/ChatConversationProposalInbox.swift
git add Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatStudyAssetMaterializerTests.swift
git add Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationLedgerTests.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationProposalInboxTests.swift
git commit -m "feat: materialize traceable study assets"
```

---

## Task 4：升级显式 `chatgpt-ledger` Skill

**阶段结果：** Skill 能生成片段目录和有类型的备考资产；范文与背诵模块只引用来源块，策略与观点输出带来源的提炼正文。

**Files:**
- Modify: `/Users/lessen/coding/test/agent-skill-governance/skills/chatgpt-ledger/SKILL.md`
- Modify: `/Users/lessen/coding/test/agent-skill-governance/skills/chatgpt-ledger/agents/openai.yaml`
- Create: `/Users/lessen/coding/test/agent-skill-governance/skills/chatgpt-ledger/scripts/validate_candidate.py`
- Create: `/Users/lessen/coding/test/agent-skill-governance/tests/test_chatgpt_ledger_candidate.py`

**Interfaces:**
- Consumes: schema v2 `ChatConversationProcessingTask`
- Produces: schema v2 `ChatConversationProposal`
- Preserves: exact command `$chatgpt-ledger process <job-id>`

- [ ] **Step 1：写候选验证脚本失败测试**

测试数据至少覆盖：

```python
def test_verbatim_asset_rejects_model_body(self):
    task = make_task()
    candidate = make_candidate()
    candidate["assets"][0]["preservation"] = "verbatim"
    candidate["assets"][0]["draftText"] = "模型重新抄写的范文"
    errors = validate_candidate(task, candidate)
    self.assertIn("verbatim asset must not contain draftText", errors)

def test_distilled_asset_requires_source_blocks(self):
    task = make_task()
    candidate = make_candidate()
    candidate["assets"][0]["preservation"] = "distilled"
    candidate["assets"][0]["sourceBlockIDs"] = []
    errors = validate_candidate(task, candidate)
    self.assertIn("asset source blocks must not be empty", errors)
```

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/agent-skill-governance
python3 -m unittest tests.test_chatgpt_ledger_candidate -v
```

预期：FAIL，提示验证模块不存在。

- [ ] **Step 3：实现纯标准库验证器**

验证器必须检查：

- 根字段严格为 `jobId/sourceDigest/baseLedgerDigest/segments/assets/duplicateMatches/ignoredMessages`；
- task 与 proposal 的三个摘要字段完全相同；
- 所有非 contextOnly 消息恰好被片段或忽略项覆盖一次；
- 片段只属于一个会话，标题和摘要非空；
- 资产指向真实片段；
- 一级类型、用途、保存策略和 origin 属于固定枚举；
- 所有 sourceBlockIDs 存在于非 contextOnly task 输入；
- Skill 候选的 `sourceSpans` 必须为空；
- 原文资产只使用同一 assistant 消息的连续块，且 `draftText` 为 null；
- 提炼资产 `draftText` 非空；
- Skill 产出的 origin 只能是 `skill`；
- 替换目标存在且未锁定；
- 候选 ID 唯一。

- [ ] **Step 4：重写 Skill 处理规则**

Skill 的固定处理顺序：

1. 校验 schema v2 任务和终态回执；
2. 按用户意图切片：新问题或新交付物开始新片段，同一内容的连续修改保持同片段；
3. 为片段生成具体标题和一句话摘要；
4. 识别一级类型、二级类型、用途和保存策略；
5. 范文、完整答题稿、背诵模块、规范表述只选择来源块；
6. 策略、方法、观点可以生成提炼正文；
7. 一个完整交付物后面没有修改意见时，把该完整回复作为当前候选 v1，但不能绕过用户确认；
8. 后续出现完整新稿时可建议替换旧版本；只有局部修改时不得伪装成完整原文版本；
9. 对用户锁定资产只允许新建旁支候选，不允许自动替换；
10. 运行验证脚本；
11. 通过后原子发布 inbox JSON，不修改正式账本和回执。

候选 JSON 使用以下核心形状：

```json
{
  "jobId": "job-1",
  "sourceDigest": "source-digest",
  "baseLedgerDigest": "ledger-digest",
  "segments": [
    {
      "id": "job-1-segment-01",
      "title": "完整范文与修改",
      "summary": "围绕同一道题生成并修改完整范文。",
      "topicTarget": {
        "kind": "new",
        "id": "job-1-topic-01",
        "name": "湖南省直遴选写作训练"
      },
      "sourceMessages": [
        {
          "conversationId": "conversation-1",
          "messageId": "assistant-1"
        }
      ]
    }
  ],
  "assets": [
    {
      "id": "job-1-asset-01",
      "segmentId": "job-1-segment-01",
      "title": "扩大内需完整范文",
      "kind": "finishedWork",
      "subtype": "范文",
      "uses": ["memorize", "imitate"],
      "preservation": "verbatim",
      "draftText": null,
      "sourceBlockIDs": [
        "conversation-1:assistant-1:line-0",
        "conversation-1:assistant-1:line-1"
      ],
      "sourceSpans": [],
      "replacesAssetID": null,
      "origin": "skill"
    }
  ],
  "duplicateMatches": [],
  "ignoredMessages": []
}
```

- [ ] **Step 5：运行治理仓验证**

```bash
cd /Users/lessen/coding/test/agent-skill-governance
python3 -m unittest discover -s tests -v
scripts/check
```

预期：全部 PASS；`chatgpt-ledger` 仍属于 manual，`allow_implicit_invocation` 仍为 false。

- [ ] **Step 6：本地提交**

```bash
git add skills/chatgpt-ledger/SKILL.md
git add skills/chatgpt-ledger/agents/openai.yaml
git add skills/chatgpt-ledger/scripts/validate_candidate.py
git add tests/test_chatgpt_ledger_candidate.py
git commit -m "feat: generate Hunan selection study assets"
```

---

## Task 5：提供逐项候选检查和三种正式投影

**阶段结果：** 用户先看到会话片段目录，再逐项核对资产；同一正式资产可按会话、主题和类型查看，不复制三份数据。

**Files:**
- Modify: `EvolutionHub/Sources/EvolutionHubCore/Models/ChatConversationEvidencePresentation.swift`
- Create: `EvolutionHub/Sources/EvolutionHubCore/Models/ChatStudyAssetPresentation.swift`
- Modify: `EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift`
- Modify: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationReviewView.swift`
- Create: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatStudyAssetCard.swift`
- Modify: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift`
- Modify: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationEvidencePresentationTests.swift`

**Interfaces:**
- Produces: `ChatConversationConversationProjection.assets`
- Produces: `ChatConversationTopicProjection.assets`
- Produces: `ChatConversationKindProjection`
- Produces: candidate edit and inclusion methods on `ChatConversationHubStore`

- [ ] **Step 1：写 Store 投影和逐项排除失败测试**

```swift
@MainActor
func testCandidateCanExcludeOneAssetWithoutDroppingSegmentCoverage() throws {
    let store = try makeStoreWithCandidate(assetCount: 2)
    let candidate = try XCTUnwrap(store.selectedCandidate)

    try store.setCandidateAssetIncluded(
        jobID: candidate.jobId,
        assetID: candidate.assets[0].id,
        isIncluded: false
    )
    let receipt = try store.confirmCandidate(jobID: candidate.jobId)

    XCTAssertEqual(receipt.status, .accepted)
    XCTAssertEqual(store.ledgerDocument.segments.count, 1)
    XCTAssertEqual(store.ledgerDocument.assets.count, 1)
}

@MainActor
func testOneAssetAppearsInConversationTopicAndKindProjections() throws {
    let store = try makeStoreWithAcceptedAsset(kind: .finishedWork)
    let assetID = try XCTUnwrap(store.ledgerDocument.assets.first?.id)

    XCTAssertEqual(store.formalConversationProjections.flatMap(\.assets).map(\.id), [assetID])
    XCTAssertEqual(store.topicProjections.flatMap(\.assets).map(\.id), [assetID])
    XCTAssertEqual(store.kindProjections.flatMap(\.assets).map(\.id), [assetID])
}
```

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversationHubStoreTests
```

预期：FAIL，提示资产投影或 inclusion API 不存在。

- [ ] **Step 3：实现 Store 候选编辑**

固定 API：

```swift
public func setCandidateSegmentMetadata(
    jobID: String,
    segmentID: String,
    title: String,
    summary: String
) throws

public func setCandidateAssetIncluded(
    jobID: String,
    assetID: String,
    isIncluded: Bool
) throws

public func updateCandidateAsset(
    jobID: String,
    assetID: String,
    title: String,
    kind: ChatStudyAssetKind,
    subtype: String,
    uses: Set<ChatStudyAssetUse>,
    draftText: String?
) throws
```

用户修改 `draftText` 时把 origin 改为 `.userEdited`。原文资产正文只读；如范围不对，用户通过来源选择重新建立候选资产。

- [ ] **Step 4：改造候选页**

每个候选主题按以下顺序显示：

1. 片段标题；
2. 片段一句话摘要；
3. 所属会话、轮次和来源数量；
4. 资产数量；
5. 每张资产卡的类型、二级类型、用途、原文/提炼、AI/人工、正文预览；
6. 逐项“纳入本次确认”开关；
7. 原文资产显示只读快照预览，提炼资产允许编辑正文；
8. 打开原文上下文。

“确认写入”只提交被纳入的资产，但提交全部片段与明确忽略项。

- [ ] **Step 5：实现三种投影**

`ChatStudyAssetPresentation` 只持有资产 ID 和展示所需派生数据，不复制资产正文。按类型投影使用 `ChatStudyAssetKind.allCases` 的固定顺序，空类型默认不显示。

- [ ] **Step 6：运行 Hub 测试**

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversation
```

预期：全部 ChatConversation 测试 PASS。

- [ ] **Step 7：本地提交**

```bash
git add EvolutionHub/Sources/EvolutionHubCore/Models/ChatConversationEvidencePresentation.swift
git add EvolutionHub/Sources/EvolutionHubCore/Models/ChatStudyAssetPresentation.swift
git add EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationReviewView.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatStudyAssetCard.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationEvidencePresentationTests.swift
git commit -m "feat: review study assets by conversation and type"
```

---

## Task 6：允许从原文手动加入备考库

**阶段结果：** 用户打开上下文、选择任意连续文本、填写分类和用途后，可以创建用户锁定的原文资产；保存文本与所选字符逐字一致。

**Files:**
- Create: `EvolutionHub/Sources/EvolutionHubCore/Models/ChatConversationTextSelection.swift`
- Modify: `EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift`
- Create: `EvolutionHub/Sources/EvolutionHub/ChatConversations/SelectableSourceTextView.swift`
- Create: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatStudyAssetEditorSheet.swift`
- Modify: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationSourceView.swift`
- Create: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationTextSelectionTests.swift`
- Modify: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift`

**Interfaces:**
- Produces: `ChatConversationTextSelection`
- Produces: `ChatConversationSourceDestination`
- Produces: `ChatConversationHubStore.addManualCandidateAsset`
- Produces: `ChatConversationHubStore.addManualFormalAsset`

- [ ] **Step 1：写精确选择失败测试**

```swift
func testSelectionCapturesExactUTF16RangeAndHash() throws {
    let message = ChatConversationMessage(
        id: "assistant-1",
        role: .assistant,
        createdAt: "2026-07-27T00:00:00Z",
        content: "前文🙂需要背诵的规范表述。\n后文"
    )
    let source = message.content as NSString
    let range = source.range(of: "需要背诵的规范表述。")

    let selection = try ChatConversationTextSelection.make(
        conversationID: "conversation-1",
        message: message,
        rangeUTF16: range
    )

    XCTAssertEqual(selection.textSnapshot, "需要背诵的规范表述。")
    XCTAssertEqual(selection.span.locationUTF16, range.location)
    XCTAssertEqual(selection.span.lengthUTF16, range.length)
    XCTAssertEqual(selection.span.textHash, ContentHasher.hash(selection.textSnapshot))
}
```

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversationTextSelectionTests
```

预期：FAIL，提示 selection 类型不存在。

- [ ] **Step 3：实现纯选择校验**

`ChatConversationTextSelection.make` 必须拒绝：

- 空范围；
- 越界范围；
- 选择到空字符串；
- 保存前消息 contentHash 已变化；
- 传入文本与 `NSString.substring(with:)` 不一致。

- [ ] **Step 4：实现 AppKit 选择控件**

`SelectableSourceTextView` 使用不可编辑的 `NSTextView`，开启 selectable，并通过 `textViewDidChangeSelection` 回传当前 `NSRange`。不得通过剪贴板读取选择内容。

```swift
struct SelectableSourceTextView: NSViewRepresentable {
    let text: String
    @Binding var selectedRange: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedRange: $selectedRange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.string = text
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let textView = view.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var selectedRange: NSRange

        init(selectedRange: Binding<NSRange>) {
            _selectedRange = selectedRange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectedRange = textView.selectedRange()
        }
    }
}
```

- [ ] **Step 5：实现两个保存目的地**

```swift
enum ChatConversationSourceDestination: Hashable {
    case candidate(jobID: String, segmentID: String)
    case formal(segmentID: String)
    case readOnly
}
```

- candidate：加入当前候选，确认任务时一起写入。
- formal：直接调用 ledger 原子追加用户资产。
- readOnly：只查看，不显示“加入备考库”。

用户保存表单必须填写标题、一级类型和二级类型；用途可多选。正式人工资产固定 `preservation = .verbatim`、`origin = .userSelection`、`isUserLocked = true`。

- [ ] **Step 6：验证用户资产不会被 Skill 覆盖**

Store 测试创建人工资产后，再提交一个 `replacesAssetID` 指向它的 Skill 候选，预期 Core 拒绝并且原资产版本、正文和锁定状态不变。

- [ ] **Step 7：运行 Hub 测试与构建**

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversation
swift build -c release
```

预期：测试 PASS，release build 成功。

- [ ] **Step 8：本地提交**

```bash
git add EvolutionHub/Sources/EvolutionHubCore/Models/ChatConversationTextSelection.swift
git add EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/SelectableSourceTextView.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatStudyAssetEditorSheet.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationSourceView.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationTextSelectionTests.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift
git commit -m "feat: save manual excerpts as study assets"
```

---

## Task 7：完成备考库、版本和来源状态界面

**阶段结果：** 用户能在一个页面回答三个问题：“这次会话包含什么”“关于这个主题积累了什么”“所有范文或待背诵材料在哪里”。

**Files:**
- Modify: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationLedgerView.swift`
- Modify: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationView.swift`
- Modify: `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatStudyAssetCard.swift`
- Modify: `EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift`
- Modify: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift`

**Interfaces:**
- Produces: `ChatConversationProjectionMode.conversation/topic/kind`
- Produces: `ChatConversationHubStore.appendUserEditedVersion`
- Produces: 来源状态 `current/changed/unavailable/legacyUnscoped`

- [ ] **Step 1：写版本与来源状态失败测试**

```swift
@MainActor
func testUserEditAppendsVersionAndKeepsOldText() throws {
    let store = try makeStoreWithAcceptedAsset(kind: .finishedWork)
    let asset = try XCTUnwrap(store.ledgerDocument.assets.first)
    let oldVersionID = asset.currentVersionId

    try store.appendUserEditedVersion(
        assetID: asset.id,
        text: "用户确认后的完整新版本"
    )

    let updated = try XCTUnwrap(store.ledgerDocument.assets.first)
    XCTAssertEqual(updated.versions.count, 2)
    XCTAssertEqual(updated.versions.last?.supersedesVersionId, oldVersionID)
    XCTAssertEqual(updated.versions.last?.origin, .userEdited)
    XCTAssertEqual(updated.versions.first?.textSnapshot, asset.versions.first?.textSnapshot)
    XCTAssertTrue(updated.isUserLocked)
}
```

来源状态测试：

- 消息 contentHash 相同 → `current`；
- 消息存在但 contentHash 不同 → `changed`；
- 消息不存在 → `unavailable`；
- 迁移资产只有消息级引用、没有精确范围 → `legacyUnscoped`；
- 无论状态如何，正式 `textSnapshot` 不变。

- [ ] **Step 2：运行并确认失败**

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversationHubStoreTests
```

预期：FAIL，提示版本 API 或来源状态不存在。

- [ ] **Step 3：实现正式备考库布局**

顶部固定三个投影：

- `按会话`：会话 → 有序片段目录 → 片段资产；
- `按主题`：主题 → 片段 → 资产；
- `按类型`：一级类型 → 二级类型与用途过滤 → 资产。

展开某个会话后，在该会话内部显示“全部、范文、表达模块、素材证据、方法策略、观点知识、待背诵”等过滤项；点击“范文”只显示这个会话中的范文，不跳到全局结果。

按类型页面提供用途过滤：

- 全部；
- 待背诵；
- 可仿写；
- 可引用；
- 待实践；
- 重点复习。

“人工摘录”不再作为类型按钮；资产卡使用“人工摘录”来源徽章。

- [ ] **Step 4：实现资产卡和版本查看**

资产卡必须显示：

- 标题、一级类型、二级类型；
- 用途；
- 原文/提炼；
- AI识别/用户摘录/用户修改；
- 当前版本完整正文；
- 重点与备注；
- 来源状态；
- “查看原文上下文”；
- “查看历史版本”；
- “创建修改版”。

历史版本只读，按时间倒序显示；任何旧版本都不得从数组中删除。

`legacyUnscoped` 的用户文案固定为“旧版材料只能定位到整条消息，不能证明逐字摘录范围”，不得显示成“原文已校验”。

- [ ] **Step 5：提供显式迁移入口**

`ChatConversationHubStore` 增加：

```swift
@Published public private(set) var ledgerSchemaState: ChatConversationLedgerSchemaState

public func performLegacyLedgerMigration() throws -> URL
```

当状态为 `requiresV1Migration` 时：

- 不读取候选、不生成新任务；
- 页面显示 schema v1 的只读计数；
- 显示“备份并升级备考库”按钮和即将创建的备份目录；
- 只有用户点击按钮后调用迁移；
- 返回实际 backup URL 并在页面展示；
- 迁移失败时保持任务按钮禁用并显示错误。

- [ ] **Step 6：把 Tab 明确标为湖南省直遴选工作区**

保留左侧导航“ChatGPT 对话”也可以，但页面标题必须显示“湖南省直遴选备考库”，并注明“只处理你主动选择的会话”。

- [ ] **Step 7：运行 Hub 测试与 release build**

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test
swift build -c release
```

预期：全部 Hub 测试 PASS，release build 成功。

- [ ] **Step 8：本地提交**

```bash
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationLedgerView.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationView.swift
git add EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatStudyAssetCard.swift
git add EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift
git commit -m "feat: present versioned Hunan selection study library"
```

---

## Task 8：全链路自动验证和两批真实材料验收

**阶段结果：** 自动测试证明契约安全；真实桌面路径证明用户能够从会话得到目录、原文资产、提炼资产和人工摘录，并且第二批只处理新增材料。

**Files:**
- Create: `EvolutionHub/Tests/EvolutionHubCoreTests/Fixtures/HunanSelectionConversation.json`
- Modify: `Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationLedgerTests.swift`
- Modify: `EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift`
- Modify: `/Users/lessen/coding/test/agent-skill-governance/tests/test_chatgpt_ledger_candidate.py`

- [ ] **Step 1：建立固定中文验收夹具**

夹具包含一个会话中的三个意图片段：

1. 三阶段备考策略；
2. 一篇包含标题、三段正文和结尾的完整范文；
3. 两个需要背诵的表达模块。

第二批在同一会话追加：

1. 对范文第二段的局部修改；
2. 一个湖南案例素材。

- [ ] **Step 2：增加自动端到端测试**

自动测试必须证明：

- 第一批生成 3 个片段；
- 范文正文哈希等于来源块拼接哈希；
- 背诵模块属于 `expressionModule` 且含 `memorize`；
- 策略属于 `methodStrategy + distilled`；
- 同一资产 ID 在会话、主题、类型投影中各出现一次；
- 用户排除候选资产不破坏消息覆盖；
- 人工选择文字逐字符保存；
- 第二批任务不含第一批已接受消息版本；
- 局部修改不能自动冒充完整原文版本；
- 用户确认的修改版保留旧版本；
- 重复 apply 不产生重复资产或版本。

- [ ] **Step 3：运行完整自动验证**

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test
swift build -c release
cd /Users/lessen/coding/test/agent-skill-governance
python3 -m unittest discover -s tests -v
scripts/check
cd /Users/lessen/coding/test/TimeLedger
git diff --check
```

预期：全部 PASS；无 whitespace error。

- [ ] **Step 4：安装桌面 App 前再次取得确认**

执行前先读取 `scripts/build-evolution-hub-app` 中的 `APP_NAME` 和 `INSTALLED_APP`，向用户报告这次实际覆盖和清理的应用路径。当前脚本会覆盖 `/Applications/TimeLedger.app`，并可能移除旧名称应用包；覆盖和删除必须获得单独明确确认。

获得确认后才运行：

```bash
cd /Users/lessen/coding/test/TimeLedger
scripts/build-evolution-hub-app
```

预期：构建完成并显示实际安装路径。不能把 release build 成功当成安装和删除已获授权。

- [ ] **Step 5：在用户确认后通过新 App 备份并迁移真实 schema v1**

备份文件放在同一 records 目录，名称为：

```text
chatgpt-ledger.v1-backup-YYYYMMDD-HHMMSS.json
```

用户在迁移提示中点击“备份并升级备考库”，执行者记录 `performLegacyLedgerMigration()` 返回的实际 backup URL；不能使用测试夹具或手工改 JSON 代替桌面迁移路径。

迁移完成后对比：

- 主题数不减少；
- 片段数不减少；
- v1 finding 数等于新增“历史结论”资产数；
- 重点与备注守恒；
- processed revisions 和 receipts 数量、jobId、状态守恒；
- 备份哈希与迁移前原文件哈希一致。

如果任一守恒检查失败，停止真实处理，保留备份与现有文件，不自行删除或回写。

- [ ] **Step 6：第一批真实材料验收**

由用户在 App 中选择一个真实会话，该会话至少包含策略、完整范文和背诵模块。执行：

1. 生成任务；
2. 在 Codex 显式运行 `$chatgpt-ledger process <job-id>`；
3. 回到 App 检查片段目录；
4. 逐项确认资产分类和用途；
5. 确认写入；
6. 打开正式范文，程序比较其 textHash 与来源块拼接 hash；
7. 分别按会话、主题、类型找到同一资产；
8. 从原文手动选择一段文字并加入备考库；
9. 重启 App，确认正式资产、用户锁定、重点、备注和版本仍在。

- [ ] **Step 7：第二批真实增量验收**

在同一会话产生新增回复后重新归档：

1. 新任务只包含新增或 contentHash 变化的消息；
2. Skill 不重复创建旧片段和旧资产；
3. 完整新稿可以建议为新版本；
4. 只有局部修改时显示“局部修改/组合候选”，不得标记为逐字原文完整稿；
5. 用户确认后旧版本仍可查看；
6. 重复执行同一任务不改变正式账本。

- [ ] **Step 8：记录真实验收结论**

只有以下证据齐全才能宣布完成：

- 自动测试命令及 PASS 摘要；
- migration backup 路径与守恒计数；
- 第一批 job ID、候选数量、确认回执；
- 范文来源 hash 与正式快照 hash 相等；
- 人工摘录的来源范围与正式快照相等；
- 第二批 job ID 与只含新增消息的证据；
- 重复执行 noOp 证据；
- 用户可见的三种投影和版本历史截图。

真实材料、迁移或桌面安装未运行时，必须分别记录为 `NOT RUN`，不能用单元测试替代。

- [ ] **Step 9：本地提交验收夹具与测试**

```bash
git add EvolutionHub/Tests/EvolutionHubCoreTests/Fixtures/HunanSelectionConversation.json
git add Packages/EvolutionCore/Tests/EvolutionCoreTests/ChatConversationLedgerTests.swift
git add EvolutionHub/Tests/EvolutionHubCoreTests/ChatConversationHubStoreTests.swift
git commit -m "test: verify Hunan selection study workflow"
```

未经用户明确要求，不 push。

## 最终验收清单

- [ ] 每个已确认会话首先显示有序片段目录，片段有标题、摘要、主题、来源和资产数量。
- [ ] 同一主题后续再次出现时建立新片段，不覆盖旧片段。
- [ ] 范文、完整答题稿、表达模块和规范表述由 App 从来源块直接保存，不由 AI 誊写。
- [ ] 原文资产快照与来源范围逐字符相等，hash 可复核。
- [ ] 策略、方法和观点允许提炼，但必须能打开来源上下文。
- [ ] 一级内容类型、二级类型、用途和产生方式互不混淆。
- [ ] “待背诵”可以附着在范文、模块、素材、方法或观点上。
- [ ] 用户能逐项接受、拒绝或修改 AI 候选。
- [ ] 用户能从原文选择连续文本并直接加入正式备考库。
- [ ] 用户资产和用户修改版本锁定，Skill 不得覆盖。
- [ ] 修改只追加新版本，旧版本始终可查看。
- [ ] 归档变化或缺失时仍保留正式快照，并显示 changed/unavailable。
- [ ] 同一正式资产能按会话、主题和类型查看，底层只有一份记录。
- [ ] 在单个会话内部点击“范文”或“待背诵”，只过滤该会话的资产。
- [ ] 第二批只处理新增或变化的消息版本。
- [ ] 失败、拒绝、重复运行和迁移中断不污染正式账本与处理回执。
- [ ] schema v1 的主题、片段、结论、重点、备注、处理版本和回执迁移守恒。

## 明确不做

- 不建立通用的多领域分类配置中心。
- 不自动判断一段会话是否属于湖南省直遴选；用户选择即为进入边界。
- 不做跨会话 AI 综合写作。
- 不做自动背诵计划、间隔重复或掌握度统计。
- 不自动验证政策、数据和案例真实性；`原文`只保证忠实保存 ChatGPT 当时的文字。
- 不修改归档器现有未提交改动。
- 不自动运行 Skill、自动确认候选、自动迁移、自动安装、push 或公开发布。
