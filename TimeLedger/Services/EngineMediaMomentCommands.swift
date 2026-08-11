import Foundation
import SwiftData

@MainActor
struct MediaMomentCommandHandler {
    let modelContext: ModelContext

    private var queries: TimeLedgerQueries {
        TimeLedgerQueries(modelContext: modelContext)
    }

    /// 插入新 MediaMoment 并提交；失败时回滚插入，抛出原始错误。
    func save(_ moment: MediaMoment) throws {
        modelContext.insert(moment)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(moment)
            throw error
        }
    }

    /// 删除 MediaMoment 及其所有 ContentAttachment，一次提交。
    func delete(_ moment: MediaMoment) throws {
        let attachments = try queries.digestAllAttachments()
        for attachment in attachments where attachment.mediaMomentID == moment.id {
            modelContext.delete(attachment)
        }
        modelContext.delete(moment)
        try modelContext.save()
    }

    /// 为 MediaMoment 创建关联 JournalEntry + ContentDocument + ContentAttachment，一次提交。
    func attachAsJournal(_ moment: MediaMoment) throws {
        let journal = JournalEntry(capturedAt: moment.capturedAt, anchorAt: moment.capturedAt)
        let document = ContentDocument(ownerID: journal.id, ownerKind: .journalEntry)
        let attachment = ContentAttachment(
            contentDocumentID: document.id,
            mediaMomentID: moment.id,
            state: .pending
        )
        modelContext.insert(journal)
        modelContext.insert(document)
        modelContext.insert(attachment)
        try modelContext.save()
    }
}
