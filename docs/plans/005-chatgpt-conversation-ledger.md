# ChatGPT 对话账本实施方案

> **后续方案说明（2026-07-27）：** 本文继续记录结构化归档、增量消息、不可变任务、显式 Skill、候选确认和回执等基础链路。涉及湖南省直遴选的片段目录、备考资产分类、原文确定性保存、版本、人工摘录和按类型查看，改按独立的 [006-hunan-selection-prep-assets.md](./006-hunan-selection-prep-assets.md) 执行；本文其余正文不在原地重写。

> **供执行者使用：** 只有用户明确说“执行”后，才能执行本方案。所有步骤使用复选框（`- [ ]`）跟踪。

**执行状态：** 仅完成方案。当前未获授权创建分支或实施功能。

**目标：** 在 TimeLedger Mac App 中新增独立的“ChatGPT 对话”入口。用户可以选择已归档的 ChatGPT 会话，通过显式调用 Codex Skill 只处理尚未处理的材料，并按会话或合并后的主题查看持续积累的结果。

**架构：** `ai-chat-future-activity-archiver` 继续作为原始资料来源，并额外保存包含稳定 ChatGPT 消息 ID 的结构化会话文件。TimeLedger 负责材料选择、处理任务、候选结果检查、正式 ChatGPT 语义账本以及两种查看方式。用户在 Codex 中显式调用 Skill；Skill 只读取一个不可变任务并生成候选结果，不能直接修改正式账本。

**技术栈：** TypeScript、WXT、Node companion、Swift 5.9、macOS 14 SwiftUI、Codable JSON、EvolutionCore 现有哈希与原子文件模式、Codex Skill。

## 全局约束

- Mac App 新增独立导航项“ChatGPT 对话”，不能混入“工作沉淀”。
- 日期范围只用于筛选和展示；处理范围永远由用户选中的会话决定。
- 选择曾经处理过的会话时，只包含当前尚未处理的消息版本；相邻旧消息只能作为只读上下文。
- 消息身份使用 ChatGPT 的 `conversationId + messageId`；内容哈希用于识别同一消息是否发生变化。
- Skill 只能由用户在 Codex 中显式调用。App 不调用 Codex CLI、OpenAI API 或后台模型。
- Skill 只写候选 JSON，不能写正式账本，也不能把原始消息标记为已处理。
- 只有候选校验、用户确认、正式保存和回执写入全部成功后，原始消息才算已处理。
- 每一条选中的输入消息必须被某个主题片段覆盖，或者明确标记为忽略并说明原因；不允许静默遗漏。
- 用户对主题的纠正、重点标记和备注属于正式内容，后续候选不能覆盖。
- 原始会话正文继续保存在归档目录。`records/chatgpt-ledger.json` 只保存语义记录、来源引用、消息版本哈希、用户内容和处理回执。
- V0 不引入数据库、SwiftData 变更、向量库、图谱、自动调度、全历史处理、跨模型聚合或 iPhone 页面。
- Task 7 的两批真实材料验收是完成条件；只有单元测试通过不能宣布完成。
- 用户没有明确要求收尾或维护现场时，不更新 `PROJECT_STATE.md` 和 `CHANGELOG.md`。
- 未经单独明确授权，不 push、不公开发布。

## 执行分支

只有用户授权执行后才创建以下分支。因为工作跨越三个独立 Git 仓库，所以必须分别建立分支。

| 仓库 | 分支 |
| --- | --- |
| `/Users/lessen/coding/test/TimeLedger` | `codex/chatgpt-conversation-ledger` |
| `/Users/lessen/coding/test/ai-chat-future-activity-archiver` | `codex/chatgpt-structured-export` |
| `/Users/lessen/coding/test/agent-skill-governance` | `codex/chatgpt-ledger-skill` |

创建每个分支前，必须先检查对应工作树，不得覆盖用户无关改动。

## 产品闭环

完成后的用户操作必须是：

