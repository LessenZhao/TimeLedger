import SwiftData
import SwiftUI

struct DraftListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TimeEntry> { entry in
            entry.status == "draft"
        },
        sort: \TimeEntry.startAt
    ) private var drafts: [TimeEntry]
    @Query private var allThoughts: [ThoughtNote]

    @State private var errorMessage: String?
    @State private var deleteTarget: TimeEntry?

    var body: some View {
        Group {
            if drafts.isEmpty {
                ContentUnavailableView(
                    "没有草稿",
                    systemImage: "tray",
                    description: Text("从项目页归档时间后，未确认的记录会出现在这里。")
                )
                .padding(.top, 40)
            } else {
                List {
                    ForEach(daySections, id: \.dayStart) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                NavigationLink {
                                    TimeEntryEditView(entry: entry)
                                        .toolbar(.visible, for: .navigationBar)
                                } label: {
                                    draftRow(entry, thoughtCount: thoughtCount(for: entry))
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteTarget = entry
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(sectionTitle(for: section.dayStart))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .alert("删除这条草稿？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let entry = deleteTarget {
                    deleteDraft(entry)
                }
            }
        } message: {
            Text("删除后后面的记录会向前贴紧；若是最后一条，未记录光标会退回。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private struct DaySection {
        let dayStart: Date
        let entries: [TimeEntry]
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: drafts) { entry in
            calendar.startOfDay(for: entry.startAt)
        }
        return grouped
            .map { DaySection(dayStart: $0.key, entries: $0.value.sorted { $0.startAt < $1.startAt }) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private func sectionTitle(for dayStart: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(dayStart) {
            return "今天"
        }
        if calendar.isDateInYesterday(dayStart) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: dayStart)
    }

    private func draftRow(_ entry: TimeEntry, thoughtCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.projectNameSnapshot)
                    .font(TLTheme.projectNameFont)
                    .foregroundStyle(SystemProject.isUnknownEntry(entry) ? Color.orange : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(DurationFormatter.compact(entry.durationSeconds))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            Text(timeAndNote(entry))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if SystemProject.isUnknownEntry(entry) || thoughtCount > 0 {
                HStack(spacing: 6) {
                    if SystemProject.isUnknownEntry(entry) {
                        Text("待选项目")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                    }
                    if thoughtCount > 0 {
                        Text("思考 \(thoughtCount)")
                            .font(TLTheme.metaFont)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, TLTheme.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TLTheme.cardRadius)
                .fill(TLTheme.cardBackground)
        )
    }

    private func timeAndNote(_ entry: TimeEntry) -> String {
        let start = DateFormatterFactory.timeOnly.string(from: entry.startAt)
        let end = DateFormatterFactory.timeOnly.string(from: entry.endAt)
        let range = "\(start) – \(end)"
        let trimmed = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return range
        }
        return "\(range) · \(trimmed)"
    }

    private func thoughtCount(for entry: TimeEntry) -> Int {
        allThoughts.filter { $0.linkedEntryId == entry.id }.count
    }

    private func deleteDraft(_ entry: TimeEntry) {
        do {
            try TimeCursorService(modelContext: modelContext).deleteDraftEntry(entry)
            deleteTarget = nil
        } catch {
            errorMessage = error.localizedDescription
            deleteTarget = nil
        }
    }
}
