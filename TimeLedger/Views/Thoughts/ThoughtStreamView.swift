import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @Query(sort: \ThoughtNote.capturedAt, order: .reverse) private var thoughts: [ThoughtNote]
    @Query(sort: \MediaMoment.capturedAt, order: .reverse) private var mediaMoments: [MediaMoment]
    @Query private var thoughtMediaLinks: [ThoughtMediaLink]
    @Query private var entries: [TimeEntry]

    @AppStorage("timeline.typeMode") private var typeModeRaw: String = TimelineTypeMode.merged.rawValue
    @State private var showingThoughtCapture = false
    @State private var showingFilter = false
    @State private var selectedFilters: Set<TimelineContentFilter> = []
    @State private var editingEntry: TimeEntry?
    @State private var editingThought: ThoughtNote?

    private var typeMode: TimelineTypeMode {
        TimelineTypeMode(rawValue: typeModeRaw) ?? .merged
    }

    var body: some View {
        let records = TimelineProjection.records(
            thoughts: thoughts,
            mediaMoments: mediaMoments,
            mediaLinks: thoughtMediaLinks,
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
                        showingThoughtCapture = true
                    } label: {
                        Image(systemName: "lightbulb.fill")
                    }
                    .accessibilityLabel("快速想法")
                }
            }
            .sheet(isPresented: $showingThoughtCapture) {
                ThoughtComposerSheet()
            }
            .sheet(isPresented: $showingFilter) {
                TimelineFilterSheet(selectedFilters: $selectedFilters)
            }
            .sheet(item: $editingEntry) { entry in
                NavigationStack {
                    TimeEntryEditView(entry: entry)
                }
            }
            .sheet(item: $editingThought) { thought in
                RichCardContentEditorSheet(target: .thought(thought), title: "编辑思考")
            }
        }
    }

    private var typeModePicker: some View {
        Picker("类型", selection: typeModeBinding) {
            Text("备注").tag(TimelineTypeMode.notes.rawValue)
            Text("思考").tag(TimelineTypeMode.thoughts.rawValue)
            Text("合并").tag(TimelineTypeMode.merged.rawValue)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .accessibilityIdentifier("timeline.typeMode.picker")
    }

    private var typeModeBinding: Binding<String> {
        Binding(
            get: { typeModeRaw },
            set: { typeModeRaw = $0 }
        )
    }

    private func filterSummary(recordsCount: Int) -> some View {
        Button {
            showingFilter = true
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
                        editingEntry = entry
                    }
                }
            )
        case .thought:
            if let thought = record.thought {
                ThoughtCardView(
                    thought: thought,
                    linkedEntry: record.linkedEntry
                        ?? linkedEntry(for: thought.linkedEntryId, entriesByID: entriesByID),
                    mediaMoments: record.mediaMoments,
                    displayStartAt: record.capturedAt,
                    displayEndAt: record.displayEndAt,
                    isRelatedToNote: record.isRelatedToNote,
                    onEdit: {
                        editingThought = thought
                    }
                )
            } else if let moment = record.mediaMoments.first {
                let targetEntry = record.linkedEntry
                    ?? linkedEntry(for: moment.linkedEntryId, entriesByID: entriesByID)
                MediaMomentCard(
                    moment: moment,
                    linkedEntry: targetEntry,
                    displayStartAt: record.capturedAt,
                    displayEndAt: record.displayEndAt,
                    isRelatedToNote: record.isRelatedToNote,
                    onEdit: targetEntry.map { entry in
                        { editingEntry = entry }
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
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .photos: "photo"
        case .videos: "video"
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
