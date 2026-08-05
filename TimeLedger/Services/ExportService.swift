import Foundation
import SwiftData

nonisolated struct ExportDateRange: Sendable {
    let start: Date
    let endExclusive: Date

    func overlaps(startAt: Date, endAt: Date) -> Bool {
        startAt < endExclusive && endAt > start
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

nonisolated struct PreparedJSONExport: Sendable {
    let data: Data
    let entryCount: Int
    let thoughtCount: Int
}

nonisolated struct JSONExportService {
    let modelContext: ModelContext

    func prepareJSON(range: ExportDateRange, onlyConfirmed: Bool) throws -> PreparedJSONExport {
        let allEntries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let entries = allEntries
            .filter { range.overlaps(startAt: $0.startAt, endAt: $0.endAt) }
            .filter { !onlyConfirmed || $0.status == TimeEntryStatus.confirmed.rawValue }
            .sorted { $0.startAt < $1.startAt }
        let entryIDs = Set(entries.map(\.id))

        let allThoughts = try modelContext.fetch(FetchDescriptor<ThoughtNote>())
        let thoughts = allThoughts
            .filter { thought in
                range.contains(thought.capturedAt)
                    || thought.linkedEntryId.map(entryIDs.contains) == true
            }
            .sorted { $0.capturedAt < $1.capturedAt }

        let projectIDs = Set(entries.map(\.projectId))
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
            .filter { projectIDs.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
            }

        let payload = JSONDataPackage(
            schemaVersion: 2,
            exportedAt: Date(),
            scope: .init(from: range.start, toExclusive: range.endExclusive),
            mediaIncluded: false,
            projects: projects.map(ProjectExport.init),
            timeEntries: entries.map(TimeEntryExport.init),
            thoughtNotes: thoughts.map(ThoughtNoteExport.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return PreparedJSONExport(data: data, entryCount: entries.count, thoughtCount: thoughts.count)
    }
}

struct ExportService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

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
}

private nonisolated struct JSONDataPackage: Encodable {
    let schemaVersion: Int
    let exportedAt: Date
    let scope: Scope
    let mediaIncluded: Bool
    let projects: [ProjectExport]
    let timeEntries: [TimeEntryExport]
    let thoughtNotes: [ThoughtNoteExport]

    struct Scope: Encodable {
        let from: Date
        let toExclusive: Date
    }
}

private nonisolated struct ProjectExport: Encodable {
    let id: UUID
    let name: String
    let categoryName: String
    let emoji: String?
    let colorHex: String?
    let sortOrder: Int
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ project: Project) {
        id = project.id
        name = project.name
        categoryName = project.categoryName
        emoji = project.emoji
        colorHex = project.colorHex
        sortOrder = project.sortOrder
        isArchived = project.isArchived
        createdAt = project.createdAt
        updatedAt = project.updatedAt
    }
}

private nonisolated struct TimeEntryExport: Encodable {
    let id: UUID
    let projectId: UUID
    let projectNameSnapshot: String
    let categoryNameSnapshot: String
    let startAt: Date
    let endAt: Date
    let note: String
    let status: String
    let createdAt: Date
    let updatedAt: Date

    init(_ entry: TimeEntry) {
        id = entry.id
        projectId = entry.projectId
        projectNameSnapshot = entry.projectNameSnapshot
        categoryNameSnapshot = entry.categoryNameSnapshot
        startAt = entry.startAt
        endAt = entry.endAt
        note = entry.note
        status = entry.status
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }
}

private nonisolated struct ThoughtNoteExport: Encodable {
    let id: UUID
    let body: String
    let capturedAt: Date
    let anchorAt: Date
    let linkedEntryId: UUID?
    let linkSource: String
    let createdAt: Date
    let updatedAt: Date

    init(_ thought: ThoughtNote) {
        id = thought.id
        body = thought.body
        capturedAt = thought.capturedAt
        anchorAt = thought.anchorAt
        linkedEntryId = thought.linkedEntryId
        linkSource = thought.linkSource
        createdAt = thought.createdAt
        updatedAt = thought.updatedAt
    }
}
