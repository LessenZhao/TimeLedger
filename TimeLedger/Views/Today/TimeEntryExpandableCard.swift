import SwiftUI
import UIKit

struct TimeEntryExpandableCard: View {
    let entry: TimeEntry
    let thoughts: [ThoughtNote]
    let mediaMoments: [MediaMoment]
    let actionCount: Int
    let onEdit: () -> Void

    @State private var isExpanded = false
    @State private var expandedThoughtIDs: Set<UUID> = []
    @State private var selectedMedia: MediaMoment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
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
                            Text(timeAndNote)
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

                        if SystemProject.isUnknownEntry(entry) || actionCount > 0 {
                            HStack(spacing: 6) {
                                if SystemProject.isUnknownEntry(entry) {
                                    badge("待选项目", color: .orange)
                                }
                                if actionCount > 0 {
                                    Text("事项 \(actionCount)")
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
                    "\(isExpanded ? "收起" : "展开") \(entry.projectNameSnapshot)"
                )
                .accessibilityIdentifier("timeEntry.expand.\(entry.id.uuidString)")

                HStack(spacing: 0) {
                    Button {
                        toggleExpansion()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(isExpanded ? "收起详情" : "展开详情") \(entry.projectNameSnapshot)"
                    )

                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("编辑 \(entry.projectNameSnapshot)")
                    .accessibilityIdentifier("timeEntry.edit.\(entry.id.uuidString)")
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
        if thoughts.isEmpty && mediaMoments.isEmpty {
            Text("没有关联的思考、照片或视频")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(thoughts) { thought in
                Button {
                    if expandedThoughtIDs.contains(thought.id) {
                        expandedThoughtIDs.remove(thought.id)
                    } else {
                        expandedThoughtIDs.insert(thought.id)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(thought.body)
                                .font(.subheadline)
                                .lineLimit(expandedThoughtIDs.contains(thought.id) ? nil : 3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeEntry.thought.\(thought.id.uuidString)")
            }

            ForEach(mediaMoments) { moment in
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
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
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

    private var timeAndNote: String {
        let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
        let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
        let duration = DurationFormatter.compact(entry.durationSeconds)
        let trimmed = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(start) – \(end) · \(duration)"
        return trimmed.isEmpty ? base : "\(base) · \(trimmed)"
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
