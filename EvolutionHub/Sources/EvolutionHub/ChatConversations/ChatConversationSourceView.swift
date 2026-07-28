import EvolutionCore
import EvolutionHubCore
import SwiftUI

enum ChatConversationSourcePurpose {
    case coverage
    case evidence
    case session

    var buttonLabel: String {
        switch self {
        case .coverage: return "查看处理材料"
        case .evidence: return "查看原文上下文"
        case .session: return "打开会话原文"
        }
    }

    var title: String {
        switch self {
        case .coverage: return "已覆盖原始消息"
        case .evidence: return "资产引用的原始消息"
        case .session: return "会话原文"
        }
    }

    var explanation: String {
        switch self {
        case .coverage:
            return "这些消息已被本次处理覆盖；它们不一定都直接证明同一条资产。"
        case .evidence:
            return "这些消息是该资产引用的对话材料；可选择连续文本加入备考库。"
        case .session:
            return "完整会话原文（归档只读）。左侧目录定位，右侧 Markdown 全文阅读与摘录。"
        }
    }
}

/// Secondary entry only: a compact button that opens the source stage in a sheet.
/// Primary reading path is `ChatConversationSourceStage` embedded in the center stage.
struct ChatConversationSourceView: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    let purpose: ChatConversationSourcePurpose
    var destination: ChatConversationSourceDestination = .readOnly
    @State private var isInspectorPresented = false

    var body: some View {
        Button {
            isInspectorPresented = true
        } label: {
            Label("\(purpose.buttonLabel) \(references.count)", systemImage: "text.book.closed")
        }
        .font(.caption)
        .help("次级入口：在独立窗口打开原文。主路径请用中栏「原文」。")
        .sheet(isPresented: $isInspectorPresented) {
            NavigationStack {
                ChatConversationSourceStage(
                    store: store,
                    references: references,
                    purpose: purpose,
                    destination: destination,
                    allowsExcerpt: true
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { isInspectorPresented = false }
                    }
                }
            }
            .frame(minWidth: 860, minHeight: 560)
        }
    }
}

