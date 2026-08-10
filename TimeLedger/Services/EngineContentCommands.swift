import Foundation
import SwiftData

@MainActor
struct ContentCommandHandler {
    let modelContext: ModelContext

    private var queries: TimeLedgerQueries {
        TimeLedgerQueries(modelContext: modelContext)
    }

    func save(_ session: ContentEditorSession) throws {
        guard let document = try queries.document(id: session.contentID) else {
            throw SaveContentError.missingDocument
        }
        guard document.revision == session.baseRevision else {
            throw SaveContentError.revisionConflict
        }

        let allMedia = try queries.digestAllMedia()
        let desiredIDs = session.workingAttachments.map(\.mediaMomentID)
        let desiredSet = Set(desiredIDs)
        for mediaID in desiredIDs where !allMedia.contains(where: { $0.id == mediaID }) {
            throw SaveContentError.missingMedia(mediaID)
        }

        let currentAttachments = try queries.attachments(documentID: document.id)
        PendingContentSnapshots.recordIfAbsent(ContentEditSnapshot(
            documentID: document.id,
            ownerID: document.ownerID,
            ownerKind: document.ownerKindEnum,
            body: document.body,
            revision: document.revision,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            attachments: currentAttachments.map {
                ContentAttachmentSnapshot(
                    id: $0.id,
                    mediaMomentID: $0.mediaMomentID,
                    sortOrder: $0.sortOrder,
                    state: $0.state,
                    lastError: $0.lastError,
                    createdAt: $0.createdAt
                )
            }
        ))

        try modelContext.transaction {
            let allAttachments = try queries.digestAllAttachments()
            let current = allAttachments.filter { $0.contentDocumentID == document.id }
            for attachment in current where !desiredSet.contains(attachment.mediaMomentID) {
                modelContext.delete(attachment)
            }
            for (index, mediaID) in desiredIDs.enumerated() {
                if let existing = current.first(where: { $0.mediaMomentID == mediaID }) {
                    existing.sortOrder = index
                    existing.state = ContentAttachmentState.ready.rawValue
                    existing.lastError = nil
                } else if let attachedElsewhere = allAttachments.first(where: {
                    $0.mediaMomentID == mediaID && $0.contentDocumentID != document.id
                }) {
                    throw SaveContentError.mediaAlreadyAttached(attachedElsewhere.mediaMomentID)
                } else {
                    modelContext.insert(ContentAttachment(
                        contentDocumentID: document.id,
                        mediaMomentID: mediaID,
                        sortOrder: index,
                        state: .ready
                    ))
                }
            }
            document.body = session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines)
            document.revision += 1
            document.updatedAt = Date()
            try modelContext.save()
        }
    }

    func createTimeEntryDocumentAndSave(
        _ session: ContentEditorSession,
        entry: TimeEntry
    ) throws {
        if let existing = try queries.document(ownerID: entry.id, ownerKind: .timeEntry) {
            try modelContext.transaction {
                existing.body = session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.revision = max(1, existing.revision)
                existing.updatedAt = Date()
                try insertDesiredAttachments(session, document: existing)
                try modelContext.save()
            }
            return
        }
        try modelContext.transaction {
            let document = ContentDocument(
                id: session.contentID,
                ownerID: entry.id,
                ownerKind: .timeEntry,
                body: session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines),
                revision: 1,
                createdAt: entry.createdAt,
                updatedAt: Date()
            )
            modelContext.insert(document)
            try insertDesiredAttachments(session, document: document)
            try modelContext.save()
        }
    }

    func createJournalAndSave(
        _ session: ContentEditorSession,
        capturedAt: Date,
        anchorAt: Date,
        linkedEntryID: UUID?,
        linkSource: JournalLinkSource
    ) throws {
        if try queries.journal(id: session.ownerID) != nil {
            try save(session)
            return
        }
        try modelContext.transaction {
            modelContext.insert(JournalEntry(
                id: session.ownerID,
                capturedAt: capturedAt,
                anchorAt: anchorAt,
                createdAt: capturedAt,
                updatedAt: Date()
            ))
            let document = ContentDocument(
                id: session.contentID,
                ownerID: session.ownerID,
                ownerKind: .journalEntry,
                body: session.workingBody.trimmingCharacters(in: .whitespacesAndNewlines),
                revision: 1,
                createdAt: capturedAt,
                updatedAt: Date()
            )
            modelContext.insert(document)
            if let linkedEntryID {
                modelContext.insert(JournalTimeLink(
                    id: session.ownerID,
                    journalEntryID: session.ownerID,
                    timeEntryID: linkedEntryID,
                    linkSource: linkSource,
                    createdAt: capturedAt,
                    updatedAt: Date()
                ))
            }
            try insertDesiredAttachments(session, document: document)
            try modelContext.save()
        }
    }

    private func insertDesiredAttachments(
        _ session: ContentEditorSession,
        document: ContentDocument
    ) throws {
        let media = try queries.digestAllMedia()
        for (index, attachment) in session.workingAttachments.enumerated() {
            guard media.contains(where: { $0.id == attachment.mediaMomentID }) else {
                throw SaveContentError.missingMedia(attachment.mediaMomentID)
            }
            modelContext.insert(ContentAttachment(
                contentDocumentID: document.id,
                mediaMomentID: attachment.mediaMomentID,
                sortOrder: index,
                state: .ready
            ))
        }
    }
}
