import Foundation
import SwiftData

struct ExportService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    // MARK: - CSV

    func exportCSV(onlyConfirmed: Bool) throws -> String {
        let entries = try fetchAllEntries(onlyConfirmed: onlyConfirmed)
        let header = "date,startAt,endAt,durationMinutes,projectName,categoryName,note,status"
        let rows = entries.map { entry in
            csvField(DateFormatterFactory.dateTitle.string(from: entry.startAt)) + "," +
            csvField(DateFormatterFactory.dateTime.string(from: entry.startAt)) + "," +
            csvField(DateFormatterFactory.dateTime.string(from: entry.endAt)) + "," +
            "\(entry.durationMinutesRounded)," +
            csvField(entry.projectNameSnapshot) + "," +
            csvField(entry.categoryNameSnapshot) + "," +
            csvField(entry.note) + "," +
            csvField(entry.status)
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - JSON Backup

    func exportJSON() throws -> String {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let settings = (try? modelContext.fetch(FetchDescriptor<AppSettings>()))?.first

        let projectDicts: [[String: Any]] = projects.map { p in
            [
                "id": p.id.uuidString,
                "name": p.name,
                "categoryName": p.categoryName,
                "emoji": p.emoji ?? "",
                "colorHex": p.colorHex ?? "",
                "sortOrder": p.sortOrder,
                "isArchived": p.isArchived,
                "createdAt": iso8601(p.createdAt),
                "updatedAt": iso8601(p.updatedAt)
            ]
        }

        let entryDicts: [[String: Any]] = entries.map { e in
            [
                "id": e.id.uuidString,
                "projectId": e.projectId.uuidString,
                "projectNameSnapshot": e.projectNameSnapshot,
                "categoryNameSnapshot": e.categoryNameSnapshot,
                "startAt": iso8601(e.startAt),
                "endAt": iso8601(e.endAt),
                "note": e.note,
                "status": e.status,
                "createdAt": iso8601(e.createdAt),
                "updatedAt": iso8601(e.updatedAt)
            ]
        }

        let settingsDict: [String: Any] = [
            "longUnclassifiedThresholdMinutes": settings?.longUnclassifiedThresholdMinutes ?? 90,
            "exportOnlyConfirmed": settings?.exportOnlyConfirmed ?? true,
            "includeDraftInTodaySummary": settings?.includeDraftInTodaySummary ?? true
        ]

        let backup: [String: Any] = [
            "version": 1,
            "exportedAt": iso8601(Date()),
            "projects": projectDicts,
            "timeEntries": entryDicts,
            "settings": settingsDict
        ]

        let data = try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Markdown Daily Report

    func exportMarkdownDailyReport(date: Date, onlyConfirmed: Bool) throws -> String {
        let summary = TimeSummaryService(modelContext: modelContext, calendar: calendar)
        let total = try summary.totalDurationForDate(date, includeDraft: !onlyConfirmed)
        let categorySummary = try summary.categorySummaryForDate(date, includeDraft: !onlyConfirmed)
        let projectSummary = try summary.projectSummaryForDate(date, includeDraft: !onlyConfirmed)
        let entries = try summary.entriesForDate(date: date).filter { entry in
            !onlyConfirmed || entry.status == TimeEntryStatus.confirmed.rawValue
        }

        let dateStr = DateFormatterFactory.dateTitle.string(from: date)
        var lines: [String] = []

        lines.append("# 时间记录日报 - \(dateStr)")
        lines.append("")
        lines.append("## 总计")
        lines.append("- 总时长：\(DurationFormatter.compact(total))")
        lines.append("")

        lines.append("## 分类汇总")
        if categorySummary.isEmpty {
            lines.append("- 无数据")
        } else {
            for (category, duration) in categorySummary.sorted(by: { $0.value > $1.value }) {
                lines.append("- \(category)：\(DurationFormatter.compact(duration))")
            }
        }
        lines.append("")

        lines.append("## 项目汇总")
        if projectSummary.isEmpty {
            lines.append("- 无数据")
        } else {
            for (name, duration) in projectSummary.sorted(by: { $0.value > $1.value }) {
                lines.append("- \(name)：\(DurationFormatter.compact(duration))")
            }
        }
        lines.append("")

        lines.append("## 时间线")
        if entries.isEmpty {
            lines.append("- 无数据")
        } else {
        for entry in entries {
            let range = DateRangeService.naturalDayRange(for: date, calendar: calendar)
            let overlap = DateRangeService.overlapDuration(
                entryStart: entry.startAt,
                entryEnd: entry.endAt,
                    rangeStart: range.lowerBound,
                    rangeEnd: range.upperBound
                )
                lines.append("- \(DateFormatterFactory.timeOnly.string(from: entry.startAt)) - \(DateFormatterFactory.timeOnly.string(from: entry.endAt))（\(DurationFormatter.compact(overlap))）\(entry.projectNameSnapshot) [\(entry.status)]")
                if !entry.note.isEmpty {
                    lines.append("  - \(entry.note)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func fetchAllEntries(onlyConfirmed: Bool) throws -> [TimeEntry] {
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))
        return onlyConfirmed
            ? entries.filter { $0.status == TimeEntryStatus.confirmed.rawValue }
            : entries
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
