import SwiftData
import SwiftUI

struct ThoughtStreamView: View {
    @Query(sort: \ThoughtNote.capturedAt, order: .reverse) private var thoughts: [ThoughtNote]
    @Query(sort: \MediaMoment.capturedAt, order: .reverse) private var mediaMoments: [MediaMoment]
    @Query private var thoughtMediaLinks: [ThoughtMediaLink]
    @Query private var entries: [TimeEntry]

    @State private var showingThoughtCapture = false
    @State private var showingFilter = false
    @State private var selectedFilters: Set<TimelineContentFilter> = []

    var body: some View {
        let records = TimelineProjection.records(
            thoughts: thoughts,
            mediaMoments: mediaMoments,
            mediaLinks: thoughtMediaLinks
        )
        .filter { TimelineContentFilter.matches($0, selectedFilters: selectedFilters) }
        let sections = daySections(for: records)
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        NavigationStack {
            VStack(spacing: 0) {
                filterSummary(recordsCount: records.count)

                if sections.isEmpty {
                    ContentUnavailableView(
                        selectedFilters.isEmpty ? "还没有时间点" : "没有符合筛选的记录",
                        systemImage: selectedFilters.isEmpty ? "clock" : "line.3.horizontal.decrease.circle",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ForEach(sections) { section in
                                Section {
                                    LazyVStack(spacing: 10) {
                                        ForEach(section.items) { record in
                                            timelineCard(record, entriesByID: entriesByID)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                } header: {
                                    dayHeader(section.title)
                                }
                            }
                        }
                        .padding(.bottom, 16)
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
        }
    }

    private func filterSummary(recordsCount: Int) -> some View {
        Button {
            showingFilter = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedFilters.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedFilters.isEmpty ? "显示：全部" : "已筛选：\(selectedFilterTitles)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(recordsCount) 条记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(TLTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("timeline.filter.button")
    }

    private var selectedFilterTitles: String {
        TimelineContentFilter.allCases
            .filter(selectedFilters.contains)
            .map(\.displayTitle)
            .joined(separator: "、")
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
        if let thought = record.thought {
            ThoughtCardView(
                thought: thought,
                linkedEntry: linkedEntry(for: thought.linkedEntryId, entriesByID: entriesByID),
                mediaMoments: record.mediaMoments
            )
        } else if let moment = record.mediaMoments.first {
            MediaMomentCard(
                moment: moment,
                linkedEntry: linkedEntry(for: moment.linkedEntryId, entriesByID: entriesByID)
            )
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(TLTheme.pageBackground.opacity(0.95))
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
