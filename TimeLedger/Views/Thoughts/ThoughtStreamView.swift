import SwiftData
import SwiftUI
import UIKit

/// 时间线 tab 上唯一一个弹层入口，避免 SwiftUI 多个 `.sheet` 互相抢同一个视图。
enum TimelineSheet: Identifiable {
    case captureThought
    case filter
    case editEntry(TimeEntry)
    case editJournal(JournalEntry)

    var id: String {
        switch self {
        case .captureThought: "captureThought"
        case .filter: "filter"
        case .editEntry(let entry): "editEntry-\(entry.id.uuidString)"
        case .editJournal(let journal): "editJournal-\(journal.id.uuidString)"
        }
    }
}

struct ThoughtStreamView: View {
    @Query(sort: \JournalEntry.capturedAt, order: .reverse) private var journals: [JournalEntry]
    @Query private var documents: [ContentDocument]
    @Query private var contentAttachments: [ContentAttachment]
    @Query private var journalLinks: [JournalTimeLink]
    @Query(sort: \MediaMoment.capturedAt, order: .reverse) private var mediaMoments: [MediaMoment]
    @Query private var entries: [TimeEntry]

    @AppStorage("timeline.typeMode") private var typeModeRaw: String = TimelineTypeMode.merged.rawValue
    @State private var selectedFilters: Set<TimelineContentFilter> = []
    @State private var activeSheet: TimelineSheet?

    private var typeMode: TimelineTypeMode {
        TimelineTypeMode(rawValue: typeModeRaw) ?? .merged
    }

    var body: some View {
        let records = TimelineProjection.records(
            journals: journals,
            documents: documents,
            contentAttachments: contentAttachments,
            journalLinks: journalLinks,
            mediaMoments: mediaMoments,
            entries: entries
        )
        .filter { typeMode.matches($0) }
        .filter { TimelineContentFilter.matches($0, selectedFilters: selectedFilters) }
        let sections = daySections(for: records)
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        NavigationStack {
            VStack(spacing: 0) {
                typeModePicker
                filterSummary(recordsCount: records.count)

                if sections.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: selectedFilters.isEmpty ? "clock" : "line.3.horizontal.decrease.circle",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: TimelineCardStyle.cardSpacing) {
                                    dayHeader(section.title)
                                    ForEach(section.items) { record in
                                        timelineCard(record, entriesByID: entriesByID)
                                    }
                                }
                                .padding(.horizontal, TimelineCardStyle.horizontalPadding)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(TLTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("时间线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
               ToolbarItem(placement: .topBarTrailing) {
                   Button {
                       activeSheet = .captureThought
                    } label: {
                        Image(systemName: "lightbulb.fill")
                    }
                    .accessibilityLabel("快速想法")
                }
            }
           // 合并到一个 .sheet(item:) 上，避免 SwiftUI 同视图多 sheet 互相打架（历史上编辑页经常被前面几个 sheet 抢掉）。
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .captureThought:
                    ThoughtComposerSheet()
                case .filter:
                    TimelineFilterSheet(selectedFilters: $selectedFilters)
                case .editEntry(let entry):
                    NavigationStack {
                        TimeEntryEditorView(mode: .edit(entry: entry))
                    }
                case .editJournal(let journal):
                    RichCardContentEditorSheet(target: .journal(journal), title: "编辑随记")
                }
            }
        }
    }

    private var typeModePicker: some View {
        TimelineTypeModeSegmentedControl(
            selection: Binding(
                get: { typeMode },
                set: { typeModeRaw = $0.rawValue }
            )
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func filterSummary(recordsCount: Int) -> some View {
        Button {
            activeSheet = .filter
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedFilters.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)

                Text(selectedFilters.isEmpty ? "全部 · \(recordsCount)" : "\(selectedFilterTitles) · \(recordsCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground).opacity(0.7))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, TimelineCardStyle.horizontalPadding)
        .padding(.vertical, 8)
        .accessibilityIdentifier("timeline.filter.button")
    }

    private var selectedFilterTitles: String {
        TimelineContentFilter.allCases
            .filter(selectedFilters.contains)
            .map(\.displayTitle)
            .joined(separator: "、")
    }

    private var emptyTitle: String {
        selectedFilters.isEmpty ? "还没有时间点" : "没有符合筛选的记录"
    }

    private var emptyDescription: String {
        selectedFilters.isEmpty
            ? "文字、照片和视频会按时间展示在这里。"
            : "调整筛选条件，或重置为查看全部记录。"
    }

    @ViewBuilder
    private func timelineCard(
        _ record: TimelineRecord,
        entriesByID: [UUID: TimeEntry]
    ) -> some View {
        switch record.kind {
        case .note:
            TimeEntryNoteCard(
                record: record,
                onEdit: {
                    if let entry = record.linkedEntry {
                        activeSheet = .editEntry(entry)
                    }
                }
            )
        case .thought:
            if let journal = record.journal {
                ThoughtCardView(
                    journal: journal,
                    body: record.journalText,
                    linkedEntry: record.linkedEntry,
                    mediaMoments: record.mediaMoments,
                    displayStartAt: record.capturedAt,
                    displayEndAt: record.displayEndAt,
                    isRelatedToNote: record.isRelatedToNote,
                    onEdit: {
                        activeSheet = .editJournal(journal)
                    }
                )
            }
        }
    }

    private func linkedEntry(
        for entryID: UUID?,
        entriesByID: [UUID: TimeEntry]
    ) -> TimeEntry? {
        entryID.flatMap { entriesByID[$0] }
    }

    private func daySections(for records: [TimelineRecord]) -> [TimelineDaySection] {
        let calendar = Calendar.current
        var buckets: [(dayStart: Date, items: [TimelineRecord])] = []
        var indexByDayStart: [Date: Int] = [:]

        for record in records {
            let dayStart = calendar.startOfDay(for: record.capturedAt)
            if let index = indexByDayStart[dayStart] {
                buckets[index].items.append(record)
            } else {
                indexByDayStart[dayStart] = buckets.count
                buckets.append((dayStart, [record]))
            }
        }

        return buckets.map { bucket in
            TimelineDaySection(
                id: bucket.dayStart,
                title: dayTitle(for: bucket.dayStart, calendar: calendar),
                items: bucket.items
            )
        }
    }

    private func dayTitle(for dayStart: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(dayStart) {
            return "今天"
        }
        if calendar.isDateInYesterday(dayStart) {
            return "昨天"
        }
        return DateFormatterFactory.dateTitle.string(from: dayStart)
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .accessibilityIdentifier("timeline.day.\(title)")
    }
}

private struct TimelineTypeModeSegmentedControl: UIViewRepresentable {
    let selection: Binding<TimelineTypeMode>

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: TimelineTypeMode.allCases.map(\.title))
        control.accessibilityIdentifier = "timeline.typeMode.picker"
        control.selectedSegmentIndex = TimelineTypeMode.allCases.firstIndex(of: selection.wrappedValue) ?? 0
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        if let index = TimelineTypeMode.allCases.firstIndex(of: selection.wrappedValue) {
            uiView.selectedSegmentIndex = index
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: selection)
    }

    final class Coordinator: NSObject {
        let selection: Binding<TimelineTypeMode>

        init(selection: Binding<TimelineTypeMode>) {
            self.selection = selection
        }

        @objc func valueChanged(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard TimelineTypeMode.allCases.indices.contains(index) else { return }
            selection.wrappedValue = TimelineTypeMode.allCases[index]
        }
    }
}

