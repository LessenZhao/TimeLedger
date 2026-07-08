import SwiftUI
import SwiftData

struct ThoughtCardView: View {
    @Environment(\.modelContext) private var modelContext

    let thought: ThoughtNote
    let date: Date

    @State private var showingEdit = false
    @State private var showingManualLink = false
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?

    var body: some View {
 VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                linkStatusBadge
            }

            Text(thought.body)
                .font(.body)
                .lineLimit(nil)

            if let linkedEntry = linkedEntry {
                linkedEntryInfo(linkedEntry)
            }

            HStack(spacing: 16) {
                Button {
                    showingEdit = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .font(.caption)

                if thought.linkedEntryId != nil {
                    Button(role: .destructive) {
                        unlink()
                    } label: {
                        Label("取消关联", systemImage: "link.badge.plus")
                    }
                    .font(.caption)
                } else {
                    Button {
                        showingManualLink = true
                    } label: {
                        Label("手动关联", systemImage: "link")
                    }
                    .font(.caption)
                }

                Spacer()

                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ThoughtEditView(thought: thought)
            }
        }
        .sheet(isPresented: $showingManualLink) {
            ThoughtManualLinkView(thought: thought, date: date)
        }
        .alert("删除这条思考？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteThought)
        } message: {
            Text("删除后无法恢复。")
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

    private var linkedEntry: TimeEntry? {
        guard let entryId = thought.linkedEntryId else { return nil }
        let entries = (try? modelContext.fetch(FetchDescriptor<TimeEntry>())) ?? []
        return entries.first { $0.id == entryId }
    }

    @ViewBuilder
    private var linkStatusBadge: some View {
        switch thought.linkSourceEnum {
        case .auto:
            Text("自动关联")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
        case .manual:
            Text("手动关联")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.blue.opacity(0.12)))
        case .none:
            Text("等待匹配")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.gray.opacity(0.12)))
        }
    }

    private func linkedEntryInfo(_ entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("关联：\(DateFormatterFactory.timeOnly.string(from: entry.startAt)) - \(DateFormatterFactory.timeOnly.string(from: entry.endAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.projectNameSnapshot)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func unlink() {
        do {
            try ThoughtLinkingService(modelContext: modelContext).unlinkThought(thought)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteThought() {
        do {
            try ThoughtLinkingService(modelContext: modelContext).deleteThought(thought)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