/// Single reading model: left turn catalog (hideable) + right continuous Markdown transcript.
/// Excerpt uses a multi-selection bag; each bag item maps to one source span.
struct ChatConversationSourceStage: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    var purpose: ChatConversationSourcePurpose = .evidence
    var destination: ChatConversationSourceDestination = .readOnly
    var allowsExcerpt: Bool = true
    var excerptMode: Bool = false
    /// When false, parent owns the one-row chrome (mode/title/stats/catalog).
    var showsToolbar: Bool = true

    @AppStorage("chat.source.showsTurnCatalog") private var showsCatalog = true
    @State private var selectedTurnID: String?
    @State private var scrollTargetTurnID: String?
    @State private var selectingMessageID: String?
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var excerptBag: [ChatConversationTextSelection] = []
    @State private var editorSelection: ChatConversationTextSelection?
    @State private var batchEditorToken: BatchEditorToken?

    private var summary: ChatConversationSourceSummary {
        store.sourceSummary(for: references)
    }

    private var turns: [ChatConversationSourceTurn] {
        store.sourceTurns(for: references)
    }

    private var indexedTurns: [(index: Int, turn: ChatConversationSourceTurn)] {
        Array(turns.enumerated()).map { ($0.offset + 1, $0.element) }
    }

    private var canAddToLibrary: Bool {
        guard allowsExcerpt else { return false }
        if case .readOnly = destination { return false }
        return true
    }

    private var showExcerptChrome: Bool {
        allowsExcerpt
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                toolbar
                Divider()
            }
            HSplitView {
                if showsCatalog {
                    turnCatalog
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
                }
                transcriptPane
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            if showExcerptChrome, !excerptBag.isEmpty || excerptMode {
                Divider()
                excerptBagBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            if selectedTurnID == nil {
                selectedTurnID = turns.first?.id
            }
        }
        .onChange(of: references.map(\.messageId).joined(separator: "|")) { _, _ in
            selectedTurnID = turns.first?.id
            scrollTargetTurnID = nil
            selectingMessageID = nil
            selectedRange = NSRange(location: 0, length: 0)
            excerptBag = []
        }
        .sheet(item: Binding(
            get: { editorSelection.map { SelectableEditorItem(selection: $0) } },
            set: { editorSelection = $0?.selection }
        )) { item in
            ChatStudyAssetEditorSheet(previewText: item.selection.textSnapshot) { title, kind, subtype, uses in
                saveSelection(item.selection, title: title, kind: kind, subtype: subtype, uses: uses)
            }
        }
        .sheet(item: $batchEditorToken) { token in
            ChatStudyAssetEditorSheet(previewText: token.previewText) { title, kind, subtype, uses in
                saveBag(token.selections, title: title, kind: kind, subtype: subtype, uses: uses)
                batchEditorToken = nil
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(purpose.title)
                .font(.subheadline.weight(.semibold))
            Text("消息 \(summary.messageCount) · 轮次 \(summary.turnCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if summary.attachmentMessageCount > 0 {
                ChatConversationAttachmentNotice()
            }
            Spacer(minLength: 0)
            SourceCatalogToggle()
        }
        .padding(.horizontal, 12)
        .frame(height: ChatChromeMetrics.headerHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var turnCatalog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(purpose.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if summary.unavailableMessageCount > 0 {
                    Text("有 \(summary.unavailableMessageCount) 条消息在当前归档中不可用")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if turns.isEmpty {
                    ContentUnavailableView(
                        "没有可展示的原文消息",
                        systemImage: "text.badge.xmark",
                        description: Text("检查归档是否包含这些 messageId。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(indexedTurns, id: \.turn.id) { item in
                        catalogRow(index: item.index, turn: item.turn)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func catalogRow(index: Int, turn: ChatConversationSourceTurn) -> some View {
        let isSelected = selectedTurnID == turn.id
        let isStarred = store.isTurnStarred(turn.id)

        return HStack(alignment: .top, spacing: 8) {
            Button {
                store.toggleTurnStar(turnID: turn.id)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? Color.orange : Color.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isStarred ? "取消轮次星标" : "标记为重点轮次")

            Button {
                selectedTurnID = turn.id
                scrollTargetTurnID = turn.id
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(index) 轮 · \(turn.catalogTitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(turn.catalogSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(turn.messages.count) 条消息")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private var transcriptPane: some View {
        Group {
            if turns.isEmpty {
                ContentUnavailableView(
                    "没有可展示的原文",
                    systemImage: "doc.plaintext",
                    description: Text(purpose.explanation)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(indexedTurns, id: \.turn.id) { item in
                                turnSection(index: item.index, turn: item.turn)
                                    .id(item.turn.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: scrollTargetTurnID) { _, turnID in
                        guard let turnID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(turnID, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func turnSection(index: Int, turn: ChatConversationSourceTurn) -> some View {
        let isStarred = store.isTurnStarred(turn.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("第 \(index) 轮")
                    .font(.title2.weight(.semibold))
                Button {
                    store.toggleTurnStar(turnID: turn.id)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isStarred ? "取消轮次星标" : "标记为重点轮次")
                Spacer(minLength: 0)
                if selectedTurnID == turn.id {
                    Text("当前")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }

            Text(turn.catalogTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(turn.messages) { message in
                messageBlock(message)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    selectedTurnID == turn.id ? Color.accentColor.opacity(0.28) : Color.clear,
                    lineWidth: 1
                )
        )
        .onTapGesture {
            selectedTurnID = turn.id
        }
    }

    private func messageBlock(_ message: ChatConversationSourceMessage) -> some View {
        let messageKey = message.reference.messageId
        let isSelecting = selectingMessageID == messageKey

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(roleLabel(message.role))
                    .font(.headline)
                Text(message.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if showExcerptChrome {
                    if isSelecting {
                        Button("取消选择") {
                            selectingMessageID = nil
                            selectedRange = NSRange(location: 0, length: 0)
                        }
                        .font(.caption)
                        Button("加入摘录袋") {
                            addCurrentSelectionToBag(from: message)
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                        .disabled(selectedRange.length == 0 || !canAddToLibrary)
                        .help(canAddToLibrary
                              ? "将当前选区加入摘录袋（可继续选其他段落）"
                              : excerptDisabledHelp)
                    } else {
                        Button("摘录此段") {
                            selectingMessageID = messageKey
                            selectedRange = NSRange(location: 0, length: 0)
                            selectedTurnID = turns.first(where: {
                                $0.messages.contains(where: { $0.id == message.id })
                            })?.id
                        }
                        .font(.caption)
                        .disabled(!canAddToLibrary)
                        .help(canAddToLibrary
                              ? "在本段原文中拖选文本，再加入摘录袋"
                              : excerptDisabledHelp)
                    }
                }
            }

            if isSelecting {
                SelectableSourceTextView(text: message.content, selectedRange: $selectedRange)
                    .frame(minHeight: 160, maxHeight: 320)
                Text(selectedRange.length > 0
                     ? "已选 \(selectedRange.length) 个 UTF-16 单位"
                     : "拖选连续文本后点「加入摘录袋」；可继续摘录其他段落")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let markdown = transcriptMarkdown(for: message)
                MarkdownBodyView(text: markdown, bodyFontSize: 15)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private var excerptBagBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("摘录袋 \(excerptBag.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !excerptBag.isEmpty {
                    Button("清空") { excerptBag = [] }
                        .font(.caption)
                    Button("逐条写入正式库") {
                        if excerptBag.count == 1, let only = excerptBag.first {
                            editorSelection = only
                        } else {
                            batchEditorToken = BatchEditorToken(selections: excerptBag)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddToLibrary)
                    .help(canAddToLibrary
                          ? "袋中每段各写入一条正式资产"
                          : excerptDisabledHelp)
                }
            }

            if excerptBag.isEmpty {
                Text(canAddToLibrary
                     ? "在正文中点「摘录此段」，拖选后加入摘录袋；可跨多轮累积。"
                     : excerptDisabledHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(excerptBag.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 6) {
                                Text("\(index + 1). \(bagPreview(item))")
                                    .font(.caption)
                                    .lineLimit(1)
                                Button {
                                    excerptBag.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var excerptDisabledHelp: String {
        "当前上下文是只读原文，或缺少可写入的正式片段/候选片段。"
    }

    private func roleLabel(_ role: ChatConversationRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        case .system: return "system"
        }
    }

    private func transcriptMarkdown(for message: ChatConversationSourceMessage) -> String {
        let body = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return "_（空消息）_"
        }
        // Keep original markdown body; role heading already shown above.
        return body
    }

    private func bagPreview(_ selection: ChatConversationTextSelection) -> String {
        ChatConversationTurnPresentation.preview(from: selection.textSnapshot, limit: 28)
    }

    private func addCurrentSelectionToBag(from message: ChatConversationSourceMessage) {
        do {
            let selection = try ChatConversationTextSelection.make(
                conversationID: message.reference.conversationId,
                message: ChatConversationMessage(
                    id: message.reference.messageId,
                    role: message.role,
                    createdAt: message.createdAt,
                    content: message.content
                ),
                rangeUTF16: selectedRange
            )
            // Avoid exact duplicate spans in the bag.
            if !excerptBag.contains(where: {
                $0.span.message == selection.span.message
                    && $0.span.locationUTF16 == selection.span.locationUTF16
                    && $0.span.lengthUTF16 == selection.span.lengthUTF16
            }) {
                excerptBag.append(selection)
            }
            selectingMessageID = nil
            selectedRange = NSRange(location: 0, length: 0)
        } catch {
            // Invalid selection stays local; user can reselect.
        }
    }

    private func saveSelection(
        _ selection: ChatConversationTextSelection,
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>
    ) {
        switch destination {
        case .candidate(let jobID, let segmentID):
            try? store.addManualCandidateAsset(
                jobID: jobID,
                segmentID: segmentID,
                selection: selection,
                title: title,
                kind: kind,
                subtype: subtype,
                uses: uses
            )
        case .formal(let segmentID):
            try? store.addManualFormalAsset(
                segmentID: segmentID,
                selection: selection,
                title: title,
                kind: kind,
                subtype: subtype,
                uses: uses
            )
        case .readOnly:
            break
        }
        excerptBag.removeAll {
            $0.span.message == selection.span.message
                && $0.span.locationUTF16 == selection.span.locationUTF16
                && $0.span.lengthUTF16 == selection.span.lengthUTF16
        }
        editorSelection = nil
    }

    private func saveBag(
        _ selections: [ChatConversationTextSelection],
        title: String,
        kind: ChatStudyAssetKind,
        subtype: String,
        uses: Set<ChatStudyAssetUse>
    ) {
        for (offset, selection) in selections.enumerated() {
            let itemTitle = selections.count == 1 ? title : "\(title)（\(offset + 1)）"
            saveSelection(selection, title: itemTitle, kind: kind, subtype: subtype, uses: uses)
        }
        excerptBag = []
    }
}

/// Shared turn-catalog toggle; keeps AppStorage key in one place.
struct SourceCatalogToggle: View {
    @AppStorage("chat.source.showsTurnCatalog") private var showsCatalog = true

    var body: some View {
        Button {
            showsCatalog.toggle()
        } label: {
            Label(
                showsCatalog ? "目录" : "目录",
                systemImage: showsCatalog ? "sidebar.left" : "sidebar.squares.left"
            )
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .help(showsCatalog ? "隐藏轮次目录" : "显示轮次目录")
    }
}

struct ChatConversationAttachmentNotice: View {
    var body: some View {
        Label(
            "该片段包含附件；当前只归档了会话文字，附件正文未进入备考库。",
            systemImage: "paperclip"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}

private struct SelectableEditorItem: Identifiable {
    var selection: ChatConversationTextSelection
    var id: String {
        "\(selection.span.message.messageId)-\(selection.span.locationUTF16)-\(selection.span.lengthUTF16)"
    }
}

private struct BatchEditorToken: Identifiable {
    var selections: [ChatConversationTextSelection]
    var id: String {
        selections.map {
            "\($0.span.message.messageId):\($0.span.locationUTF16):\($0.span.lengthUTF16)"
        }
        .joined(separator: "|")
    }

    var previewText: String {
        selections.enumerated().map { index, item in
            "### 摘录 \(index + 1)\n\(item.textSnapshot)"
        }
        .joined(separator: "\n\n")
    }
}

private extension ChatConversationSourceDestination {
    var isReadOnly: Bool {
        if case .readOnly = self { return true }
        return false
    }
}
