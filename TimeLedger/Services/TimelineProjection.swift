import Foundation

extension ThoughtNote {
    var hasTextContent: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TimelineRecord: Identifiable {
    let id: String
    let capturedAt: Date
    let thought: ThoughtNote?
    let mediaMoments: [MediaMoment]

    var hasText: Bool {
        thought?.hasTextContent == true
    }

    var hasPhoto: Bool {
        mediaMoments.contains { $0.kind == .photo }
    }

    var hasVideo: Bool {
        mediaMoments.contains { $0.kind == .video }
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

enum TimelineProjection {
    static func records(
        thoughts: [ThoughtNote],
        mediaMoments: [MediaMoment],
        mediaLinks: [ThoughtMediaLink]
    ) -> [TimelineRecord] {
        let thoughtByID = Dictionary(uniqueKeysWithValues: thoughts.map { ($0.id, $0) })
        let mediaByID = Dictionary(uniqueKeysWithValues: mediaMoments.map { ($0.id, $0) })
        var attachedMediaByThoughtID: [UUID: [(sortOrder: Int, mediaID: UUID)]] = [:]
        var attachedMediaIDs: Set<UUID> = []

        for link in mediaLinks {
            guard let thought = thoughtByID[link.thoughtId],
                  thought.hasTextContent,
                  mediaByID[link.mediaMomentId] != nil,
                  attachedMediaIDs.insert(link.mediaMomentId).inserted else {
                continue
            }
            attachedMediaByThoughtID[thought.id, default: []].append(
                (sortOrder: link.sortOrder, mediaID: link.mediaMomentId)
            )
        }

        let thoughtRecords = thoughts.compactMap { thought -> TimelineRecord? in
            guard thought.hasTextContent else { return nil }
            let attachedMedia = (attachedMediaByThoughtID[thought.id] ?? [])
                .sorted {
                    if $0.sortOrder == $1.sortOrder {
                        return $0.mediaID.uuidString < $1.mediaID.uuidString
                    }
                    return $0.sortOrder < $1.sortOrder
                }
                .compactMap { mediaByID[$0.mediaID] }
            return TimelineRecord(
                id: "thought-\(thought.id.uuidString)",
                capturedAt: thought.capturedAt,
                thought: thought,
                mediaMoments: attachedMedia
            )
        }

        let standaloneMediaRecords = mediaMoments
            .filter { !attachedMediaIDs.contains($0.id) }
            .map { moment in
                TimelineRecord(
                    id: "media-\(moment.id.uuidString)",
                    capturedAt: moment.capturedAt,
                    thought: nil,
                    mediaMoments: [moment]
                )
            }

        return (thoughtRecords + standaloneMediaRecords).sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.id < $1.id
            }
            return $0.capturedAt > $1.capturedAt
        }
    }
}