1. 打开“ChatGPT 对话”。
2. 按日期范围筛选已归档会话。
3. 选择一个或多个会话。
4. 点击“生成处理任务”。
5. 复制 App 显示的命令：`$chatgpt-ledger process <job-id>`。
6. 在 Codex 中显式执行命令，并查看执行过程。
7. 回到 App，检查候选变化；必要时纠正主题归属，然后确认。
8. 按会话或按主题查看累计账本；点击任一结果可检查来源消息。
9. 出现新消息后重复上述流程；只处理新增或发生变化的消息版本。

主页面只包含：

- 日期范围和处理状态筛选。
- 会话选择，以及“已处理 / 新增”消息数量。
- “生成处理任务”。
- 待确认候选结果。
- “按会话 / 按主题”切换。
- 来源消息检查区。

## 最小数据契约

### 原始归档结构化文件

每个已归档会话在 `data/conversations/<conversation-id>.json` 下保存一份稳定 JSON：

- `schemaVersion`
- `conversationId`、`title`、`sourceURL`
- `createdAt`、`updatedAt`
- 按顺序保存的消息，每条包含 `id`、`role`、`createdAt` 和 `content`

`_archive-index.json` 增加可选的 `lastDataFilename`，保证旧归档仍能读取。缺少结构化文件的会话在 App 中显示“需要重新导出”，不能伪装成空会话。

### 正式 ChatGPT 账本

`records/chatgpt-ledger.json` 保存：

- `topics`：稳定主题身份和用户控制的名称。
- `segments`：按原会话顺序排列、归属于某个主题的会话片段。
- `findings`：去重后的内容点及其来源消息。
- `processedRevisions`：原消息 ID、已接受内容哈希和对应任务 ID。
- `marks`：内容点的重点标记和用户备注。
- `receipts`：已接受或已拒绝任务的回执，用于幂等和恢复。

正式账本不保存完整原始会话正文。

### 处理任务

一个不可变处理任务包含：

- `jobId`、`createdAt`
- 用户选中的会话 ID
- 尚未处理的消息版本
- 少量相邻上下文消息，并标记为 `contextOnly`
- 当前主题名称和压缩后的已有内容点
- `sourceDigest` 和 `baseLedgerDigest`

### 候选结果

Skill 生成的一份候选结果包含：

- 与任务一致的 `jobId`、`sourceDigest` 和 `baseLedgerDigest`
- 主题片段及其按顺序排列的来源消息 ID
- 每个片段对应的已有主题 ID，或者建议创建的新主题
- 建议新增的内容点及其来源消息 ID
- 与已有内容重复的匹配结果
- 被忽略的输入消息 ID 及原因

遇到旧账本版本不一致、哈希不一致、输入覆盖不完整、伪造来源 ID 或重复导入时，App 必须拒绝候选。

## 文件范围

### `ai-chat-future-activity-archiver`

- 修改 `src/core/archive-model.ts`：定义结构化会话文件，并把它加入待写入导出结果。
- 修改 `src/core/archive-service.ts`：携带导出时已经获得的用户与助手消息数据。
- 修改 `src/storage/file-system-archive.ts`：在 fallback 模式写结构化文件。
- 修改 `src/core/export-runner.ts`：每次成功写 Markdown 时同步写结构化文件。
- 修改 `companion/src/types.ts`：接收结构化数据。
- 修改 `companion/src/archive-writer.ts`：原子写入 `data/conversations/<id>.json`，并记录到 manifest。
- 修改 `src/core/export-planner.ts`：保留 `lastDataFilename`。
- 测试 `tests/archive-service.test.ts`、`tests/file-system-archive.test.ts`、`tests/companion-server.test.ts` 和 `tests/export-planner.test.ts`。

### TimeLedger `EvolutionCore`

- 修改 `Packages/EvolutionCore/Sources/EvolutionCore/EvolutionLedgerLayout.swift`：在现有 Personal Evolution 根目录下增加 ChatGPT 正式账本与交换目录。
- 新建 `ChatConversationDomain.swift`：归档 DTO、主题、片段、内容点、标记和账本文档。
- 新建 `ChatConversationArchiveReader.swift`：读取 manifest 与结构化文件，计算每个会话的待处理数量。
- 新建 `ChatConversationExchange.swift`：处理任务、候选结果、忽略输入和回执契约。
- 新建 `ChatConversationLedger.swift`：原子持久化、任务生成、校验、应用、幂等和用户修改。
- 每项职责使用独立的 `ChatConversation*Tests.swift` 测试。

