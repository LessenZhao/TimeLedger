import Foundation
import Testing
@testable import TimeLedger

@MainActor
struct TimelineProjectionTests {
    @Test func textPhotoAndVideoFormOneRecordThatMatchesAllRelevantFilters() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let thought = ThoughtNote(body: "记录当下的想法", capturedAt: capturedAt)
        let photo = mediaMoment(kind: .photo, capturedAt: capturedAt.addingTimeInterval(10))
        let video = mediaMoment(kind: .video, capturedAt: capturedAt.addingTimeInterval(20))

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [photo, video],
            mediaLinks: [
                ThoughtMediaLink(thoughtId: thought.id, mediaMomentId: photo.id, sortOrder: 1),
                ThoughtMediaLink(thoughtId: thought.id, mediaMomentId: video.id, sortOrder: 0),
            ]
        )

        #expect(records.count == 1)
        let record = records[0]
        #expect(record.id == "thought-\(thought.id.uuidString)")
        #expect(record.mediaMoments.map(\.id) == [video.id, photo.id])
        #expect(TimelineContentFilter.matches(record, selectedFilters: []))
        #expect(TimelineContentFilter.text.matches(record))
        #expect(TimelineContentFilter.photos.matches(record))
        #expect(TimelineContentFilter.videos.matches(record))
    }

    @Test func standalonePhotoAndVideoDoNotMatchThoughtFilter() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let photo = mediaMoment(kind: .photo, capturedAt: capturedAt)
        let video = mediaMoment(kind: .video, capturedAt: capturedAt.addingTimeInterval(10))

        let records = TimelineProjection.records(
            thoughts: [],
            mediaMoments: [photo, video],
            mediaLinks: []
        )

        #expect(records.map(\.id) == ["media-\(video.id.uuidString)", "media-\(photo.id.uuidString)"])
        #expect(records.allSatisfy { !TimelineContentFilter.text.matches($0) })
        #expect(TimelineContentFilter.photos.matches(records[1]))
        #expect(!TimelineContentFilter.videos.matches(records[1]))
        #expect(TimelineContentFilter.videos.matches(records[0]))
        #expect(!TimelineContentFilter.photos.matches(records[0]))
        #expect(!TimelineContentFilter.matches(records[0], selectedFilters: [.text, .photos]))
        #expect(TimelineContentFilter.matches(records[1], selectedFilters: [.text, .photos]))
    }

    @Test func legacyEmptyThoughtWithManualPhotoProjectsAsMediaWithoutChangingLink() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let entryID = UUID()
        let emptyThought = ThoughtNote(
            body: " \n ",
            capturedAt: capturedAt,
            linkedEntryId: entryID,
            linkSource: .manual
        )
        let photo = mediaMoment(
            kind: .photo,
            capturedAt: capturedAt,
            linkedEntryId: entryID,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [emptyThought],
            mediaMoments: [photo],
            mediaLinks: [
                ThoughtMediaLink(thoughtId: emptyThought.id, mediaMomentId: photo.id, sortOrder: 0)
            ]
        )

        #expect(records.count == 1)
        let record = records[0]
        #expect(record.id == "media-\(photo.id.uuidString)")
        #expect(record.thought == nil)
        #expect(record.mediaMoments.map(\.id) == [photo.id])
        #expect(!TimelineContentFilter.text.matches(record))
        #expect(TimelineContentFilter.photos.matches(record))
        #expect(photo.linkedEntryId == entryID)
        #expect(photo.linkSourceEnum == .manual)
    }

    @Test func legacyEmptyThoughtWithAutoVideoRemainsVideoOnly() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let entryID = UUID()
        let emptyThought = ThoughtNote(body: "", capturedAt: capturedAt)
        let video = mediaMoment(
            kind: .video,
            capturedAt: capturedAt,
            linkedEntryId: entryID,
            linkSource: .auto
        )

        let records = TimelineProjection.records(
            thoughts: [emptyThought],
            mediaMoments: [video],
            mediaLinks: [
                ThoughtMediaLink(thoughtId: emptyThought.id, mediaMomentId: video.id, sortOrder: 0)
            ]
        )

        #expect(records.count == 1)
        #expect(records[0].id == "media-\(video.id.uuidString)")
        #expect(!TimelineContentFilter.text.matches(records[0]))
        #expect(TimelineContentFilter.videos.matches(records[0]))
        #expect(video.linkedEntryId == entryID)
        #expect(video.linkSourceEnum == .auto)
    }

    private func mediaMoment(
        kind: MediaKind,
        capturedAt: Date,
        linkedEntryId: UUID? = nil,
        linkSource: ThoughtLinkSource = .none
    ) -> MediaMoment {
        MediaMoment(
            kind: kind,
            capturedAt: capturedAt,
            linkedEntryId: linkedEntryId,
            linkSource: linkSource,
            requestedStorage: .app,
            thumbnailData: Data([1])
        )
    }
}
