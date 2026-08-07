import SwiftData
import SwiftUI

struct DailyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allJournals: [JournalEntry]
    @Query private var documents: [ContentDocument]

    @State private var selectedDate = Date()
    @State private var includeDraft = false

    var body: some View {
        VStack(spacing: 0) {
            datePickerBar
            ScrollView {
                LazyVStack(spacing: 16) {
                    totalCard
                    categorySection
                    projectSection
                    timelineSection
                    thoughtDistributionSection
                }
                .padding(16)
            }
        }
        .navigationTitle("每日复盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var datePickerBar: some View {
        HStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
            Spacer()
            Toggle("含待确认", isOn: $includeDraft)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var totalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatterFactory.dateTitle.string(from: selectedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.compact(totalDuration))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("随记")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(thoughtCount)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }

    private var categorySection: some View {
        ReviewSection(title: "分类汇总") {
            if categorySummary.isEmpty {
                Text("无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(categorySummary.sorted(by: { $0.value > $1.value }), id: \.key) { category, duration in
                    summaryRow(category, DurationFormatter.compact(duration))
                }
            }
        }
    }

    private var projectSection: some View {
        ReviewSection(title: "项目汇总") {
            if projectSummary.isEmpty {
                Text("无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projectSummary.sorted(by: { $0.value > $1.value }), id: \.key) { name, duration in
                    summaryRow(name, DurationFormatter.compact(duration))
                }
            }
        }
    }

    private var timelineSection: some View {
        ReviewSection(title: "时间线") {
            if entries.isEmpty {
                Text("无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    timelineRow(entry)
                }
            }
        }
    }

    private var totalDuration: TimeInterval {
        (try? TimeSummaryService(modelContext: modelContext).totalDurationForDate(selectedDate, includeDraft: includeDraft)) ?? 0
    }

    private var categorySummary: [String: TimeInterval] {
        (try? TimeSummaryService(modelContext: modelContext).categorySummaryForDate(selectedDate, includeDraft: includeDraft)) ?? [:]
    }

    private var projectSummary: [String: TimeInterval] {
        (try? TimeSummaryService(modelContext: modelContext).projectSummaryForDate(selectedDate, includeDraft: includeDraft)) ?? [:]
    }

    private var entries: [TimeEntry] {
        (try? TimeSummaryService(modelContext: modelContext).entriesForDate(date: selectedDate)) ?? []
    }

    private var todayJournals: [JournalEntry] {
        let range = DateRangeService.naturalDayRange(for: selectedDate)
        return allJournals.filter { $0.capturedAt >= range.lowerBound && $0.capturedAt < range.upperBound }
    }

    private var thoughtCount: Int {
        todayJournals.count
    }

    private var thoughtHourlyDistribution: [(hour: Int, count: Int)] {
        let calendar = Calendar.current
        let counts = todayJournals.reduce(into: [Int: Int]()) { result, journal in
            let hour = calendar.component(.hour, from: journal.capturedAt)
            result[hour, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { (hour: $0.key, count: $0.value) }
    }

    private func summaryRow(_ name: String, _ duration: String) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(duration)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func timelineRow(_ entry: TimeEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.projectNameSnapshot)
                    .font(.subheadline.weight(.medium))
                Text("\(DateFormatterFactory.timeOnly.string(from: entry.startAt)) - \(DateFormatterFactory.timeOnly.string(from: entry.endAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let body = documents.first {
                    $0.ownerID == entry.id && $0.ownerKindEnum == .timeEntry
                }?.body ?? ""
                if !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(DurationFormatter.compact(entry.durationSeconds))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }

    private var thoughtDistributionSection: some View {
        ReviewSection(title: "今日随记分布") {
            if todayJournals.isEmpty {
                Text("无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("随记总数")
                            .font(.subheadline)
                        Spacer()
                        Text("\(thoughtCount) 条")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                    Divider()
                        .padding(.vertical, 4)
                    ForEach(thoughtHourlyDistribution, id: \.hour) { item in
                        HStack {
                            Text(String(format: "%02d:00 - %02d:00", item.hour, (item.hour + 1) % 24))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(item.count) 条")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct ReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }
}