### TimeLedger `EvolutionHub`

- 新建 `EvolutionHub/Sources/EvolutionHubCore/Store/ChatConversationHubStore.swift`：负责刷新归档、选择会话、生成任务、读取待确认候选、接受或拒绝，以及用户修改。
- 新建 `EvolutionHub/Sources/EvolutionHubCore/Import/ChatConversationProposalInbox.swift`：读取 Skill 候选，但不能自动应用。
- 新建 `EvolutionHub/Sources/EvolutionHub/ChatConversations/ChatConversationView.swift`：组合单页工作流。
- 新建 `ChatConversationListView.swift`：筛选、数量、选择和 Skill 命令。
- 新建 `ChatConversationLedgerView.swift`：会话/主题投影和候选检查。
- 新建 `ChatConversationSourceView.swift`：检查来源消息。
- 修改 `EvolutionHub/Sources/EvolutionHub/RootView.swift`：增加“ChatGPT 对话”。
- 修改 `EvolutionHub/Sources/EvolutionHub/EvolutionHubApp.swift`：注入并刷新 `ChatConversationHubStore`。
- 复用 `HubSettings.chatgptArchiveRoot`，不新增第二套路径设置。
- 测试 `ChatConversationHubStoreTests.swift`、`ChatConversationProposalInboxTests.swift` 和一条完整用户流程。

### `agent-skill-governance`

- 新建 `skills/chatgpt-ledger/SKILL.md`：提供显式 `process <job-id>` 流程。
- 新建 `skills/chatgpt-ledger/agents/openai.yaml`：只保存展示元数据。
- 修改 `policy.yaml`：把 Skill 注册为仅显式调用。
- Skill 读取一个待处理任务，报告可见执行阶段，先写 `<job-id>.json.tmp`，再原子发布到 ChatGPT 候选收件箱。
- Skill 不得调用另一个 Codex CLI 进程，也不得修改 TimeLedger 正式记录。

## Task 1：保留稳定的 ChatGPT 原始消息

**阶段结果：** 一次成功归档同时生成现有 Markdown 和包含 ChatGPT 原始消息 ID 的结构化会话文件。

- [ ] 先为待写入导出结果、companion 写入、fallback 写入和旧 manifest 兼容性增加失败测试。
- [ ] 实现结构化会话数据，不把附件的 data URL 写入 sidecar。
- [ ] companion 模式使用原子写入；File System Access fallback 模式正常写入同一数据格式。
- [ ] `lastDataFilename` 保持可选，旧 manifest 必须继续解码。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/ai-chat-future-activity-archiver
npm test
npm run compile
npm run companion:build
npm run build
```

**必要证据：** 测试证明消息 ID、角色、时间和正文能够完整保存；重新导出覆盖同一个结构化文件，不产生副本。

## Task 2：读取归档并计算待处理材料

**阶段结果：** EvolutionCore 能列出已归档会话，并根据原始消息版本和正式账本准确推导“已处理、待处理、部分处理、需要重新导出”。

- [ ] 定义最小 ChatGPT 领域记录，并增加 Codable 往返测试。
- [ ] 实现结构化会话读取，保证顺序稳定并明确报告错误。
- [ ] 在 EvolutionCore 中计算每条消息的内容哈希。
- [ ] 会话状态必须由原始版本与正式记录推导，不能再存一份可能漂移的状态。
- [ ] 覆盖新会话、完全处理、追加消息、消息内容变化和缺少结构化文件五种情况。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test --filter ChatConversation
```

**必要证据：** 一个包含18条已接受消息和4条新增消息的测试夹具，必须准确显示 `18 processed / 4 pending`。

## Task 3：建立安全处理任务和正式账本

**阶段结果：** App 能从用户选中的会话生成一个不可变任务；正式账本对候选只校验和应用一次。

