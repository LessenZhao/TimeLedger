import SwiftUI
import SwiftData

struct ThoughtEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let thought: ThoughtNote
    let entry: TimeEntry?

    @State private var thoughtBody: String
    @State private var hasAttachedMedia = false
    @State private var didLoadMediaState = false
    @State private var errorMessage: String?
    @State private var showingUnlinkConfirm = false
    @FocusState private var isBodyFocused: Bool

    init(thought: ThoughtNote, entry: TimeEntry? = nil) {
        self.thought = thought
        self.entry = entry
        _thoughtBody = State(initialValue: thought.body)
    }

    var body: some View {
        RichCardContentView(
            target: .thought(thought),
            mode: .edit,
            onSave: { dismiss() },
            onCancel: { dismiss() }
        )
    }

    private var metaHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("捕获时间：\(DateFormatterFactory.dateTime.string(from: thought.capturedAt))")
            Text("锚点时间：\(DateFormatterFactory.dateTime.string(from: thought.anchorAt))")
            Text("关联状态：\(linkSourceText)")
            if hasAttachedMedia {
                Text("已附带媒体")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionFooter: some View {
        HStack(spacing: 12) {
            if thought.linkedEntryId != nil {
                Button("取消关联", role: .destructive) {
                    showingUnlinkConfirm = true
                }
                .accessibilityIdentifier("timeline.thoughtEdit.unlink")
            }

            Spacer()

            Button("删除", role: .destructive, action: deleteThought)
                .accessibilityIdentifier("thought.edit.delete")
        }
        .font(.subheadline.weight(.medium))
    }

    private var linkSourceText: String {
        switch thought.linkSourceEnum {
        case .none: "等待匹配"
        case .auto: "自动关联"
        case .manual: "手动关联"
        }
    }

    private var unlinkMessage: String {
        if let entry {
            let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
            let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
            return "将解除与「\(entry.projectNameSnapshot)」\(start)–\(end) 的关联。"
        }
        return "将解除与当前时间条目的关联。"
    }

    private var saveDisabled: Bool {
        !didLoadMediaState
            || (
                thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !hasAttachedMedia
            )
    }

    @MainActor
    private func loadMediaState() async {
        do {
            hasAttachedMedia = try ThoughtMediaLinkService(modelContext: modelContext)
                .hasAttachedMedia(for: thought)
            didLoadMediaState = true
        } catch {
            didLoadMediaState = true
            hasAttachedMedia = false
            errorMessage = "无法读取媒体状态：\(error.localizedDescription)"
        }
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
