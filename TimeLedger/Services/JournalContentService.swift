import Foundation
import SwiftData

/// 兼容 facade：只转发给 TimeLedgerEngine，不再直接写数据库。
@MainActor
struct JournalContentService {
    let modelContext: ModelContext

    private var engine: TimeLedgerEngine {
        TimeLedgerEngine(modelContext: modelContext)
    }

    func link(_ journal: JournalEntry, to entry: TimeEntry) throws {
        try engine.link(journal, to: entry)
    }

    func unlink(_ journal: JournalEntry) throws {
        try engine.unlink(journal)
    }

    @discardableResult
    func linkUnlinkedJournals(to entry: TimeEntry) throws -> Int {
        try engine.linkUnlinkedJournals(to: entry)
    }

    @discardableResult
    func reconcileAutoLinks() throws -> Int {
        try engine.reconcileAutoLinks()
    }

    func delete(_ journal: JournalEntry) throws {
        try engine.delete(journal)
    }

    func setFavorite(_ journal: JournalEntry, _ value: Bool) throws {
        try engine.setFavorite(journal, value)
    }
}
