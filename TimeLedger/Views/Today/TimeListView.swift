import SwiftData
import SwiftUI

struct TimeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [TimeEntry]
    @Query private var documents: [ContentDocument]
    @Query private var journalLinks: [JournalTimeLink]

    let date: Date
    let now: Date

    init(date: Date, now: Date) {
        self.date = date
        self.now = now
        let range = DateRangeService.naturalDayRange(for: date)
        _allEntries = Query(
            filter: #Predicate<TimeEntry> { entry in
                entry.startAt < range.upperBound && entry.endAt > range.lowerBound
            },
            sort: \TimeEntry.startAt
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: TLTheme.listSpacing) {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "今天还没有记录",
                        systemImage: "clock",
                        description: Text("从项目页快速归档一段时间。")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            TimeEntryDetailView(entry: entry)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            entryRow(entry, journalCount: journalCount(for: entry))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var entries: [TimeEntry] {
        allEntries
    }

    private func entryRow(_ entry: TimeEntry, journalCount: Int) -> some View {
        let isDraft = entry.status == TimeEntryStatus.draft.rawValue

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.projectNameSnapshot)
                    .font(TLTheme.projectNameFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(DurationFormatter.compact(entry.durationSeconds))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Text(timeRangeText(entry))
                .font(TLTheme.metaFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(isDraft ? "待确认" : "已确认")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDraft ? Color.secondary : Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            isDraft
                                ? Color.gray.opacity(0.12)
                                : Color.accentColor.opacity(0.12)
                        )
                    )

                if journalCount > 0 {
                    Text("随记 \(journalCount)")
                        .font(TLTheme.metaFont)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, TLTheme.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDraft ? 0.7 : 1)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                .fill(TLTheme.cardBackground)
        )
    }

    private func timeRangeText(_ entry: TimeEntry) -> String {
        let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
        let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
        let body = documents.first {
            $0.ownerID == entry.id && $0.ownerKindEnum == .timeEntry
        }?.body ?? ""
        if body.isEmpty {
            return "\(start) – \(end)"
        }
        return "\(start) – \(end) · \(body)"
    }

    private func journalCount(for entry: TimeEntry) -> Int {
        journalLinks.filter { $0.timeEntryID == entry.id }.count
    }
}

#Preview {
    NavigationStack {
        TimeListView(date: Date(), now: Date())
    }
    .modelContainer(previewModelContainer)
}
