import SwiftUI
import SwiftData

struct ThoughtEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var mediaLinks: [ThoughtMediaLink]

    let thought: ThoughtNote
    let entry: TimeEntry?

    @State private var thoughtBody: String
    @State private var errorMessage: String?

    init(thought: ThoughtNote, entry: TimeEntry? = nil) {
        self.thought = thought
        self.entry = entry
        _thoughtBody = State(initialValue: thought.body)
    }

    var body: some View {
        Form {
            Section {
                TextField("思考内容", text: $thoughtBody, axis: .vertical)
                    .lineLimit(1...1000)
                    .lineSpacing(6)
                    .font(.body)
            } header: {
                Text("内容")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("捕获时间：\(DateFormatterFactory.dateTime.string(from: thought.capturedAt))")
                    Text("锚点时间：\(DateFormatterFactory.dateTime.string(from: thought.anchorAt))")
                    Text("关联状态：\(linkSourceText)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if thought.linkedEntryId != nil {
                Section {
                    Button("取消关联", role: .destructive, action: unlink)
                }
            }

            Section {
                Button("删除", role: .destructive, action: deleteThought)
            }
        }
        .navigationTitle("编辑思考")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: save)
                    .disabled(
                        thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !hasAttachedMedia
                    )
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var linkSourceText: String {
        switch thought.linkSourceEnum {
        case .none: "等待匹配"
        case .auto: "自动关联"
        case .manual: "手动关联"
        }
    }

    private var hasAttachedMedia: Bool {
        mediaLinks.contains { $0.thoughtId == thought.id }
    }

    private func save() {
        do {
            try ThoughtLinkingService(modelContext: modelContext).updateThought(thought, body: thoughtBody)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unlink() {
        do {
            try ThoughtLinkingService(modelContext: modelContext).unlinkThought(thought)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteThought() {
        do {
            try ThoughtLinkingService(modelContext: modelContext).deleteThought(thought)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
