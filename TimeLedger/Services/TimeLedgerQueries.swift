import Foundation
import SwiftData

/// 薄查询入口：所有读侧走带谓词的存储查询，禁止 View 全表拉取后自行过滤。
/// 全量扫描仅允许封装在 `digestAll*` / `export*` / `reconcile*` 命名的批处理查询中。
@MainActor
struct TimeLedgerQueries {
    let modelContext: ModelContext

    // MARK: - TimeEntry

    func entry(id: UUID) throws -> TimeEntry? {
        var descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func nextEntry(after entryID: UUID, startAt: Date, endAt: Date) throws -> TimeEntry? {
        var forward = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.id != entryID && $0.startAt >= endAt },
            sortBy: [SortDescriptor(\.startAt)]
        )
        forward.fetchLimit = 1
        if let next = try modelContext.fetch(forward).first {
            return next
        }
        var fallback = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.id != entryID && $0.startAt > startAt },
            sortBy: [SortDescriptor(\.startAt)]
        )
        fallback.fetchLimit = 1
        return try modelContext.fetch(fallback).first
    }

    // MARK: - TimeCursor

    func cursor() throws -> TimeCursor? {
        var descriptor = FetchDescriptor<TimeCursor>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - ContentDocument

    func document(id: UUID) throws -> ContentDocument? {
        var descriptor = FetchDescriptor<ContentDocument>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func document(ownerID: UUID, ownerKind: ContentOwnerKind) throws -> ContentDocument? {
        var descriptor = FetchDescriptor<ContentDocument>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.ownerKind == ownerKind.rawValue }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func documents(ownerID: UUID, ownerKind: ContentOwnerKind) throws -> [ContentDocument] {
        try modelContext.fetch(
            FetchDescriptor<ContentDocument>(
                predicate: #Predicate { $0.ownerID == ownerID && $0.ownerKind == ownerKind.rawValue }
            )
        )
    }

    // MARK: - ContentAttachment

    func attachments(documentID: UUID) throws -> [ContentAttachment] {
        try modelContext.fetch(
            FetchDescriptor<ContentAttachment>(
                predicate: #Predicate { $0.contentDocumentID == documentID }
            )
        )
    }

    func attachments(documentIDs: Set<UUID>) throws -> [ContentAttachment] {
        guard !documentIDs.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<ContentAttachment>(
                predicate: #Predicate { documentIDs.contains($0.contentDocumentID) }
            )
        )
    }

    // MARK: - JournalEntry

    func journal(id: UUID) throws -> JournalEntry? {
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func journals(ids: Set<UUID>) throws -> [JournalEntry] {
        guard !ids.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<JournalEntry>(
                predicate: #Predicate { ids.contains($0.id) }
            )
        )
    }

    // MARK: - JournalTimeLink

    func journalLinks(timeEntryID: UUID) throws -> [JournalTimeLink] {
        try modelContext.fetch(
            FetchDescriptor<JournalTimeLink>(
                predicate: #Predicate { $0.timeEntryID == timeEntryID }
            )
        )
    }

    func journalLinks(timeEntryIDs: Set<UUID>) throws -> [JournalTimeLink] {
        guard !timeEntryIDs.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<JournalTimeLink>(
                predicate: #Predicate { timeEntryIDs.contains($0.timeEntryID) }
            )
        )
    }

    func journalLink(journalEntryID: UUID) throws -> JournalTimeLink? {
        var descriptor = FetchDescriptor<JournalTimeLink>(
            predicate: #Predicate { $0.journalEntryID == journalEntryID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func journalLinks(journalEntryID: UUID) throws -> [JournalTimeLink] {
        try modelContext.fetch(
            FetchDescriptor<JournalTimeLink>(
                predicate: #Predicate { $0.journalEntryID == journalEntryID }
            )
        )
    }

    // MARK: - MediaMoment

    func mediaMoment(id: UUID) throws -> MediaMoment? {
        var descriptor = FetchDescriptor<MediaMoment>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func mediaMoments(ids: Set<UUID>) throws -> [MediaMoment] {
        guard !ids.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<MediaMoment>(
                predicate: #Predicate { ids.contains($0.id) }
            )
        )
    }

    // MARK: - Batch / Digest / Reconcile (全量扫描仅允许在此类命名方法中)

    func digestAllDocuments() throws -> [ContentDocument] {
        try modelContext.fetch(FetchDescriptor<ContentDocument>())
    }

    func digestAllAttachments() throws -> [ContentAttachment] {
        try modelContext.fetch(FetchDescriptor<ContentAttachment>())
    }

    func digestAllJournals() throws -> [JournalEntry] {
        try modelContext.fetch(FetchDescriptor<JournalEntry>())
    }

    func digestAllLinks() throws -> [JournalTimeLink] {
        try modelContext.fetch(FetchDescriptor<JournalTimeLink>())
    }

    func digestAllTimeEntries() throws -> [TimeEntry] {
        try modelContext.fetch(FetchDescriptor<TimeEntry>())
    }

    func digestAllMedia() throws -> [MediaMoment] {
        try modelContext.fetch(FetchDescriptor<MediaMoment>())
    }

    func digestAllCursors() throws -> [TimeCursor] {
        try modelContext.fetch(FetchDescriptor<TimeCursor>())
    }

    func entriesSortedByStartAt() throws -> [TimeEntry] {
        try modelContext.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startAt)]))
    }

}
