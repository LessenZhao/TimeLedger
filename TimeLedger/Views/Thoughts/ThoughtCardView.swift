import SwiftData
import SwiftUI

struct ThoughtCardView: View {
    @Environment(\.modelContext) private var modelContext

    let thought: ThoughtNote
    let linkedEntry: TimeEntry?
    let mediaMoments: [MediaMoment]

    @State private var showingEdit = false
    @State private var showingManualLink = false
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var isExpanded = false
    @State private var selectedMedia: MediaMoment?

    init(
        thought: ThoughtNote,
        linkedEntry: TimeEntry?,
        mediaMoments: [MediaMoment] = []
    ) {
        self.thought = thought
        self.linkedEntry = linkedEntry
        self.mediaMoments = mediaMoments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                lifecycleBadge
            }

            if !thought.body.isEmpty {
                Text(thought.body)
                    .font(.body)
                    .lineLimit(isExpanded ? nil : 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    }
                    .accessibilityHint(isExpanded ? "轻点收起" : "轻点展开全文")
            }

            if !mediaMoments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mediaMoments) { moment in
                            Button {
                                selectedMedia = moment
                            } label: {
                                attachmentThumbnail(moment)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(moment.kind == .photo ? "查看照片" : "查看视频")
                        }
                    }
                }
            }

            if let linkedEntry {
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
            ThoughtManualLinkView(thought: thought, date: thought.capturedAt)
        }
        .fullScreenCover(item: $selectedMedia) { moment in
            MediaViewer(moment: moment)
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

    @ViewBuilder
    private var lifecycleBadge: some View {
        switch lifecycle {
        case .unlinked:
            badge("未关联", color: .secondary, fill: Color.gray.opacity(0.12))
        case .draft:
            badge("草稿", color: .orange, fill: Color.orange.opacity(0.12))
        case .confirmed:
            badge("已确认", color: .green, fill: Color.green.opacity(0.12))
        case .orphaned:
            badge("关联失效", color: .red, fill: Color.red.opacity(0.12))
        }
    }

    private var lifecycle: ThoughtLifecycle {
        if let linkedEntry {
            switch linkedEntry.entryStatus {
            case .draft:
                return .draft
            case .confirmed:
                return .confirmed
            }
        }
        if thought.linkedEntryId != nil {
            return .orphaned
        }
        return .unlinked
    }

    private func badge(_ title: String, color: Color, fill: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
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

    private func attachmentThumbnail(_ moment: MediaMoment) -> some View {
        TimelineThumbnailView(
            mediaID: moment.id,
            thumbnailData: moment.thumbnailData,
            kind: moment.kind,
            size: CGSize(width: 104, height: 78)
        )
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

private enum ThoughtLifecycle {
    case unlinked
    case draft
    case confirmed
    case orphaned
}
