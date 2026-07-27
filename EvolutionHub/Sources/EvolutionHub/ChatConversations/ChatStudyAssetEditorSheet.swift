import EvolutionCore
import EvolutionHubCore
import SwiftUI

struct ChatStudyAssetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let previewText: String
    var onSave: (String, ChatStudyAssetKind, String, Set<ChatStudyAssetUse>) -> Void

    @State private var title = ""
    @State private var kind: ChatStudyAssetKind = .expressionModule
    @State private var subtype = ""
    @State private var uses: Set<ChatStudyAssetUse> = [.memorize]

    var body: some View {
        NavigationStack {
            Form {
                Section("摘录正文") {
                    Text(previewText)
                        .textSelection(.enabled)
                }
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
            }
            .formStyle(.grouped)
            .navigationTitle("加入备考库")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title, kind, subtype, uses)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || subtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func binding(for use: ChatStudyAssetUse) -> Binding<Bool> {
        Binding(
            get: { uses.contains(use) },
            set: { isOn in
                if isOn { uses.insert(use) } else { uses.remove(use) }
            }
        )
    }
}
