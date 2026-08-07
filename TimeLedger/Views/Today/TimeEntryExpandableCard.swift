import SwiftUI
import UIKit

struct TimeEntryExpandableCard: View {
    let entry: TimeEntry
    let thoughts: [ThoughtNote]
    let mediaMoments: [MediaMoment]
    let thoughtMediaLinks: [ThoughtMediaLink]
    let actionTitles: [String]
    let onEditThought: (ThoughtNote) -> Void
    let onEdit: () -> Void

    @State private var isExpanded = false
    @State private var selectedMedia: MediaMoment?

    init(
        entry: TimeEntry,
        thoughts: [ThoughtNote],
        mediaMoments: [MediaMoment],
        thoughtMediaLinks: [ThoughtMediaLink] = [],
        actionTitles: [String] = [],
        onEditThought: @escaping (ThoughtNote) -> Void = { _ in },
        onEdit: @escaping () -> Void
    ) {
        self.entry = entry
        self.thoughts = thoughts
        self.mediaMoments = mediaMoments
        self.thoughtMediaLinks = thoughtMediaLinks
        self.actionTitles = actionTitles
        self.onEditThought = onEditThought
        self.onEdit = onEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: TimelineCardActionMetrics.spacing) {
                Button {
                    toggleExpansion()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.projectNameSnapshot)
                                .font(TLTheme.projectNameFont)
                                .foregroundStyle(
                                    SystemProject.isUnknownEntry(entry)
                                        ? Color.orange
                                        : Color.primary
                                )
                                .lineLimit(1)
                            Text(timeRangeText)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !contentTimes.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(contentTimes) { item in
                                    Label(item.title, systemImage: item.icon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if SystemProject.isUnknownEntry(entry) || !actionTitles.isEmpty {
                            HStack(spacing: 6) {
                                if SystemProject.isUnknownEntry(entry) {
                                    badge("待选项目", color: .orange)
                                }
                                if !actionTitles.isEmpty {
                                    Text("事项 \(actionTitles.count)")
                                        .font(TLTheme.metaFont)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "展开内容 \(entry.projectNameSnapshot)"
                )
                .accessibilityIdentifier("timeEntry.body.\(entry.id.uuidString)")

                HStack(spacing: TimelineCardActionMetrics.spacing) {
                    Button {
                        toggleExpansion()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(
                                minWidth: TimelineCardActionMetrics.minTouch,
                                minHeight: TimelineCardActionMetrics.minTouch
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .layoutPriority(1)
                    .accessibilityLabel(
                        "\(isExpanded ? "收起详情" : "展开详情") \(entry.projectNameSnapshot)"
                    )

                    VisibleEditButton(
                        accessibilityLabel: "编辑 \(entry.projectNameSnapshot)",
                        accessibilityIdentifier: "timeEntry.edit.\(entry.id.uuidString)",
                        action: onEdit
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if !trimmedNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("备注", systemImage: "text.alignleft")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timeEntry.note.label")

                    TimelineExpandableText(
                        text: trimmedNote,
                        collapsedLineLimit: 2,
                        accessibilityPrefix: "timeEntry.note",
                        style: .note
                    )
                }
            }

            if isExpanded {
                Divider()
                expandedContents
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, TLTheme.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                .fill(TLTheme.cardBackground)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeEntry.card.\(entry.entryStatus.rawValue)")
        .fullScreenCover(item: $selectedMedia) { moment in
            MediaViewer(moment: moment)
        }
    }

    @ViewBuilder
    private var expandedContents: some View {
        if thoughts.isEmpty && entryOnlyMedia.isEmpty && actionTitles.isEmpty && trimmedNote.isEmpty {
            Text("没有关联的思考、照片或视频")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if !actionTitles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("完成事项")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(actionTitles.enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(.subheadline)
                    }
                }
                .accessibilityIdentifier("entry.actions")
            }

            ForEach(thoughts) { thought in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: TimelineCardActionMetrics.spacing) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.orange)
                        Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        VisibleEditButton(
                            accessibilityLabel: "编辑关联思考",
                            accessibilityIdentifier: "timeEntry.thought.edit",
                            action: { onEditThought(thought) }
                        )
                    }

                    if !thought.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TimelineExpandableText(
                            text: thought.body,
                            collapsedLineLimit: 6,
                            accessibilityPrefix: "timeEntry.thought.body",
                            style: .thought
                        )
                    } else {
                        Text("暂无文字内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    let moments = media(for: thought)
                    if !moments.isEmpty {
                        TimelineMediaGrid(moments: moments) { moment in
                            selectedMedia = moment
                        }
                    }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("timeEntry.thought.card")
            }

            ForEach(entryOnlyMedia) { moment in
                Button {
                    selectedMedia = moment
                } label: {
                    HStack(spacing: 10) {
                        mediaThumbnail(moment)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(DateFormatterFactory.timeOnly.string(from: moment.capturedAt))
                                .font(.caption.weight(.semibold))
                            Text(moment.kind == .photo ? "照片" : "视频")
                                .font(.subheadline)
                            if moment.kind == .video {
                                Text(DurationFormatter.compact(moment.durationSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if moment.saveStatus == .partial || moment.saveStatus == .failed {
                                Text(moment.saveStatus == .partial ? "部分保存" : "保存失败")
                                    .font(.caption)
                                    .foregroundStyle(
                                        moment.saveStatus == .partial ? Color.orange : Color.red
                                    )
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(moment.kind == .photo ? "查看照片" : "查看视频")
                .accessibilityIdentifier("timeEntry.media.\(moment.id.uuidString)")
            }
        }
    }

    private var contentTimes: [EntryContentTime] {
        let thoughtItems = thoughts.map {
            EntryContentTime(
                id: "thought-\($0.id.uuidString)",
                title: "思考 \(DateFormatterFactory.timeOnly.string(from: $0.capturedAt))",
                icon: "lightbulb"
            )
        }
        let mediaItems = mediaMoments.map {
            EntryContentTime(
                id: "media-\($0.id.uuidString)",
                title: "\($0.kind == .photo ? "照片" : "视频") \(DateFormatterFactory.timeOnly.string(from: $0.capturedAt))",
                icon: $0.kind == .photo ? "photo" : "video"
            )
        }
        return thoughtItems + mediaItems
    }

    private var timeRangeText: String {
        let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
        let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
        let duration = DurationFormatter.compact(entry.durationSeconds)
        return "\(start) – \(end) · \(duration)"
    }

    private var trimmedNote: String {
        entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func media(for thought: ThoughtNote) -> [MediaMoment] {
        let order = Dictionary(
            uniqueKeysWithValues: thoughtMediaLinks
                .filter { $0.thoughtId == thought.id }
                .map { ($0.mediaMomentId, $0.sortOrder) }
        )
        return mediaMoments
            .filter { order[$0.id] != nil }
            .sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    private var entryOnlyMedia: [MediaMoment] {
        let linkedIDs = Set(thoughtMediaLinks.map(\.mediaMomentId))
        return mediaMoments
            .filter { !linkedIDs.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isExpanded.toggle()
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func mediaThumbnail(_ moment: MediaMoment) -> some View {
        Group {
            if let image = UIImage(data: moment.thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: moment.kind == .photo ? "photo" : "video")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 68, height: 52)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct EntryContentTime: Identifiable {
    let id: String
    let title: String
    let icon: String
}
