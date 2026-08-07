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

    @Test func emptyThoughtWithManualPhotoRetainsThoughtIdentityAndOwnsMedia() {
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
        #expect(record.id == "thought-\(emptyThought.id.uuidString)")
        #expect(record.thought?.id == emptyThought.id)
        #expect(record.mediaMoments.map(\.id) == [photo.id])
        #expect(!TimelineContentFilter.text.matches(record))
        #expect(TimelineContentFilter.photos.matches(record))
        #expect(photo.linkedEntryId == entryID)
        #expect(photo.linkSourceEnum == .manual)
    }

    @Test func emptyThoughtWithAutoVideoRetainsThoughtIdentityAndOwnsMedia() {
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
        #expect(records[0].id == "thought-\(emptyThought.id.uuidString)")
        #expect(records[0].thought?.id == emptyThought.id)
        #expect(records[0].mediaMoments.map(\.id) == [video.id])
        #expect(!TimelineContentFilter.text.matches(records[0]))
        #expect(TimelineContentFilter.videos.matches(records[0]))
        #expect(video.linkedEntryId == entryID)
        #expect(video.linkSourceEnum == .auto)
    }

    // MARK: - Semantic time projection

    @Test func notePhotoCapturedInAugustProjectsOntoJulyEntryDay() {
        let july20 = date(2026, 7, 20, 10, 0)
        let july20End = date(2026, 7, 20, 12, 0)
        let august6 = date(2026, 8, 6, 15, 30)
        let entry = timeEntry(startAt: july20, endAt: july20End, note: "")
        let notePhoto = mediaMoment(
            kind: .photo,
            capturedAt: august6,
            linkedEntryId: entry.id,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [],
            mediaMoments: [notePhoto],
            mediaLinks: [],
            entries: [entry]
        )

        #expect(records.count == 1)
        let record = records[0]
        #expect(record.kind == .note)
        #expect(record.id == "note-\(entry.id.uuidString)")
        #expect(record.capturedAt == july20)
        #expect(record.displayEndAt == july20End)
        #expect(record.mediaMoments.map(\.id) == [notePhoto.id])
        #expect(notePhoto.capturedAt == august6)
        #expect(Calendar.current.isDate(record.capturedAt, inSameDayAs: july20))
        #expect(!Calendar.current.isDate(record.capturedAt, inSameDayAs: august6))
    }

    @Test func manualThoughtInsideEntryUsesEntryTimeRange() {
        let entryStart = date(2026, 7, 20, 9, 0)
        let entryEnd = date(2026, 7, 20, 11, 0)
        let capturedLater = date(2026, 8, 6, 18, 0)
        let entry = timeEntry(startAt: entryStart, endAt: entryEnd, note: "当日备注")
        let thought = ThoughtNote(
            body: "条目内事后思考",
            capturedAt: capturedLater,
            anchorAt: capturedLater,
            linkedEntryId: entry.id,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [],
            mediaLinks: [],
            entries: [entry]
        )

        let thoughtRecord = records.first { $0.kind == .thought }
        #expect(thoughtRecord != nil)
        #expect(thoughtRecord?.capturedAt == entryStart)
        #expect(thoughtRecord?.displayEndAt == entryEnd)
        #expect(thoughtRecord?.linkedEntry?.id == entry.id)
        #expect(thought.capturedAt == capturedLater)
        #expect(thought.anchorAt == capturedLater)
    }

    @Test func standaloneHomeThoughtKeepsOwnCaptureTime() {
        let august6 = date(2026, 8, 6, 14, 0)
        let thought = ThoughtNote(body: "首页独立思考", capturedAt: august6, anchorAt: august6)

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [],
            mediaLinks: [],
            entries: []
        )

        #expect(records.count == 1)
        #expect(records[0].kind == .thought)
        #expect(records[0].capturedAt == august6)
        #expect(records[0].displayEndAt == nil)
        #expect(records[0].linkedEntry == nil)
        #expect(Calendar.current.isDate(records[0].capturedAt, inSameDayAs: august6))
    }

    @Test func standaloneHomeMediaProjectsAsThoughtAtOwnTime() {
        let august6 = date(2026, 8, 6, 16, 0)
        let photo = mediaMoment(kind: .photo, capturedAt: august6)

        let records = TimelineProjection.records(
            thoughts: [],
            mediaMoments: [photo],
            mediaLinks: [],
            entries: []
        )

        #expect(records.count == 1)
        #expect(records[0].kind == .thought)
        #expect(records[0].id == "media-\(photo.id.uuidString)")
        #expect(records[0].capturedAt == august6)
        #expect(records[0].thought == nil)
        #expect(TimelineContentFilter.photos.matches(records[0]))
        #expect(!TimelineContentFilter.text.matches(records[0]))
    }

    @Test func sameEntryNoteAndThoughtShowAssociationMarkersAndSortByEntryStart() {
        let entryStart = date(2026, 7, 20, 8, 0)
        let entryEnd = date(2026, 7, 20, 10, 0)
        let entry = timeEntry(startAt: entryStart, endAt: entryEnd, note: "项目备注正文")
        let thought = ThoughtNote(
            body: "同条目思考",
            capturedAt: date(2026, 8, 6, 12, 0),
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        let notePhoto = mediaMoment(
            kind: .photo,
            capturedAt: date(2026, 8, 6, 12, 5),
            linkedEntryId: entry.id,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [notePhoto],
            mediaLinks: [],
            entries: [entry]
        )

        #expect(records.count == 2)
        let noteRecord = records.first { $0.kind == .note }
        let thoughtRecord = records.first { $0.kind == .thought }
        #expect(noteRecord != nil)
        #expect(thoughtRecord != nil)
        #expect(noteRecord?.relatedThoughtCount == 1)
        #expect(thoughtRecord?.isRelatedToNote == true)
        #expect(noteRecord?.noteText == "项目备注正文")
        #expect(noteRecord?.mediaMoments.map(\.id) == [notePhoto.id])
        #expect(noteRecord?.capturedAt == entryStart)
        #expect(thoughtRecord?.capturedAt == entryStart)
        #expect(records.allSatisfy { $0.linkedEntry?.id == entry.id })
    }

    @Test func movingDraftEntryTimeMovesManualProjectionAutomatically() {
        let originalStart = date(2026, 7, 20, 9, 0)
        let originalEnd = date(2026, 7, 20, 10, 0)
        let movedStart = date(2026, 7, 21, 14, 0)
        let movedEnd = date(2026, 7, 21, 15, 0)
        let entry = timeEntry(startAt: originalStart, endAt: originalEnd, note: "可移动草稿")
        let thought = ThoughtNote(
            body: "跟着条目走",
            capturedAt: date(2026, 8, 6, 9, 0),
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        let notePhoto = mediaMoment(
            kind: .photo,
            capturedAt: date(2026, 8, 6, 9, 30),
            linkedEntryId: entry.id,
            linkSource: .manual
        )

        let before = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [notePhoto],
            mediaLinks: [],
            entries: [entry]
        )
        #expect(before.map(\.capturedAt).allSatisfy { $0 == originalStart })

        entry.startAt = movedStart
        entry.endAt = movedEnd

        let after = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [notePhoto],
            mediaLinks: [],
            entries: [entry]
        )
        #expect(after.count == 2)
        #expect(after.map(\.capturedAt).allSatisfy { $0 == movedStart })
        #expect(after.map(\.displayEndAt).allSatisfy { $0 == movedEnd })
        #expect(thought.capturedAt == date(2026, 8, 6, 9, 0))
        #expect(notePhoto.capturedAt == date(2026, 8, 6, 9, 30))
    }

    @Test func orphanManualLinkFallsBackToOwnTime() {
        let missingEntryID = UUID()
        let ownTime = date(2026, 8, 6, 11, 0)
        let thought = ThoughtNote(
            body: "孤儿思考",
            capturedAt: ownTime,
            linkedEntryId: missingEntryID,
            linkSource: .manual
        )
        let photo = mediaMoment(
            kind: .photo,
            capturedAt: ownTime.addingTimeInterval(60),
            linkedEntryId: missingEntryID,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [photo],
            mediaLinks: [],
            entries: []
        )

        let thoughtRecord = records.first { $0.thought?.id == thought.id }
        let mediaRecord = records.first { $0.id == "media-\(photo.id.uuidString)" }
        #expect(thoughtRecord?.capturedAt == ownTime)
        #expect(thoughtRecord?.displayEndAt == nil)
        #expect(mediaRecord?.capturedAt == photo.capturedAt)
        #expect(mediaRecord?.kind == .thought)
    }

    @Test func autoLinkedThoughtKeepsOwnTimeEvenWhenEntryExists() {
        let entryStart = date(2026, 7, 20, 9, 0)
        let entryEnd = date(2026, 7, 20, 11, 0)
        let capture = date(2026, 7, 20, 9, 30)
        let entry = timeEntry(startAt: entryStart, endAt: entryEnd, note: "")
        let thought = ThoughtNote(
            body: "自动关联仍用自身时间",
            capturedAt: capture,
            anchorAt: capture,
            linkedEntryId: entry.id,
            linkSource: .auto
        )

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [],
            mediaLinks: [],
            entries: [entry]
        )

        #expect(records.count == 1)
        #expect(records[0].kind == .thought)
        #expect(records[0].capturedAt == capture)
        #expect(records[0].displayEndAt == nil)
        #expect(records[0].linkedEntry?.id == entry.id)
    }

    @Test func noteOnlyAttachmentsAppearWithoutNoteText() {
        let entry = timeEntry(
            startAt: date(2026, 7, 20, 13, 0),
            endAt: date(2026, 7, 20, 14, 0),
            note: "   "
        )
        let photo = mediaMoment(
            kind: .photo,
            capturedAt: date(2026, 8, 6, 10, 0),
            linkedEntryId: entry.id,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [],
            mediaMoments: [photo],
            mediaLinks: [],
            entries: [entry]
        )

        #expect(records.count == 1)
        #expect(records[0].kind == .note)
        #expect(!records[0].hasText)
        #expect(records[0].hasPhoto)
        #expect(TimelineContentFilter.photos.matches(records[0]))
    }

    @Test func typeModeFiltersNotesAndThoughts() {
        let entry = timeEntry(
            startAt: date(2026, 7, 20, 8, 0),
            endAt: date(2026, 7, 20, 9, 0),
            note: "备注"
        )
        let thought = ThoughtNote(
            body: "思考",
            capturedAt: date(2026, 8, 6, 8, 0),
            linkedEntryId: entry.id,
            linkSource: .manual
        )

        let records = TimelineProjection.records(
            thoughts: [thought],
            mediaMoments: [],
            mediaLinks: [],
            entries: [entry]
        )

        #expect(records.filter { TimelineTypeMode.notes.matches($0) }.map(\.kind) == [.note])
        #expect(records.filter { TimelineTypeMode.thoughts.matches($0) }.map(\.kind) == [.thought])
        #expect(records.filter { TimelineTypeMode.merged.matches($0) }.count == 2)
    }

    private func timeEntry(startAt: Date, endAt: Date, note: String) -> TimeEntry {
        TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "语义项目",
            categoryNameSnapshot: "测试",
            startAt: startAt,
            endAt: endAt,
            note: note,
            status: .draft
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
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
