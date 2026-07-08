import SwiftUI

struct ThoughtAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var thoughtBody: String = ""

    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("思考内容", text: $thoughtBody, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("事后补充")
                } footer: {
                    Text("这条思考会关联到当前时间段，关联方式为手动关联。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加思考")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        let trimmed = thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
