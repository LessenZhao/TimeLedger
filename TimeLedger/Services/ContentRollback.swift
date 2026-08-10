import Foundation
import SwiftData

struct ContentAttachmentSnapshot: Equatable, Sendable {
    let id: UUID
    let mediaMomentID: UUID
    let sortOrder: Int
    let state: String
    let lastError: String?
    let createdAt: Date
}

struct ContentEditSnapshot: Equatable, Sendable {
    let documentID: UUID
    let ownerID: UUID
    let ownerKind: ContentOwnerKind
    let body: String
    let revision: Int
    let createdAt: Date
    let updatedAt: Date
    let attachments: [ContentAttachmentSnapshot]
}

@MainActor
enum PendingContentSnapshots {
    private static var snapshots: [UUID: ContentEditSnapshot] = [:]

    static func recordIfAbsent(_ snapshot: ContentEditSnapshot) {
        if snapshots[snapshot.documentID] == nil {
            snapshots[snapshot.documentID] = snapshot
        }
    }

    static func pending(documentID: UUID) -> ContentEditSnapshot? {
        snapshots[documentID]
    }

    static func clear(ownerID: UUID, ownerKind: ContentOwnerKind) {
        snapshots = snapshots.filter {
            $0.value.ownerID != ownerID || $0.value.ownerKind != ownerKind
        }
    }
}

@MainActor
enum ContentRollback {
    static func restorePendingContent(
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        modelContext: ModelContext
    ) throws {
        let documents = try modelContext.fetch(FetchDescriptor<ContentDocument>())
        for document in documents where document.ownerID == ownerID && document.ownerKindEnum == ownerKind {
            guard let snapshot = PendingContentSnapshots.pending(documentID: document.id) else { continue }
            try apply(snapshot, to: document, modelContext: modelContext)
        }
        try modelContext.save()
    }

    private static func apply(
        _ snapshot: ContentEditSnapshot,
        to document: ContentDocument,
        modelContext: ModelContext
    ) throws {
        document.body = snapshot.body
        document.revision = snapshot.revision
        document.updatedAt = snapshot.updatedAt

        let attachments = try modelContext.fetch(FetchDescriptor<ContentAttachment>())
            .filter { $0.contentDocumentID == document.id }
        let snapshotByMediaID = Dictionary(
            uniqueKeysWithValues: snapshot.attachments.map { ($0.mediaMomentID, $0) }
        )
        for attachment in attachments where snapshotByMediaID[attachment.mediaMomentID] == nil {
            modelContext.delete(attachment)
        }
        for snapshotAttachment in snapshot.attachments {
            if let existing = attachments.first(where: { $0.mediaMomentID == snapshotAttachment.mediaMomentID }) {
                existing.id = snapshotAttachment.id
                existing.sortOrder = snapshotAttachment.sortOrder
                existing.state = snapshotAttachment.state
                existing.lastError = snapshotAttachment.lastError
                existing.createdAt = snapshotAttachment.createdAt
            } else {
                modelContext.insert(ContentAttachment(
                    id: snapshotAttachment.id,
                    contentDocumentID: document.id,
                    mediaMomentID: snapshotAttachment.mediaMomentID,
                    sortOrder: snapshotAttachment.sortOrder,
                    state: ContentAttachmentState(rawValue: snapshotAttachment.state) ?? .failed,
                    lastError: snapshotAttachment.lastError,
                    createdAt: snapshotAttachment.createdAt
                ))
            }
        }
        PendingContentSnapshots.clear(ownerID: document.ownerID, ownerKind: document.ownerKindEnum)
    }
}