- [ ] 在现有 Personal Evolution 目录结构下增加 ChatGPT 路径。
- [ ] 为 `chatgpt-ledger.json` 实现一个原子 JSON 文档存储。
- [ ] 任务只包含尚未处理的消息版本；最多携带前一个相邻的用户/助手问答作为 `contextOnly`。
- [ ] 在任务中冻结 `sourceDigest` 和 `baseLedgerDigest`。
- [ ] 校验输入完整覆盖、来源引用、主题目标和摘要哈希一致性。
- [ ] 只有显式确认后才能应用；先写正式账本，再写回执。
- [ ] 增加幂等、旧候选、部分写入恢复和用户锁定测试。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test --filter ChatConversation
```

**必要证据：** 同一任务再次应用时不产生变化；被拒绝或中断的任务必须让全部输入消息继续保持待处理。

## Task 4：增加 Mac“ChatGPT 对话”工作流

**阶段结果：** 用户无需离开新 Tab，即可筛选会话、选择材料并生成处理任务。

- [ ] 增加新导航项并注入对应 Store。
- [ ] 明确展示归档路径错误和“需要重新导出”状态。
- [ ] 增加日期范围与处理状态筛选，并证明日期筛选只改变可见内容。
- [ ] 显示已处理/待处理消息数量，支持多选会话。
- [ ] 生成任务，并显示可复制的 `$chatgpt-ledger process <job-id>` 命令。
- [ ] 保持现有“工作沉淀”行为不变。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversation
```

**必要证据：** 选择一个部分处理的会话后，生成的任务只能包含其待处理消息版本。

## Task 5：实现显式调用的 Codex Skill

**阶段结果：** 在 Codex 中运行 `$chatgpt-ledger process <job-id>`，能够生成一份可核查候选结果，并且不修改 App 正式账本。

- [ ] 定义仅允许显式调用的 Skill 及受管元数据。
- [ ] 必须传入准确任务 ID，不支持含糊的 `latest`。
- [ ] 分析前确认任务存在，并且没有已接受回执。
- [ ] 报告可见执行阶段：输入盘点、会话分段、主题匹配、内容点比较、覆盖检查和候选发布。
- [ ] 已有主题 ID 必须原样复用；新主题只能保持候选状态。
- [ ] 保留不同判断，不能为了合并而制造虚假共识。
- [ ] 完成本地结构检查后，先写 `.json.tmp`，再发布到 ChatGPT 候选收件箱。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/agent-skill-governance
python3 -m unittest discover -s tests -v
scripts/check
```

**必要证据：** 一个包含三个会话和一个重复主题的测试任务，必须生成已有主题匹配、带来源的内容点、完整输入覆盖，并且不写正式账本。

## Task 6：检查、确认并查看结果

**阶段结果：** App 允许用户纠正候选主题归属、确认候选，并按会话或按主题查看同一批正式记录。

- [ ] 读取候选结果，但不能自动应用。
- [ ] 确认前展示新主题、已有主题匹配、新内容点、重复内容和忽略消息。
- [ ] 允许修改片段的主题目标，并重命名候选主题。
- [ ] 只有确认后才能应用，并展示最终回执。
- [ ] 增加“按会话”投影，保持原始会话顺序。
- [ ] 增加“按主题”投影，跨会话合并片段和去重内容点。
- [ ] 增加主题重命名、主题合并、片段移动、内容点重点标记和备注。
- [ ] 每个片段和内容点都能打开来源消息。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversation
```

**必要证据：** 两种投影解析到完全相同的主题、片段、内容点和来源 ID；用户纠正和标记在刷新后仍然存在。

## Task 7：使用两批真实材料验收

**阶段结果：** 使用真实 ChatGPT 归档，在真实 App 中证明用户的完整目标已经实现。

- [ ] 运行全部自动验证：

