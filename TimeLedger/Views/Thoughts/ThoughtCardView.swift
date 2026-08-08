import SwiftData
import SwiftUI

struct ThoughtCardView: View {
    @Environment(\.modelContext) private var modelContext

    let journal: JournalEntry
    let bodyText: String
    let linkedEntry: TimeEntry?
    let mediaMoments: [MediaMoment]
    let displayStartAt: Date?
    let displayEndAt: Date?
    let isRelatedToNote: Bool
    let onEdit: () -> Void

    @State private var showingManualLink = false
    @State private var showingDeleteAlert = false
    @State private var showingUnlinkConfirm = false
    @State private var errorMessage: String?
    @State private var selectedMedia: MediaMoment?

    init(
        journal: JournalEntry,
        body: String,
        linkedEntry: TimeEntry?,
        mediaMoments: [MediaMoment] = [],
        displayStartAt: Date? = nil,
        displayEndAt: Date? = nil,
        isRelatedToNote: Bool = false,
        onEdit: @escaping () -> Void = {}
    ) {
        self.journal = journal
        self.bodyText = body
        self.linkedEntry = linkedEntry
        self.mediaMoments = mediaMoments
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
                    .lineLimit(1)
                Spacer(minLength: 8)
                TimelineKindBadge(title: "随记", tint: Color.purple.opacity(0.16), foreground: Color.purple)
                favoriteButton
                VisibleEditButton(
                    accessibilityLabel: "编辑",
                    accessibilityIdentifier: "timeline.thought.edit",
                    action: onEdit
                )
                menuButton
                    .fixedSize()
                    .layoutPriority(1)
            }
            .zIndex(1)

            if !bodyText.isEmpty {
                TimelineExpandableText(text: bodyText, style: .thought)
            }

