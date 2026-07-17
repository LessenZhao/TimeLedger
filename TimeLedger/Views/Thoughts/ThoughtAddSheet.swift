import SwiftUI

struct ThoughtAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var thoughtBody: String = ""

    private let draftStore = ThoughtDraftStore()
    let onSave: (String) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $thoughtBody)
                        .font(.body)
                        .frame(minHeight: 280)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("思考内容")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
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
                        if onSave(trimmed) {
                            draftStore.clear(.addToEntry)
                            dismiss()
                        }
                    }
                    .disabled(thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                thoughtBody = draftStore.load(.addToEntry)
            }
            .onChange(of: thoughtBody) { _, newValue in
                draftStore.save(newValue, for: .addToEntry)
            }
        }
    }
}