```bash
cd /Users/lessen/coding/test/ai-chat-future-activity-archiver
npm test
npm run compile
npm run companion:build
npm run build

cd /Users/lessen/coding/test/TimeLedger/Packages/EvolutionCore
swift test

cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test

cd /Users/lessen/coding/test/agent-skill-governance
python3 -m unittest discover -s tests -v
scripts/check

cd /Users/lessen/coding/test/TimeLedger
scripts/build-evolution-hub-app
git diff --check
```

- [ ] 第一批：重新导出并选择三个真实会话，其中至少两个会话包含同一主题。
- [ ] 执行 App 显示的 Skill 命令，并在 App 中确认候选。
- [ ] 验证会话分段、主题合并、内容点去重、来源打开、重点标记和备注。
- [ ] 第二批：在一个已处理会话中追加消息，并增加一个新会话。
- [ ] 验证 App 只选择新增版本；Skill 与已有主题比较；确认后不重复生成旧内容点。
- [ ] 再次执行同一条第二批命令，验证正式账本完全不变。
- [ ] 退出并重新启动 App，验证主题、内容点、处理数量、纠正、重点、备注和回执全部保留。

## 最终验收

只有以下条件全部满足，才能宣布功能完成：

1. Mac App 中存在独立的“ChatGPT 对话”入口。
2. 处理范围由用户选择；日期不能在后台决定处理范围。
3. 第一批材料能够生成会话片段、合并主题和带来源的内容点。
4. 第二批只处理新增或发生变化的消息版本。
5. 重复主题和重复内容点不会再次创建。
6. 用户可以在确认前纠正主题归属。
7. 用户可以按会话或按主题查看同一批已接受材料。
8. 每个已接受内容点都能打开对应原始消息。
9. 用户重点、备注和主题纠正在后续处理和 App 重启后仍然存在。
10. 失败、拒绝或重复执行不能错误标记消息已处理，也不能制造重复语义记录。

## Task 8：证据链清晰展示与可扩展来源查看

**阶段结果：** 候选态和正式态使用同一条可追溯关系：主题、会话片段、结论、会话和原始消息。用户能区分“本批材料已覆盖”与“哪几条消息直接支撑结论”，且不会在页面内展开全部原文而卡顿。

- [ ] 原始消息仍是唯一增量和回执单位：`conversationId + messageId + contentHash`；对话轮次只用于阅读，不写入正式账本。
- [ ] 在 Hub Store 增加可测试的来源摘要、按会话顺序推导的对话轮次，以及“结论引用哪些会话片段”的关系查询；该关系从已有片段和消息引用确定，不改变候选或正式 JSON 格式。
- [ ] 候选页按建议主题分组显示会话片段和候选结论。片段显示“已覆盖原始消息”，结论显示“结论引用”；两者不再共用含糊的“来源”名称。
- [ ] 每个结论明确展示其关联的会话片段；每个片段明确展示所属会话和主题目标。
- [ ] 原始材料通过独立、可滚动的来源查看器按对话轮次呈现，一次只展开一轮，不在候选或正式页内内联渲染全部原文。
- [ ] 正式账本默认只显示含已接受片段或结论的会话；按主题和按会话两种投影都显示相同的主题、片段、结论和来源关系。
- [ ] 候选已出现时隐藏同一任务的旧 Skill 命令，改为明确提示“候选待确认”。
- [ ] 增加 Store 回归测试：角色/轮次统计、结论到片段的推导关系、空正式账本过滤，以及候选出现后不再显示旧命令。
- [ ] 运行：

```bash
cd /Users/lessen/coding/test/TimeLedger/EvolutionHub
swift test --filter ChatConversation
swift build -c release
```

**必要证据：** 一个含两个会话片段和一条跨片段结论的测试夹具，必须在候选态和确认后的正式态中都显示同一组关联；一个含长原文的来源查看仅在用户选择某一轮时才展示该轮全文。

## 明确后置

- 自动处理或定时处理。
- 由 App 控制 Codex CLI/API。
- 全历史批量处理。
- 主题层级、Embedding、向量搜索和知识图谱。
- 跨主题演化或冲突可视化。
- ChatGPT、Codex、Claude 跨来源聚合。
- iPhone 端展示或同步。
- 统计面板和自动生成学习计划。
