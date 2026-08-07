import SwiftUI

struct TimeEntryNoteEditView: View {
    @Environment(\.dismiss) private var dismiss

    let initialText: String
    let onSave: (String) throws -> Void

    @State private var draft: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(initialText: String, onSave: @escaping (String) throws -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(size: 17))
            .lineSpacing(6)
            .padding(12)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .overlay(alignment: .topLeading) {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("写点补充，可留空……")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityIdentifier("entry.detail.note")
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        do {
                            try onSave(draft)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("note.edit.done")
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            // 不自动聚焦：避免 UI 测试卡在 waitForIdle；用户点编辑器即可输入
    }
}
