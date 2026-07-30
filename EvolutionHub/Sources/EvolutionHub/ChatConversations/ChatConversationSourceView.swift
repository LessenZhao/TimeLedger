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
            return "这些消息是该资产引用的对话材料。"
        case .session:
            return "完整会话原文（归档只读）。左侧目录定位，右侧阅读并可划线/写笔记。"
        }
    }
}

/// Secondary entry only: a compact button that opens the source stage in a sheet.
struct ChatConversationSourceView: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    let purpose: ChatConversationSourcePurpose
    var destination: ChatConversationSourceDestination = .readOnly
    var allowsNotes: Bool = true
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
                    allowsNotes: allowsNotes
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

/// Left turn catalog + right continuous transcript. Selection notes are parallel to formal assets.
struct ChatConversationSourceStage: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    var purpose: ChatConversationSourcePurpose = .evidence
    var destination: ChatConversationSourceDestination = .readOnly
    /// When false (待确认), selection notes are neither created nor shown.
    var allowsNotes: Bool = true
    /// When false, parent owns the one-row chrome (mode/title/stats/catalog).
    var showsToolbar: Bool = true

    @AppStorage("chat.source.showsTurnCatalog") private var showsCatalog = true
    @State private var selectedTurnID: String?
    @State private var scrollTargetTurnID: String?
    @State private var composer: NoteComposerState?
    @State private var activeNote: ReadingNote?

    private var summary: ChatConversationSourceSummary {
        store.sourceSummary(for: references)
    }

    private var turns: [ChatConversationSourceTurn] {
        store.sourceTurns(for: references)
    }

    private var indexedTurns: [(index: Int, turn: ChatConversationSourceTurn)] {
        Array(turns.enumerated()).map { ($0.offset + 1, $0.element) }
    }

    private var readerSections: [ObsidianReaderSection] {
        turns.flatMap { turn in
            turn.messages.map { message in
                ObsidianReaderSection(
                    id: message.reference.messageId,
                    markdown: transcriptMarkdown(for: message),
                    label: "\(roleLabel(message.role)) · \(message.createdAt)",
                    metadata: .init(
                        conversationId: message.reference.conversationId,
                        messageId: message.reference.messageId
                    )
                )
            }
        }
    }

    private var readerNotes: [ObsidianReaderNote] {
        turns.flatMap { turn in
            turn.messages.flatMap { message in
                store.notes(forMessageID: message.reference.messageId).compactMap { note in
                    switch note.anchor {
                    case .sourceMessageSpan(let span):
                        return ObsidianReaderNote(
                            id: note.id,
                            sectionID: message.reference.messageId,
                            sourceRange: NSRange(location: span.locationUTF16, length: span.lengthUTF16),
                            quote: note.quoteSnapshot,
                            sourceHash: span.sourceHash,
                            visibleTextHash: span.visibleTextHash,
                            rendererVersion: span.rendererVersion,
                            selectorVersion: span.selectorVersion,
                            offsetUnit: span.offsetUnit,
                            positionStart: span.positionStart,
                            positionEnd: span.positionEnd,
                            exact: span.exact,
                            prefix: span.prefix,
                            suffix: span.suffix
                        )
                    case .formalAssetSpan:
                        return nil
                    }
                }
            }
        }
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
                scrollTargetTurnID = turn.messages.first?.reference.messageId
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
                ObsidianMarkdownReader(
                    sections: readerSections,
                    notes: allowsNotes ? readerNotes : [],
                    allowsAnnotations: allowsNotes,
                    scrollTargetID: scrollTargetTurnID,
                    onSelectionAction: { messageID, selection, action in
                        guard let message = sourceMessage(messageID) else { return }
                        switch action {
                        case .note:
                            composer = NoteComposerState(
                                range: selection.range,
                                quote: selection.quote,
                                existingNoteID: nil,
                                existingBody: "",
                                sectionID: messageID,
                                selection: selection
                            )
                        case .highlight:
                            saveSourceNote(message: message, selection: selection, body: nil, highlight: true)
                        case .copy:
                            break
                        }
                    },
                    onEditNote: { noteID in
                        activeNote = sourceNote(noteID)
                    }
                )
                .sheet(item: $composer) { state in
                    NoteComposerSheet(quote: state.quote, initialBody: state.existingBody) { body in
                        guard let messageID = state.sectionID, let message = sourceMessage(messageID) else { return }
                        saveSourceNote(
                            message: message,
                            selection: state.selection ?? .init(
                                range: state.range,
                                quote: state.quote,
                                visibleText: state.quote,
                                prefix: "",
                                suffix: ""
                            ),
                            body: body,
                            highlight: false
                        )
                        composer = nil
                    } onCancel: {
                        composer = nil
                    }
                }
                .sheet(item: $activeNote) { note in
                    NoteComposerSheet(quote: note.quoteSnapshot, initialBody: note.body ?? "") { body in
                        try? store.updateReadingNote(id: note.id, body: body)
                        activeNote = nil
                    } onCancel: {
                        activeNote = nil
                    } onDelete: {
                        try? store.deleteReadingNote(id: note.id)
                        activeNote = nil
                    }
                }
            }
        }
    }

    private func saveSourceNote(
        message: ChatConversationSourceMessage,
        selection: ObsidianReaderSelection,
        body: String?,
        highlight: Bool
    ) {
        do {
            let canonicalMarkdown = message.canonicalMarkdown
            let contentHash = ContentHasher.hash(canonicalMarkdown)
            let textHash = ContentHasher.hash(selection.quote)
            let anchor = try ReadingNote.sourceAnchor(
                conversationId: message.reference.conversationId,
                messageId: message.reference.messageId,
                contentHash: contentHash,
                locationUTF16: selection.range.location,
                lengthUTF16: selection.range.length,
                textHash: textHash,
                sourceHash: contentHash,
                visibleTextHash: ContentHasher.hash(selection.visibleText),
                exact: selection.quote,
                prefix: selection.prefix,
                suffix: selection.suffix
            )
            if highlight && (body == nil || body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                _ = try store.addHighlight(quoteSnapshot: selection.quote, anchor: anchor)
            } else {
                _ = try store.addNote(
                    body: body,
                    quoteSnapshot: selection.quote,
                    anchor: anchor,
                    isHighlight: highlight
                )
            }
        } catch {
            // Invalid selection stays local.
        }
    }

    private func roleLabel(_ role: ChatConversationRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        case .system: return "system"
        }
    }

    private func sourceMessage(_ messageID: String) -> ChatConversationSourceMessage? {
        turns.lazy.flatMap(\.messages).first { $0.reference.messageId == messageID }
    }

    private func sourceNote(_ noteID: String) -> ReadingNote? {
        turns.lazy.flatMap(\.messages)
            .flatMap { store.notes(forMessageID: $0.reference.messageId) }
            .first { $0.id == noteID }
    }


    private func transcriptMarkdown(for message: ChatConversationSourceMessage) -> String {
        message.canonicalMarkdown
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
