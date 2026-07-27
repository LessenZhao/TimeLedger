import EvolutionCore
import EvolutionHubCore
import SwiftUI

enum ChatConversationSourcePurpose {
    case coverage
    case evidence

    var buttonLabel: String {
        switch self {
        case .coverage: return "查看处理材料"
        case .evidence: return "查看原文上下文"
        }
    }

    var title: String {
        switch self {
        case .coverage: return "已覆盖原始消息"
        case .evidence: return "资产引用的原始消息"
        }
    }

    var explanation: String {
        switch self {
        case .coverage:
            return "这些消息已被本次处理覆盖；它们不一定都直接证明同一条资产。"
        case .evidence:
            return "这些消息是该资产引用的对话材料；可选择连续文本加入备考库。"
        }
    }
}

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
        .sheet(isPresented: $isInspectorPresented) {
            ChatConversationSourceInspector(
                store: store,
                references: references,
                purpose: purpose,
                destination: destination
            )
        }
    }
}

private struct ChatConversationSourceInspector: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ChatConversationHubStore
    let references: [ChatConversationMessageReference]
    let purpose: ChatConversationSourcePurpose
    let destination: ChatConversationSourceDestination
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

    var body: some View {
        NavigationStack {
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text(purpose.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("消息 \(summary.messageCount) · 用户 \(summary.userMessageCount) · 助手 \(summary.assistantMessageCount) · 轮次 \(summary.turnCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(turns) { turn in
                            DisclosureGroup(isExpanded: expansion(for: turn.id)) {
                                ForEach(turn.messages) { message in
                                    Button {
                                        activeMessage = message
                                        selectedRange = NSRange(location: 0, length: 0)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(message.role.rawValue) · \(message.createdAt)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(message.content)
                                                .lineLimit(4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            } label: {
                                Text("轮次 \(turn.id)")
                            }
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 280)

                VStack(alignment: .leading, spacing: 10) {
                    if let activeMessage {
                        Text("\(activeMessage.role.rawValue) · \(activeMessage.reference.messageId)")
                            .font(.headline)
                        SelectableSourceTextView(text: activeMessage.content, selectedRange: $selectedRange)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if canAddToLibrary {
                            Button("加入备考库") {
                                do {
                                    let selection = try ChatConversationTextSelection.make(
                                        conversationID: activeMessage.reference.conversationId,
                                        message: ChatConversationMessage(
                                            id: activeMessage.reference.messageId,
                                            role: activeMessage.role,
                                            createdAt: activeMessage.createdAt,
                                            content: activeMessage.content
                                        ),
                                        rangeUTF16: selectedRange
                                    )
                                    editorSelection = selection
                                } catch {
                                    // Invalid selection stays local to the inspector.
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedRange.length == 0)
                        }
                    } else {
                        ContentUnavailableView("选择一条消息", systemImage: "text.cursor")
                    }
                }
                .padding()
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(purpose.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { editorSelection.map { SelectableEditorItem(selection: $0) } },
                set: { editorSelection = $0?.selection }
            )) { item in
                ChatStudyAssetEditorSheet(previewText: item.selection.textSnapshot) { title, kind, subtype, uses in
                    saveSelection(item.selection, title: title, kind: kind, subtype: subtype, uses: uses)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var canAddToLibrary: Bool {
        if case .readOnly = destination { return false }
        return true
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedTurnID == nil || selectedTurnID == id },
            set: { isExpanded in
                selectedTurnID = isExpanded ? id : nil
            }
        )
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
    }
}

private struct SelectableEditorItem: Identifiable {
    var selection: ChatConversationTextSelection
    var id: String { "\(selection.span.message.messageId)-\(selection.span.locationUTF16)-\(selection.span.lengthUTF16)" }
}