            if !mediaMoments.isEmpty {
                TimelineMediaGrid(moments: mediaMoments) { moment in
                    selectedMedia = moment
                }
                if bodyText.isEmpty {
                    HStack(spacing: 8) {
                        if mediaMoments.contains(where: { $0.kind == .photo }) {
                            Label("照片", systemImage: "photo")
                        }
                        if mediaMoments.contains(where: { $0.kind == .video }) {
                            Label("视频", systemImage: "video")
                            if let video = mediaMoments.first(where: { $0.kind == .video }) {
                                Text("· \(DurationFormatter.compact(video.durationSeconds))")
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }

            secondaryMeta
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.card.thought")
        .sheet(isPresented: $showingManualLink) {
            ThoughtManualLinkView(journal: journal, date: journal.capturedAt)
        }
        .fullScreenCover(item: $selectedMedia) { moment in
            MediaViewer(moment: moment)
        }
        .alert("删除这条随记？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteThought)
        } message: {
            Text("删除后无法恢复。")
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: journal.isFavorite ? "star.fill" : "star")
                .font(.body.weight(.semibold))
                .foregroundStyle(journal.isFavorite ? Color.yellow : .secondary)
                .frame(
                    width: TimelineCardActionMetrics.minTouch,
                    height: TimelineCardActionMetrics.minTouch
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(journal.isFavorite ? "取消收藏随记" : "收藏随记")
        .accessibilityIdentifier("timeline.thought.favorite")
    }

    private func toggleFavorite() {
        do {
            try JournalContentService(modelContext: modelContext).setFavorite(journal, !journal.isFavorite)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var menuButton: some View {
        Menu {
            if linkedEntry != nil {
                Button("取消关联", role: .destructive) {
                    showingUnlinkConfirm = true
                }
                .accessibilityIdentifier("timeline.thought.unlink")
            } else {
                Button("手动关联") { showingManualLink = true }
                    .accessibilityIdentifier("timeline.thought.link")
            }

            Button("删除", role: .destructive) {
                showingDeleteAlert = true
            }
            .accessibilityIdentifier("timeline.thought.delete")
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
        .accessibilityIdentifier(
            linkedEntry == nil
                ? "timeline.thought.menu.unlinked"
                : "timeline.thought.menu.linked"
        )
    }

    @ViewBuilder
    private var secondaryMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRelatedToNote {
                Text("关联时间记录")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("timeline.thought.relatedNote")
            }

            if let linkedEntry {
                Text("\(linkedEntry.projectNameSnapshot) · \(lifecycleTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("未关联")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeText: String {
        let start = displayStartAt ?? journal.capturedAt
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

    private var lifecycleTitle: String {
        switch linkedEntry?.entryStatus {
        case .draft: "待确认"
        case .confirmed: "已确认"
        case nil: "未关联"
        }
    }

    private func unlink() {
        do {
            try JournalContentService(modelContext: modelContext).unlink(journal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteThought() {
        do {
            try JournalContentService(modelContext: modelContext).delete(journal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shared timeline card pieces

enum TimelineCardStyle {
    static let cornerRadius: CGFloat = 18
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
}

enum TimelineCardActionMetrics {
    static let minTouch: CGFloat = 44
    static let spacing: CGFloat = 8
}

struct VisibleEditButton: View {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                Text("编辑")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .frame(height: TimelineCardActionMetrics.minTouch)
            .frame(minWidth: TimelineCardActionMetrics.minTouch)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct TimelineKindBadge: View {
    let title: String
    let tint: Color
    let foreground: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint))
            .accessibilityIdentifier(title == "时间记录" ? "timeline.badge.note" : "timeline.badge.thought")
    }
}

struct TimelineExpandableText: View {
    enum Style {
        case note
        case thought

        var font: Font {
            switch self {
            case .note: .subheadline
            case .thought: .system(size: 17)
            }
        }

        var foregroundStyle: Color {
            switch self {
            case .note: .secondary
            case .thought: .primary
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .note: 3
            case .thought: 5
            }
        }
    }

    let text: String
    var collapsedLineLimit: Int = 6
    var accessibilityPrefix: String = "timeline.body"
    var style: Style = .thought

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard isTruncated || isExpanded else { return }
                toggle()
            } label: {
                Text(text)
                    .font(style.font)
                    .lineSpacing(style.lineSpacing)
                    .foregroundStyle(style.foregroundStyle)
                    .lineLimit(isExpanded ? nil : collapsedLineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(truncationReader)
            .accessibilityIdentifier("\(accessibilityPrefix).text")
            .accessibilityHint(isTruncated || isExpanded ? "点按展开或收起" : "")

            if isTruncated || isExpanded {
                Button(isExpanded ? "收起" : "展开") {
                    toggle()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: TimelineCardActionMetrics.minTouch, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier(
                    isExpanded
                        ? "\(accessibilityPrefix).collapse"
                        : "\(accessibilityPrefix).expand"
                )
            }
        }
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isExpanded.toggle()
        }
    }

    private var truncationReader: some View {
        Text(text)
            .font(style.font)
            .lineSpacing(style.lineSpacing)
            .lineLimit(collapsedLineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay {
                GeometryReader { collapsedProxy in
                    Text(text)
                        .font(style.font)
                        .lineSpacing(style.lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: collapsedProxy.size.width, alignment: .leading)
                        .hidden()
                        .background(
                            GeometryReader { fullProxy in
                                Color.clear.preference(
                                    key: TimelineTextHeightKey.self,
                                    value: TimelineTextHeights(
                                        collapsed: collapsedProxy.size.height,
                                        full: fullProxy.size.height
                                    )
                                )
                            }
                        )
                }
            }
            .onPreferenceChange(TimelineTextHeightKey.self) { heights in
                isTruncated = heights.full > heights.collapsed + 1
            }
    }
}

private struct TimelineTextHeights: Equatable {
    var collapsed: CGFloat
    var full: CGFloat
}

private struct TimelineTextHeightKey: PreferenceKey {
    static var defaultValue = TimelineTextHeights(collapsed: 0, full: 0)
    static func reduce(value: inout TimelineTextHeights, nextValue: () -> TimelineTextHeights) {
        value = nextValue()
    }
}

struct TimelineMediaGrid: View {
    let moments: [MediaMoment]
    let onSelect: (MediaMoment) -> Void

    private let spacing: CGFloat = 6

    @ViewBuilder
    var body: some View {
        switch moments.count {
        case 0:
            EmptyView()
        case 1:
            cell(moments[0], aspectRatio: 1 / 0.62)
        case 2:
            HStack(spacing: spacing) {
                cell(moments[0], aspectRatio: 1)
                cell(moments[1], aspectRatio: 1)
            }
        default:
            let visible = Array(moments.prefix(3))
            let overflow = moments.count - 3
            HStack(spacing: spacing) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, moment in
                    cell(
                        moment,
                        aspectRatio: 1,
                        badge: index == 2 && overflow > 0 ? "+\(overflow)" : nil
                    )
                }
            }
        }
    }

    private func cell(
        _ moment: MediaMoment,
        aspectRatio: CGFloat,
        badge: String? = nil
    ) -> some View {
        Button {
            onSelect(moment)
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    TimelineThumbnailView(
                        mediaID: moment.id,
                        thumbnailData: moment.thumbnailData,
                        kind: moment.kind,
                        size: proxy.size
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(8)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
        .accessibilityLabel(moment.kind == .photo ? "查看照片" : "查看视频")
    }
}
