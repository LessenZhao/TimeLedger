import Foundation

enum TimelineRecordKind: String, Hashable {
    case note
    case thought
}

struct TimelineRecord: Identifiable {
    let id: String
    let kind: TimelineRecordKind
    /// Semantic start used for sorting and day grouping (entry startAt or own time).
    let capturedAt: Date
    let displayEndAt: Date?
    let journal: JournalEntry?
    let mediaMoments: [MediaMoment]
    let linkedEntry: TimeEntry?
    let noteText: String
    let journalText: String
    let relatedThoughtCount: Int
    let isRelatedToNote: Bool

    var hasText: Bool {
        switch kind {
        case .note:
            !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .thought:
            !journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var hasPhoto: Bool {
        mediaMoments.contains { $0.kind == .photo }
    }

    var hasVideo: Bool {
        mediaMoments.contains { $0.kind == .video }
    }

    init(
        id: String,
        kind: TimelineRecordKind,
        capturedAt: Date,
        displayEndAt: Date? = nil,
        journal: JournalEntry? = nil,
        mediaMoments: [MediaMoment],
        linkedEntry: TimeEntry? = nil,
        noteText: String = "",
        journalText: String = "",
        relatedThoughtCount: Int = 0,
        isRelatedToNote: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.displayEndAt = displayEndAt
        self.journal = journal
        self.mediaMoments = mediaMoments
        self.linkedEntry = linkedEntry
        self.noteText = noteText
        self.journalText = journalText
        self.relatedThoughtCount = relatedThoughtCount
        self.isRelatedToNote = isRelatedToNote
    }
}

enum TimelineContentFilter: String, CaseIterable, Hashable, Identifiable {
    case text
    case photos
    case videos
    case favorite

    var id: String { rawValue }

    func matches(_ record: TimelineRecord) -> Bool {
        switch self {
        case .text:
            record.hasText
        case .photos:
            record.hasPhoto
        case .videos:
            record.hasVideo
        case .favorite:
            record.journal?.isFavorite == true
        }
    }

    static func matches(
        _ record: TimelineRecord,
        selectedFilters: Set<TimelineContentFilter>
    ) -> Bool {
        selectedFilters.isEmpty || selectedFilters.contains { $0.matches(record) }
    }
}

enum TimelineTypeMode: String, CaseIterable, Hashable, Identifiable {
    case notes
    case thoughts
    case merged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "时间记录"
        case .thoughts: "随记"
        case .merged: "合并"
        }
    }

    func matches(_ record: TimelineRecord) -> Bool {
        switch self {
        case .merged:
            true
        case .notes:
            record.kind == .note
        case .thoughts:
            record.kind == .thought
        }
    }
}

enum TimelineProjection {
    static func records(
        journals: [JournalEntry],
        documents: [ContentDocument],
        contentAttachments: [ContentAttachment],
        journalLinks: [JournalTimeLink],
        mediaMoments: [MediaMoment],
        entries: [TimeEntry] = []
    ) -> [TimelineRecord] {
        let mediaByID = Dictionary(uniqueKeysWithValues: mediaMoments.map { ($0.id, $0) })
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        let documentsByOwnerKey = Dictionary(uniqueKeysWithValues: documents.map { ($0.ownerKey, $0) })
        let attachmentsByDocumentID = Dictionary(grouping: contentAttachments, by: \.contentDocumentID)
        let linksByJournalID = Dictionary(uniqueKeysWithValues: journalLinks.map { ($0.journalEntryID, $0) })
        let journalCountByEntryID = Dictionary(
            grouping: journalLinks.filter { entryByID[$0.timeEntryID] != nil },
            by: \.timeEntryID
        ).mapValues(\.count)

        func document(ownerID: UUID, kind: ContentOwnerKind) -> ContentDocument? {
            documentsByOwnerKey[ContentDocument.key(ownerID: ownerID, ownerKind: kind)]
        }

        func media(documentID: UUID) -> [MediaMoment] {
            (attachmentsByDocumentID[documentID] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .compactMap { mediaByID[$0.mediaMomentID] }
        }

        var noteEntryIDs: Set<UUID> = []
        var projected: [TimelineRecord] = []

        for entry in entries {
            guard let content = document(ownerID: entry.id, kind: .timeEntry) else { continue }
            let attachments = media(documentID: content.id)
            guard !content.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !attachments.isEmpty else { continue }
            noteEntryIDs.insert(entry.id)
            projected.append(
                TimelineRecord(
                    id: "note-\(entry.id.uuidString)",
                    kind: .note,
                    capturedAt: entry.startAt,
                    displayEndAt: entry.endAt,
                    journal: nil,
                    mediaMoments: attachments,
                    linkedEntry: entry,
                    noteText: content.body,
                    relatedThoughtCount: journalCountByEntryID[entry.id] ?? 0,
                    isRelatedToNote: false
                )
            )
        }

        for journal in journals {
            guard let content = document(ownerID: journal.id, kind: .journalEntry) else { continue }
            let attachedMedia = media(documentID: content.id)
            let journalLink = linksByJournalID[journal.id]
            let linked = journalLink.flatMap { entryByID[$0.timeEntryID] }
            let useEntryTime = journalLink?.linkSource == ThoughtLinkSource.manual.rawValue && linked != nil
            projected.append(
                TimelineRecord(
                    id: "journal-\(journal.id.uuidString)",
                    kind: .thought,
                    capturedAt: useEntryTime ? linked!.startAt : journal.anchorAt,
                    displayEndAt: useEntryTime ? linked!.endAt : nil,
                    journal: journal,
                    mediaMoments: attachedMedia,
                    linkedEntry: linked,
                    noteText: "",
                    journalText: content.body,
                    relatedThoughtCount: 0,
                    isRelatedToNote: linked.map { noteEntryIDs.contains($0.id) } ?? false
                )
            )
        }

        return projected.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.id < $1.id
            }
            return $0.capturedAt > $1.capturedAt
        }
    }
}
