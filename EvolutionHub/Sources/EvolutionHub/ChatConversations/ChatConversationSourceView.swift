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
            return "完整会话原文（归档只读）。在「摘录」模式下选中文本后可写入正式库。"
        }
    }
}

/// Secondary entry only: a compact button that opens the source stage in a sheet.
/// Primary reading path is `ChatConversationSourceStage` embedded in the center stage.
/// Do not treat this sheet as the main “查看原文” experience.
struct ChatConversationSourceView: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    let purpose: ChatConversationSourcePurpose
    var destination: ChatConversationSourceDestination = .readOnly
    @State private var isInspectorPresented = false

    var body: some View {
        Button {
            // Secondary path only — primary path is the center-stage source mode.
            isInspectorPresented = true
        } label: {
            Label("\(purpose.buttonLabel) \(references.count)", systemImage: "text.book.closed")
        }
        .font(.caption)
        .help("次级入口：在独立窗口打开原文。主路径请用中栏「原文」。")
        .sheet(isPresented: $isInspectorPresented) {
            // Non-primary presentation kept for quick cross-checks from catalogs.
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

/// Primary source reading surface: full-height center/main-column reader.
/// Messages are fully readable and text-selectable for excerpt.
struct ChatConversationSourceStage: View {
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    var purpose: ChatConversationSourcePurpose = .evidence
    var destination: ChatConversationSourceDestination = .readOnly
    /// When false, selection UI stays available but save actions are hidden.
    var allowsExcerpt: Bool = true
    /// Force excerpt chrome (selection + 加入备考库) when stage mode is 摘录.
    var excerptMode: Bool = false

    @State private var selectedTurnID: String?
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var activeMessage: ChatConversationSourceMessage?
    @State private var editorSelection: ChatConversationTextSelection?

    private var summary: ChatConversationSourceSummary {
        store.sourceSummary(for: references)
    }

    private var turns: [ChatConversationSourceTurn] {
        store.sourceTurns(for: references)
    }

    private var canAddToLibrary: Bool {
        guard allowsExcerpt else { return false }
        if case .readOnly = destination { return false }
        return true
    }

    private var showExcerptChrome: Bool {
        // Always allow selecting text; save button respects destination.
        allowsExcerpt
    }

    var body: some View {
        HSplitView {
            turnCatalog
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
            messageReader
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            bootstrapSelection()
        }
        .onChange(of: references.map(\.messageId).joined(separator: "|")) { _, _ in
            selectedTurnID = nil
            activeMessage = nil
            selectedRange = NSRange(location: 0, length: 0)
            bootstrapSelection()
        }
        .sheet(item: Binding(
            get: { editorSelection.map { SelectableEditorItem(selection: $0) } },
            set: { editorSelection = $0?.selection }
        )) { item in
            // Metadata form only — not the source reading path.
            ChatStudyAssetEditorSheet(previewText: item.selection.textSnapshot) { title, kind, subtype, uses in
                saveSelection(item.selection, title: title, kind: kind, subtype: subtype, uses: uses)
            }
        }
    }

    private var turnCatalog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(purpose.title)
                    .font(.headline)
                Text(purpose.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("消息 \(summary.messageCount) · 用户 \(summary.userMessageCount) · 助手 \(summary.assistantMessageCount) · 轮次 \(summary.turnCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if summary.unavailableMessageCount > 0 {
                    Text("有 \(summary.unavailableMessageCount) 条消息在当前归档中不可用")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if summary.attachmentMessageCount > 0 {
                    ChatConversationAttachmentNotice()
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
                    ForEach(turns) { turn in
                        DisclosureGroup(isExpanded: expansion(for: turn.id)) {
                            ForEach(turn.messages) { message in
                                Button {
                                    activeMessage = message
                                    selectedRange = NSRange(location: 0, length: 0)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("\(message.role.rawValue) · \(message.createdAt)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if activeMessage?.id == message.id {
                                                Image(systemName: "text.cursor")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                        }
                                        Text(message.content)
                                            .lineLimit(5)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(activeMessage?.id == message.id
                                                  ? Color.accentColor.opacity(0.12)
                                                  : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        } label: {
                            Text("轮次 \(turn.id)")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var messageReader: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let activeMessage {
                HStack(spacing: 10) {
                    Text("\(activeMessage.role.rawValue)")
                        .font(.headline)
                    Text(activeMessage.reference.messageId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    if showExcerptChrome {
                        Button("摘录到正式库") {
                            captureSelection(from: activeMessage)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedRange.length == 0 || !canAddToLibrary)
                        .help(canAddToLibrary
                              ? "将当前选区写入正式库（origin=userSelection）"
                              : excerptDisabledHelp)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                SelectableSourceTextView(text: activeMessage.content, selectedRange: $selectedRange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if excerptMode || showExcerptChrome {
                    HStack {
                        Text(selectedRange.length > 0
                             ? "已选 \(selectedRange.length) 个 UTF-16 单位"
                             : "在原文中拖选连续文本，再点「摘录到正式库」")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !canAddToLibrary {
                            Text(excerptDisabledHelp)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            } else {
                ContentUnavailableView(
                    "选择一条消息",
                    systemImage: "text.cursor",
                    description: Text("左侧点选消息后，这里显示完整原文，可复制与摘录。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var excerptDisabledHelp: String {
        "当前上下文是只读原文，或缺少可写入的正式片段/候选片段。"
    }

    private func bootstrapSelection() {
        guard activeMessage == nil else { return }
        if let first = turns.first?.messages.first {
            activeMessage = first
            selectedTurnID = turns.first?.id
        }
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedTurnID == nil || selectedTurnID == id },
            set: { isExpanded in
                selectedTurnID = isExpanded ? id : nil
            }
        )
    }

    private func captureSelection(from message: ChatConversationSourceMessage) {
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
            editorSelection = selection
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
        editorSelection = nil
        selectedRange = NSRange(location: 0, length: 0)
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
