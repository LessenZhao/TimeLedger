import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatCandidateAssetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preservation: ChatStudyAssetPreservation
    let onSave: (
        String,
        ChatStudyAssetKind,
        String,
        Set<ChatStudyAssetUse>,
        String?
    ) -> Void

    @State private var title: String
    @State private var kind: ChatStudyAssetKind
    @State private var subtype: String
    @State private var uses: Set<ChatStudyAssetUse>
    @State private var draftText: String

    init(
        asset: ChatConversationProposalAsset,
        onSave: @escaping (
            String,
            ChatStudyAssetKind,
            String,
            Set<ChatStudyAssetUse>,
            String?
        ) -> Void
    ) {
        preservation = asset.preservation
        self.onSave = onSave
        _title = State(initialValue: asset.title)
        _kind = State(initialValue: asset.kind)
        _subtype = State(initialValue: asset.subtype)
        _uses = State(initialValue: asset.uses)
        _draftText = State(initialValue: asset.draftText ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    TextField("标题", text: $title)
                    Picker("一级类型", selection: $kind) {
                        ForEach(ChatStudyAssetKind.allCases, id: \.self) { item in
                            Text(ChatStudyAssetKindLabel.title(for: item)).tag(item)
                        }
                    }
                    TextField("二级类型", text: $subtype)
                    ForEach(ChatStudyAssetUse.allCases, id: \.self) { use in
                        Toggle(ChatStudyAssetUseLabel.title(for: use), isOn: binding(for: use))
                    }
                }

                Section("正文") {
                    if preservation == .distilled {
                        TextEditor(text: $draftText)
                            .frame(minHeight: 160)
                    } else {
                        Text("原文正文不能手工改写。如AI选择范围不准确，请打开原文重新选择，新增人工摘录，并排除错误候选。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑候选")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            normalizedTitle,
                            kind,
                            normalizedSubtype,
                            uses,
                            preservation == .distilled ? draftText : nil
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSubtype: String {
        subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty
            && !normalizedSubtype.isEmpty
            && !uses.isEmpty
            && (preservation == .verbatim
                || !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func binding(for use: ChatStudyAssetUse) -> Binding<Bool> {
        Binding(
            get: { uses.contains(use) },
            set: { isOn in
                if isOn {
                    uses.insert(use)
                } else {
                    uses.remove(use)
                }
            }
        )
    }
}
