import SwiftUI

struct TimeEntryNoteEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var note: String
    @FocusState private var isFocused: Bool

    @State private var draft: String

    init(note: Binding<String>) {
        _note = note
        _draft = State(initialValue: note.wrappedValue)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(size: 17))
            .lineSpacing(6)
            .padding(12)
            .focused($isFocused)
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        note = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                isFocused = true
            }
    }
}
