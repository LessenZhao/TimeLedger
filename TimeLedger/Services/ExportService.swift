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
        let entries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
            .filter { range.overlaps(startAt: $0.startAt, endAt: $0.endAt) }
            .filter { !onlyConfirmed || $0.status == TimeEntryStatus.confirmed.rawValue }
            .sorted { $0.startAt < $1.startAt }
        let entryIDs = Set(entries.map(\.id))
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
            .filter { journal in
                let entryID = links.first { $0.journalEntryID == journal.id }?.timeEntryID
                return range.contains(journal.capturedAt) || entryID.map(entryIDs.contains) == true
            }
            .sorted { $0.capturedAt < $1.capturedAt }
        let projectIDs = Set(entries.map(\.projectId))
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
            .filter { projectIDs.contains($0.id) }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }

        let payload = JSONDataPackage(
            schemaVersion: 2,
            exportedAt: Date(),
            scope: .init(from: range.start, toExclusive: range.endExclusive),
            mediaIncluded: false,
            projects: projects.map(ProjectExport.init),
            timeEntries: entries.map { entry in
                TimeEntryExport(entry, note: document(ownerID: entry.id, kind: .timeEntry, documents: documents)?.body ?? "")
            },
            thoughtNotes: journals.map { journal in
                ThoughtNoteExport(
                    journal,
                    body: document(ownerID: journal.id, kind: .journalEntry, documents: documents)?.body ?? "",
                    link: links.first { $0.journalEntryID == journal.id }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return PreparedJSONExport(
            data: try encoder.encode(payload),
            entryCount: entries.count,
            thoughtCount: journals.count
        )
    }
}

struct ExportService {
    let modelContext: ModelContext
    var calendar: Calendar = .current

    func exportMarkdownDailyReport(date: Date, onlyConfirmed: Bool) throws -> String {
        let summary = TimeSummaryService(modelContext: modelContext, calendar: calendar)
        let entries = try summary.entriesForDate(date: date)
            .filter { !onlyConfirmed || $0.status == TimeEntryStatus.confirmed.rawValue }
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
        let links = try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
        let allEntries = try modelContext.fetch(FetchDescriptor<TimeEntry>())
        let dayRange = DateRangeService.naturalDayRange(for: date, calendar: calendar)
        let captured = journals
            .filter { $0.capturedAt >= dayRange.lowerBound && $0.capturedAt < dayRange.upperBound }
            .sorted { $0.capturedAt < $1.capturedAt }
        let linkedJournalIDs = Set(links.map(\.journalEntryID))
        let unlinked = captured.filter { !linkedJournalIDs.contains($0.id) }
        let total = try summary.totalDurationForDate(date, includeDraft: !onlyConfirmed)
        let categorySummary = try summary.categorySummaryForDate(date, includeDraft: !onlyConfirmed)
        let projectSummary = try summary.projectSummaryForDate(date, includeDraft: !onlyConfirmed)
        var lines = [
            "# 时间记录日报 - \(DateFormatterFactory.dateTitle.string(from: date))",
            "",
            "## 总计",
            "- 总时长：\(DurationFormatter.compact(total))",
            "- 随记条数：\(captured.count)",
            "",
            "## 分类汇总",
        ]
        lines += categorySummary.isEmpty
            ? ["- 无数据"]
            : categorySummary.sorted { $0.value > $1.value }.map { "- \($0.key)：\(DurationFormatter.compact($0.value))" }
        lines += ["", "## 项目汇总"]
        lines += projectSummary.isEmpty
            ? ["- 无数据"]
            : projectSummary.sorted { $0.value > $1.value }.map { "- \($0.key)：\(DurationFormatter.compact($0.value))" }
        lines += ["", "## 时间线"]
        if entries.isEmpty {
            lines.append("- 无数据")
        } else {
            for entry in entries {
                let overlap = DateRangeService.overlapDuration(
                    entryStart: entry.startAt,
                    entryEnd: entry.endAt,
                    rangeStart: dayRange.lowerBound,
                    rangeEnd: dayRange.upperBound
                )
                lines.append("- \(DateFormatterFactory.timeOnly.string(from: entry.startAt)) - \(DateFormatterFactory.timeOnly.string(from: entry.endAt))（\(DurationFormatter.compact(overlap))）\(entry.projectNameSnapshot) [\(entry.status)]")
                let body = document(ownerID: entry.id, kind: .timeEntry, documents: documents)?.body ?? ""
                if !body.isEmpty { lines.append("  - \(body)") }
                let journalIDs = Set(links.filter { $0.timeEntryID == entry.id }.map(\.journalEntryID))
                let linked = journals.filter { journalIDs.contains($0.id) }.sorted { $0.capturedAt < $1.capturedAt }
                if !linked.isEmpty {
                    lines.append("  - 关联随记：")
                    for journal in linked {
                        let tag = journal.capturedAt >= entry.startAt && journal.capturedAt <= entry.endAt ? "当时想法" : "事后补充"
                        let journalBody = document(ownerID: journal.id, kind: .journalEntry, documents: documents)?.body ?? ""
                        lines.append("    - \(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))｜\(tag)｜\(journalBody)")
                    }
                }
            }
        }
        lines += ["", "## 今日捕获的随记"]
        if captured.isEmpty {
            lines.append("- 无数据")
        } else {
            for journal in captured {
                let entryID = links.first { $0.journalEntryID == journal.id }?.timeEntryID
                let linkText = entryID.flatMap { id in allEntries.first { $0.id == id }?.projectNameSnapshot } ?? "未关联"
                let body = document(ownerID: journal.id, kind: .journalEntry, documents: documents)?.body ?? ""
                lines.append("- \(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))｜\(body)｜关联：\(linkText)")
            }
        }
        lines += ["", "## 未匹配随记"]
        if unlinked.isEmpty {
            lines.append("- 无数据")
        } else {
            for journal in unlinked {
                let body = document(ownerID: journal.id, kind: .journalEntry, documents: documents)?.body ?? ""
                lines.append("- \(DateFormatterFactory.timeOnly.string(from: journal.capturedAt))｜\(body)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private nonisolated func document(ownerID: UUID, kind: ContentOwnerKind, documents: [ContentDocument]) -> ContentDocument? {
    documents.first { $0.ownerID == ownerID && $0.ownerKindEnum == kind }
}

private nonisolated struct JSONDataPackage: Encodable {
    let schemaVersion: Int
    let exportedAt: Date
    let scope: Scope
    let mediaIncluded: Bool
    let projects: [ProjectExport]
    let timeEntries: [TimeEntryExport]
    let thoughtNotes: [ThoughtNoteExport]
    struct Scope: Encodable { let from: Date; let toExclusive: Date }
}

private nonisolated struct ProjectExport: Encodable {
    let id: UUID; let name: String; let categoryName: String; let emoji: String?; let colorHex: String?
    let sortOrder: Int; let isArchived: Bool; let createdAt: Date; let updatedAt: Date
    init(_ p: Project) {
        id = p.id; name = p.name; categoryName = p.categoryName; emoji = p.emoji; colorHex = p.colorHex
        sortOrder = p.sortOrder; isArchived = p.isArchived; createdAt = p.createdAt; updatedAt = p.updatedAt
    }
}

private nonisolated struct TimeEntryExport: Encodable {
    let id: UUID; let projectId: UUID; let projectNameSnapshot: String; let categoryNameSnapshot: String
    let startAt: Date; let endAt: Date; let note: String; let status: String; let createdAt: Date; let updatedAt: Date
    init(_ e: TimeEntry, note: String) {
        id = e.id; projectId = e.projectId; projectNameSnapshot = e.projectNameSnapshot
        categoryNameSnapshot = e.categoryNameSnapshot; startAt = e.startAt; endAt = e.endAt
        self.note = note; status = e.status; createdAt = e.createdAt; updatedAt = e.updatedAt
    }
}

private nonisolated struct ThoughtNoteExport: Encodable {
    let id: UUID; let body: String; let capturedAt: Date; let anchorAt: Date; let linkedEntryId: UUID?
    let linkSource: String; let createdAt: Date; let updatedAt: Date
    init(_ j: JournalEntry, body: String, link: JournalTimeLink?) {
        id = j.id; self.body = body; capturedAt = j.capturedAt; anchorAt = j.anchorAt
        linkedEntryId = link?.timeEntryID; linkSource = link?.linkSource ?? ThoughtLinkSource.none.rawValue
        createdAt = j.createdAt; updatedAt = j.updatedAt
    }
}