private struct TimelineFilterSheet: View {
    @Binding var selectedFilters: Set<TimelineContentFilter>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("显示包含以下内容的记录")
                    .font(.headline)

                HStack(spacing: 10) {
                    ForEach(TimelineContentFilter.allCases) { filter in
                        filterOption(filter)
                    }
                }

                Text("选择一个或多个；会显示含其中任一内容的记录。未选择时显示全部。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .navigationTitle("筛选时间线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !selectedFilters.isEmpty {
                        Button("重置") {
                            selectedFilters.removeAll()
                        }
                        .accessibilityIdentifier("timeline.filter.reset")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .accessibilityIdentifier("timeline.filter.done")
                }
            }
        }
        .presentationDetents([.height(250)])
    }

    private func filterOption(_ filter: TimelineContentFilter) -> some View {
        let isSelected = selectedFilters.contains(filter)
        return Button {
            if isSelected {
                selectedFilters.remove(filter)
            } else {
                selectedFilters.insert(filter)
            }
        } label: {
            Label(filter.displayTitle, systemImage: isSelected ? "checkmark.circle.fill" : filter.symbolName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isSelected ? Color.accentColor.opacity(0.12) : TLTheme.cardBackground)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.45) : .secondary.opacity(0.2))
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline.filter.option.\(filter.rawValue)")
    }
}

private extension TimelineContentFilter {
    var displayTitle: String {
        switch self {
        case .text: "文字"
        case .photos: "照片"
        case .videos: "视频"
        case .favorite: "收藏"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .photos: "photo"
        case .videos: "video"
        case .favorite: "star"
        }
    }
}

private struct TimelineDaySection: Identifiable {
    let id: Date
    let title: String
    let items: [TimelineRecord]
}

#Preview {
    ThoughtStreamView()
        .modelContainer(previewModelContainer)
}
