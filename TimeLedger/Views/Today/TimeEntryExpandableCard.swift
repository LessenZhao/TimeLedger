import SwiftUI
import SwiftData

struct TimeEntryExpandableCard: View {
    @Environment(\.modelContext) private var modelContext

    let entry: TimeEntry
    let documents: [ContentDocument]
    let journals: [JournalEntry]
    let mediaMoments: [MediaMoment]
    let contentAttachments: [ContentAttachment]
    let actionTitles: [String]
    let onEditJournal: (JournalEntry) -> Void
    let onEdit: () -> Void

    @State private var isExpanded = false
    @State private var selectedMedia: MediaMoment?
    @State private var errorMessage: String?

    init(
        entry: TimeEntry,
        documents: [ContentDocument],
        journals: [JournalEntry],
        mediaMoments: [MediaMoment],
        contentAttachments: [ContentAttachment],
        actionTitles: [String] = [],
        onEditJournal: @escaping (JournalEntry) -> Void = { _ in },
        onEdit: @escaping () -> Void
    ) {
        self.entry = entry
        self.documents = documents
        self.journals = journals
        self.mediaMoments = mediaMoments
        self.contentAttachments = contentAttachments
        self.actionTitles = actionTitles
        self.onEditJournal = onEditJournal
        self.onEdit = onEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if !entryBody.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("记录内容")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timeEntry.content.label")
                    TimelineExpandableText(
                        text: entryBody,
                        collapsedLineLimit: 2,
                        accessibilityPrefix: "timeEntry.content",
                        style: .note
                    )
                }
            }

            summaryRow

            if isExpanded {
                Divider()
                expandedContents
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, TLTheme.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLTheme.cardRadius).fill(TLTheme.cardBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeEntry.card.\(entry.entryStatus.rawValue)")
        .fullScreenCover(item: $selectedMedia) { MediaViewer(moment: $0) }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: TimelineCardActionMetrics.spacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.projectNameSnapshot)
                    .font(TLTheme.projectNameFont)
                    .foregroundStyle(SystemProject.isUnknownEntry(entry) ? .orange : .primary)
                    .lineLimit(1)
                Text(timeRangeText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VisibleEditButton(
                accessibilityLabel: "编辑 \(entry.projectNameSnapshot)",
                accessibilityIdentifier: "timeEntry.edit.\(entry.id.uuidString)",
                action: onEdit
            )
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        if canExpand {
            Button(action: toggleExpansion) {
                HStack(spacing: 8) {
                    if let contentSummary {
                        summaryLabels(contentSummary)
                    }
                    if SystemProject.isUnknownEntry(entry) {
                        badge("待选项目", color: .orange)
                    }
                    if let actionSummary {
                        Text(actionSummary)
                            .font(TLTheme.metaFont)
                            .foregroundStyle(.blue)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起详情 \(entry.projectNameSnapshot)" : "展开详情 \(entry.projectNameSnapshot)")
            .accessibilityIdentifier("timeEntry.body.\(entry.id.uuidString)")
        } else {
            if contentSummary != nil || SystemProject.isUnknownEntry(entry) || !actionTitles.isEmpty {
                HStack(spacing: 8) {
                    if let contentSummary {
                        summaryLabels(contentSummary)
                    }
                    if SystemProject.isUnknownEntry(entry) {
                        badge("待选项目", color: .orange)
                    }
                    if let actionSummary {
                        Text(actionSummary)
                            .font(TLTheme.metaFont)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    private func summaryLabels(_ summary: String) -> some View {
        let parts = summary.components(separatedBy: " · ")
        return HStack(spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.hasPrefix("随记") {
                    Label(part, systemImage: "note.text")
                        .font(TLTheme.metaFont)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(part)
                        .font(TLTheme.metaFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var expandedContents: some View {
        if entryBody.isEmpty && entryMedia.isEmpty && journals.isEmpty && actionTitles.isEmpty {
            Text("没有记录内容或关联随记")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if !entryMedia.isEmpty {
                TimelineMediaGrid(moments: entryMedia) { selectedMedia = $0 }
            }

            ForEach(journals) { journal in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("随记", systemImage: "note.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        favoriteButton(for: journal)
                        VisibleEditButton(
                            accessibilityLabel: "编辑关联随记",
                            accessibilityIdentifier: "timeEntry.journal.edit",
                            action: { onEditJournal(journal) }
                        )
                    }
                    let body = body(for: journal)
                    if !body.isEmpty {
                        TimelineExpandableText(
                            text: body,
                            collapsedLineLimit: 6,
                            accessibilityPrefix: "timeEntry.journal.body",
                            style: .thought
                        )
                    }
                    let media = media(for: journal)
                    if !media.isEmpty {
                        TimelineMediaGrid(moments: media) { selectedMedia = $0 }
                    }
                }
                .padding(.vertical, 3)
            }

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
                .padding(.vertical, 3)
            }
        }
    }

    private func favoriteButton(for journal: JournalEntry) -> some View {
        Button {
            do {
                try JournalContentService(modelContext: modelContext).setFavorite(journal, !journal.isFavorite)
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            Image(systemName: journal.isFavorite ? "star.fill" : "star")
                .font(.caption.weight(.semibold))
                .foregroundStyle(journal.isFavorite ? Color.yellow : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(journal.isFavorite ? "取消收藏随记" : "收藏随记")
        .accessibilityIdentifier("timeEntry.journal.favorite")
    }

    private var entryDocument: ContentDocument? {
        documents.first { $0.ownerID == entry.id && $0.ownerKindEnum == .timeEntry }
    }

    private var entryBody: String {
        entryDocument?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var entryMedia: [MediaMoment] {
        guard let id = entryDocument?.id else { return [] }
        return media(documentID: id)
    }

    private var canExpand: Bool {
        contentSummary != nil || SystemProject.isUnknownEntry(entry) || !actionTitles.isEmpty
    }

    private func body(for journal: JournalEntry) -> String {
        documents.first {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        }?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func media(for journal: JournalEntry) -> [MediaMoment] {
        guard let id = documents.first(where: {
            $0.ownerID == journal.id && $0.ownerKindEnum == .journalEntry
        })?.id else { return [] }
        return media(documentID: id)
    }

    private func media(documentID: UUID) -> [MediaMoment] {
        let order = Dictionary(uniqueKeysWithValues: contentAttachments
            .filter { $0.contentDocumentID == documentID }
            .map { ($0.mediaMomentID, $0.sortOrder) })
        return mediaMoments.filter { order[$0.id] != nil }
            .sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    private var contentSummary: String? {
        let allMedia = entryMedia + journals.flatMap(media(for:))
        let photos = allMedia.filter { $0.kind == .photo }.count
        let videos = allMedia.filter { $0.kind == .video }.count
        var parts: [String] = []
        if !journals.isEmpty { parts.append("随记 \(journals.count)") }
        if photos > 0 { parts.append("照片 \(photos)") }
        if videos > 0 { parts.append("视频 \(videos)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var actionSummary: String? {
        guard let first = actionTitles.first else { return nil }
        return actionTitles.count == 1 ? first : "\(first) +\(actionTitles.count - 1)"
    }

    private var timeRangeText: String {
        let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
        let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
        return "\(start) – \(end) · \(DurationFormatter.compact(entry.durationSeconds))"
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
    }
}
