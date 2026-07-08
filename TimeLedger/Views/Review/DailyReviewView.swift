import SwiftData
import SwiftUI

struct DailyReviewView: View {
    @Environment(\.modelContext) private var modelContext

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
            Toggle("含草稿", isOn: $includeDraft)
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
                if !entry.note.isEmpty {
                    Text(entry.note)
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
