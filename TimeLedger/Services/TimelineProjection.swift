import Foundation

extension ThoughtNote {
    var hasTextContent: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

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
    let thought: ThoughtNote?
    let mediaMoments: [MediaMoment]
    let linkedEntry: TimeEntry?
    let noteText: String
    let relatedThoughtCount: Int
    let isRelatedToNote: Bool

    var hasText: Bool {
        switch kind {
        case .note:
            !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .thought:
            thought?.hasTextContent == true
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
        thought: ThoughtNote? = nil,
        mediaMoments: [MediaMoment],
        linkedEntry: TimeEntry? = nil,
        noteText: String = "",
        relatedThoughtCount: Int = 0,
        isRelatedToNote: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.displayEndAt = displayEndAt
        self.thought = thought
        self.mediaMoments = mediaMoments
        self.linkedEntry = linkedEntry
        self.noteText = noteText
        self.relatedThoughtCount = relatedThoughtCount
        self.isRelatedToNote = isRelatedToNote
    }
}

enum TimelineContentFilter: String, CaseIterable, Hashable, Identifiable {
    case text
    case photos
    case videos

    var id: String { rawValue }

    func matches(_ record: TimelineRecord) -> Bool {
        switch self {
        case .text:
            record.hasText
        case .photos:
            record.hasPhoto
        case .videos:
            record.hasVideo
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
        thoughts: [ThoughtNote],
        mediaMoments: [MediaMoment],
        mediaLinks: [ThoughtMediaLink],
        entries: [TimeEntry] = []
    ) -> [TimelineRecord] {
        let thoughtByID = Dictionary(uniqueKeysWithValues: thoughts.map { ($0.id, $0) })
        let mediaByID = Dictionary(uniqueKeysWithValues: mediaMoments.map { ($0.id, $0) })
        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        var attachedMediaByThoughtID: [UUID: [(sortOrder: Int, mediaID: UUID)]] = [:]
        var thoughtMediaIDs: Set<UUID> = []

        for link in mediaLinks {
            guard let thought = thoughtByID[link.thoughtId],
                  mediaByID[link.mediaMomentId] != nil,
                  thoughtMediaIDs.insert(link.mediaMomentId).inserted else {
                continue
            }
            attachedMediaByThoughtID[thought.id, default: []].append(
                (sortOrder: link.sortOrder, mediaID: link.mediaMomentId)
            )
        }

        var noteMediaByEntryID: [UUID: [MediaMoment]] = [:]
        var consumedMediaIDs = thoughtMediaIDs

        for moment in mediaMoments {
            guard !thoughtMediaIDs.contains(moment.id) else { continue }
            guard moment.linkSourceEnum == .manual,
                  let entryID = moment.linkedEntryId,
                  entryByID[entryID] != nil else {
                continue
            }
            noteMediaByEntryID[entryID, default: []].append(moment)
            consumedMediaIDs.insert(moment.id)
        }

        var thoughtCountByEntryID: [UUID: Int] = [:]
        for thought in thoughts {
            guard let entryID = thought.linkedEntryId, entryByID[entryID] != nil else { continue }
            thoughtCountByEntryID[entryID, default: 0] += 1
        }

        var noteEntryIDs: Set<UUID> = []
        var projected: [TimelineRecord] = []

        for entry in entries {
            let trimmedNote = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachments = (noteMediaByEntryID[entry.id] ?? [])
                .sorted {
                    if $0.capturedAt == $1.capturedAt {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.capturedAt < $1.capturedAt
                }
            guard !trimmedNote.isEmpty || !attachments.isEmpty else { continue }
            noteEntryIDs.insert(entry.id)
            projected.append(
                TimelineRecord(
                    id: "note-\(entry.id.uuidString)",
                    kind: .note,
                    capturedAt: entry.startAt,
                    displayEndAt: entry.endAt,
                    thought: nil,
                    mediaMoments: attachments,
                    linkedEntry: entry,
                    noteText: entry.note,
                    relatedThoughtCount: thoughtCountByEntryID[entry.id] ?? 0,
                    isRelatedToNote: false
                )
            )
        }

        for thought in thoughts {
            let attachedMedia = (attachedMediaByThoughtID[thought.id] ?? [])
                .sorted {
                    if $0.sortOrder == $1.sortOrder {
                        return $0.mediaID.uuidString < $1.mediaID.uuidString
                    }
                    return $0.sortOrder < $1.sortOrder
                }
                .compactMap { mediaByID[$0.mediaID] }
            let linked = thought.linkedEntryId.flatMap { entryByID[$0] }
            let useEntryTime = thought.linkSourceEnum == .manual && linked != nil
            projected.append(
                TimelineRecord(
                    id: "thought-\(thought.id.uuidString)",
                    kind: .thought,
                    capturedAt: useEntryTime ? linked!.startAt : thought.anchorAt,
                    displayEndAt: useEntryTime ? linked!.endAt : nil,
                    thought: thought,
                    mediaMoments: attachedMedia,
                    linkedEntry: linked,
                    noteText: "",
                    relatedThoughtCount: 0,
                    isRelatedToNote: linked.map { noteEntryIDs.contains($0.id) } ?? false
                )
            )
        }

        for moment in mediaMoments where !consumedMediaIDs.contains(moment.id) {
            let linked = moment.linkedEntryId.flatMap { entryByID[$0] }
            let useEntryTime = moment.linkSourceEnum == .manual && linked != nil
            projected.append(
                TimelineRecord(
                    id: "media-\(moment.id.uuidString)",
                    kind: .thought,
                    capturedAt: useEntryTime ? linked!.startAt : moment.anchorAt,
                    displayEndAt: useEntryTime ? linked!.endAt : nil,
                    thought: nil,
                    mediaMoments: [moment],
                    linkedEntry: linked,
                    noteText: "",
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
