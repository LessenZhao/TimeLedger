import Foundation
import SwiftData

struct ExportService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    // MARK: - CSV

    func exportCSV(onlyConfirmed: Bool) throws -> String {
        let entries = try fetchAllEntries(onlyConfirmed: onlyConfirmed)
        let allThoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let header = "date,startAt,endAt,durationMinutes,projectName,categoryName,note,status,linkedThoughtCount,linkedThoughts"
        let rows = entries.map { entry in
            let linked = allThoughts.filter { $0.linkedEntryId == entry.id }
            let linkedBodies = linked.map { $0.body }.joined(separator: " | ")
            return csvField(DateFormatterFactory.dateTitle.string(from: entry.startAt)) + "," +
                csvField(DateFormatterFactory.dateTime.string(from: entry.startAt)) + "," +
                csvField(DateFormatterFactory.dateTime.string(from: entry.endAt)) + "," +
                "\(entry.durationMinutesRounded)," +
                csvField(entry.projectNameSnapshot) + "," +
                csvField(entry.categoryNameSnapshot) + "," +
                csvField(entry.note) + "," +
                csvField(entry.status) + "," +
                "\(linked.count)," +
                csvField(linkedBodies)
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - JSON Backup

    func exportJSON() throws -> String {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let thoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
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

        let thoughtDicts: [[String: Any]] = thoughts.map { t in
            [
                "id": t.id.uuidString,
                "body": t.body,
                "capturedAt": iso8601(t.capturedAt),
                "anchorAt": iso8601(t.anchorAt),
                "linkedEntryId": t.linkedEntryId?.uuidString ?? "",
                "linkSource": t.linkSource,
                "createdAt": iso8601(t.createdAt),
                "updatedAt": iso8601(t.updatedAt)
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
            "thoughtNotes": thoughtDicts,
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
        let allThoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let allEntries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let thoughtsCapturedToday = allThoughts
            .filter { $0.capturedAt >= dayRange.lowerBound && $0.capturedAt < dayRange.upperBound }
            .sorted { $0.capturedAt < $1.capturedAt }
        let unlinkedThoughts = thoughtsCapturedToday.filter { $0.linkedEntryId == nil }

        let dateStr = DateFormatterFactory.dateTitle.string(from: date)
        var lines: [String] = []

        lines.append("# 时间记录日报 - \(dateStr)")
        lines.append("")
        lines.append("## 总计")
        lines.append("- 总时长：\(DurationFormatter.compact(total))")
        lines.append("- 思考条数：\(thoughtsCapturedToday.count)")
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
                // Add linked thoughts
                let linkedThoughts = allThoughts.filter { $0.linkedEntryId == entry.id }
                    .sorted { $0.capturedAt < $1.capturedAt }
                if !linkedThoughts.isEmpty {
                    lines.append("  - 关联思考：")
                    for thought in linkedThoughts {
                        let isWithinRange = thought.capturedAt >= entry.startAt && thought.capturedAt <= entry.endAt
                        let tag = isWithinRange ? "当时想法" : "事后补充"
                        lines.append("    - \(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))｜\(tag)｜\(thought.body)")
                    }
                }
            }
        }

        // 今日捕获的思考
        lines.append("")
        lines.append("## 今日捕获的思考")
        if thoughtsCapturedToday.isEmpty {
            lines.append("- 无数据")
        } else {
            for thought in thoughtsCapturedToday {
                let linkText: String
                if let entryId = thought.linkedEntryId,
                   let entry = allEntries.first(where: { $0.id == entryId }) {
                    linkText = entry.projectNameSnapshot
                } else {
                    linkText = "未关联"
                }
                lines.append("- \(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))｜\(thought.body)｜关联：\(linkText)")
            }
        }

        // 未匹配思考
        lines.append("")
        lines.append("## 未匹配思考")
        if unlinkedThoughts.isEmpty {
            lines.append("- 无数据")
        } else {
            for thought in unlinkedThoughts {
                lines.append("- \(DateFormatterFactory.timeOnly.string(from: thought.capturedAt))｜\(thought.body)")
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
