import SwiftData
import SwiftUI

struct MediaMomentCard: View {
    @Environment(\.modelContext) private var modelContext

    let moment: MediaMoment
    let linkedEntry: TimeEntry?
    let displayStartAt: Date?
    let displayEndAt: Date?
    let isRelatedToNote: Bool
    let onEdit: (() -> Void)?

    @State private var showingViewer = false
    @State private var showingManualLink = false
    @State private var showingDeleteAlert = false
    @State private var showingUnlinkConfirm = false
    @State private var errorMessage: String?

    init(
        moment: MediaMoment,
        linkedEntry: TimeEntry?,
        displayStartAt: Date? = nil,
        displayEndAt: Date? = nil,
        isRelatedToNote: Bool = false,
        onEdit: (() -> Void)? = nil
    ) {
        self.moment = moment
        self.linkedEntry = linkedEntry
        self.displayStartAt = displayStartAt
        self.displayEndAt = displayEndAt
        self.isRelatedToNote = isRelatedToNote
        self.onEdit = onEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: TimelineCardActionMetrics.spacing) {
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TimelineKindBadge(
                    title: "思考",
                    tint: Color.purple.opacity(0.16),
                    foreground: Color.purple
                )
                if let onEdit {
                    VisibleEditButton(
                        accessibilityLabel: "编辑",
                        accessibilityIdentifier: "timeline.media.edit",
                        action: onEdit
                    )
                }
                menuButton
            }

            TimelineMediaGrid(moments: [moment]) { _ in
                showingViewer = true
            }

            HStack(spacing: 6) {
                Image(systemName: moment.kind == .photo ? "photo" : "video")
                Text(moment.kind == .photo ? "照片" : "视频")
                    .fontWeight(.semibold)
                if moment.kind == .video {
                    Text("· \(DurationFormatter.compact(moment.durationSeconds))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            Text(linkedEntry?.projectNameSnapshot ?? "未关联时间项目")
                .font(.caption)
                .foregroundStyle(linkedEntry == nil ? Color.orange : Color.secondary)

            if isRelatedToNote {
                Text("关联备注")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("timeline.media.relatedNote")
            }

            statusLine
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.card.media")
        .fullScreenCover(isPresented: $showingViewer) {
            MediaViewer(moment: moment)
        }
        .sheet(isPresented: $showingManualLink) {
            MediaManualLinkView(moment: moment)
        }
        .alert("删除这条媒体记录？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    await MediaMomentService(modelContext: modelContext).deleteRecord(moment)
                }
            }
        } message: {
            Text("只删除 TimeLedger 中的 App 文件、缩略图和记录，绝不会删除系统相册原件。")
        }
        .alert("取消关联？", isPresented: $showingUnlinkConfirm) {
            Button("保留关联", role: .cancel) {}
            Button("确认取消关联", role: .destructive, action: unlink)
        } message: {
            Text(unlinkMessage)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await MediaMomentService(modelContext: modelContext)
                .refreshOriginalAvailability(moment)
        }
    }

    private var menuButton: some View {
        Menu {
            if moment.linkedEntryId == nil {
                Button("手动关联") { showingManualLink = true }
            } else {
                Button("取消关联", role: .destructive) {
                    showingUnlinkConfirm = true
                }
                .accessibilityIdentifier("timeline.media.unlink")
            }

            if moment.saveStatus == .partial || moment.saveStatus == .failed {
                Button("重试") {
                    Task {
                        await MediaMomentService(modelContext: modelContext).retry(moment)
                    }
                }
                Button("改存 App") {
                    Task {
                        await MediaMomentService(modelContext: modelContext).saveToAppInstead(moment)
                    }
                }
            }

            Button("删除", role: .destructive) {
                showingDeleteAlert = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(
                    minWidth: TimelineCardActionMetrics.minTouch,
                    minHeight: TimelineCardActionMetrics.minTouch
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多操作")
        .accessibilityIdentifier("timeline.media.menu")
    }

    private var timeText: String {
        let start = displayStartAt ?? moment.capturedAt
        if let end = displayEndAt {
            let startText = DateFormatterFactory.timeOnly.string(from: start)
            let endText = DateFormatterFactory.timeOnly.string(from: end)
            return "\(startText) – \(endText)"
        }
        return DateFormatterFactory.dateTime.string(from: start)
    }

    private var unlinkMessage: String {
        if let linkedEntry {
            let start = DateFormatterFactory.timeOnly.string(from: linkedEntry.startAt)
            let end = DateFormatterFactory.timeOnly.string(from: linkedEntry.endAt)
            return "将解除与「\(linkedEntry.projectNameSnapshot)」\(start)–\(end) 的关联。"
        }
        return "将解除与当前时间条目的关联。"
    }

    @ViewBuilder
    private var statusLine: some View {
        if moment.availability == .unavailable {
            Label("原件不可用", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        } else if moment.saveStatus == .partial {
            Label("部分保存，原件已保留", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if moment.saveStatus == .failed {
            Label("保存失败，原件待重试", systemImage: "xmark.circle")
                .foregroundStyle(.red)
                .font(.caption)
        } else if moment.saveStatus == .pending {
            Label("正在保存", systemImage: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func unlink() {
        do {
            try MediaLinkingService(modelContext: modelContext).unlink(moment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
