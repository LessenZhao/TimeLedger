import Foundation
import Testing
@testable import TimeLedger

@MainActor
struct TimelineProjectionTests {
    @Test func textPhotoAndVideoFormOneRecordThatMatchesAllRelevantFilters() {
        var fixture = Fixture()
        let journal = fixture.addJournal(body: "记录当下的想法")
        let photo = fixture.addMedia(kind: .photo, ownerID: journal.id, ownerKind: .journalEntry, sortOrder: 1)
        let video = fixture.addMedia(kind: .video, ownerID: journal.id, ownerKind: .journalEntry, sortOrder: 0)

        let records = fixture.records()
        #expect(records.count == 1)
        #expect(records[0].id == "journal-\(journal.id.uuidString)")
        #expect(records[0].mediaMoments.map(\.id) == [video.id, photo.id])
        #expect(TimelineContentFilter.text.matches(records[0]))
        #expect(TimelineContentFilter.photos.matches(records[0]))
        #expect(TimelineContentFilter.videos.matches(records[0]))
    }

    @Test func standalonePhotoAndVideoRemainSeparateMediaOnlyJournals() {
        var fixture = Fixture()
        let first = fixture.addJournal(body: "")
        let second = fixture.addJournal(body: "", capturedAt: fixture.now.addingTimeInterval(10))
        _ = fixture.addMedia(kind: .photo, ownerID: first.id, ownerKind: .journalEntry)
        _ = fixture.addMedia(kind: .video, ownerID: second.id, ownerKind: .journalEntry)

        let records = fixture.records()
        #expect(records.count == 2)
        #expect(records.allSatisfy { !$0.hasText })
        #expect(records.contains(where: { $0.hasPhoto && !$0.hasVideo }))
        #expect(records.contains(where: { $0.hasVideo && !$0.hasPhoto }))
    }

    @Test func emptyJournalWithManualPhotoRetainsIdentityAndOwnsMedia() {
        var fixture = Fixture()
        let entry = fixture.addEntry()
        let journal = fixture.addJournal(body: " \n ", linkedEntry: entry, source: .manual)
        let photo = fixture.addMedia(kind: .photo, ownerID: journal.id, ownerKind: .journalEntry)

        let record = fixture.records().first
        #expect(record?.journal?.id == journal.id)
        #expect(record?.mediaMoments.map(\.id) == [photo.id])
        #expect(record?.hasText == false)
        #expect(record?.linkedEntry?.id == entry.id)
    }

    @Test func emptyJournalWithAutoVideoRetainsIdentityAndOwnsMedia() {
        var fixture = Fixture()
        let entry = fixture.addEntry()
        let journal = fixture.addJournal(body: "", linkedEntry: entry, source: .auto)
        let video = fixture.addMedia(kind: .video, ownerID: journal.id, ownerKind: .journalEntry)

        let record = fixture.records().first
        #expect(record?.journal?.id == journal.id)
        #expect(record?.mediaMoments.map(\.id) == [video.id])
        #expect(record?.capturedAt == journal.anchorAt)
        #expect(record?.hasVideo == true)
    }

    @Test func entryPhotoCapturedInAugustProjectsOntoJulyEntryDay() {
        var fixture = Fixture()
        let start = fixture.date(2026, 7, 20, 10, 0)
        let end = fixture.date(2026, 7, 20, 12, 0)
        let entry = fixture.addEntry(startAt: start, endAt: end, body: "")
        let photo = fixture.addMedia(kind: .photo, ownerID: entry.id, ownerKind: .timeEntry, capturedAt: fixture.date(2026, 8, 6, 15, 30))

        let record = fixture.records().first
        #expect(record?.kind == .note)
        #expect(record?.capturedAt == start)
        #expect(record?.displayEndAt == end)
        #expect(record?.mediaMoments.map(\.id) == [photo.id])
    }

    @Test func manualJournalInsideEntryUsesEntryTimeRange() {
        var fixture = Fixture()
        let start = fixture.date(2026, 7, 20, 9, 0)
        let end = fixture.date(2026, 7, 20, 11, 0)
        let entry = fixture.addEntry(startAt: start, endAt: end)
        _ = fixture.addJournal(body: "条目内事后随记", capturedAt: fixture.date(2026, 8, 6, 18, 0), linkedEntry: entry, source: .manual)

        let record = fixture.records().first { $0.kind == .thought }
        #expect(record?.capturedAt == start)
        #expect(record?.displayEndAt == end)
        #expect(record?.linkedEntry?.id == entry.id)
    }

    @Test func standaloneHomeJournalKeepsOwnCaptureTime() {
        var fixture = Fixture()
        let captured = fixture.date(2026, 8, 6, 14, 0)
        _ = fixture.addJournal(body: "首页独立随记", capturedAt: captured)

        let record = fixture.records().first
        #expect(record?.kind == .thought)
        #expect(record?.capturedAt == captured)
        #expect(record?.displayEndAt == nil)
        #expect(record?.linkedEntry == nil)
    }

    @Test func standaloneHomeMediaJournalProjectsAtOwnTime() {
        var fixture = Fixture()
        let captured = fixture.date(2026, 8, 6, 16, 0)
        let journal = fixture.addJournal(body: "", capturedAt: captured)
        _ = fixture.addMedia(kind: .photo, ownerID: journal.id, ownerKind: .journalEntry, capturedAt: captured)

        let record = fixture.records().first
        #expect(record?.kind == .thought)
        #expect(record?.capturedAt == captured)
        #expect(record?.journal?.id == journal.id)
        #expect(record?.hasPhoto == true)
        #expect(record?.hasText == false)
    }

    @Test func sameEntryContentAndJournalShowAssociationMarkersAndSortByEntryStart() {
        var fixture = Fixture()
        let start = fixture.date(2026, 7, 20, 8, 0)
        let entry = fixture.addEntry(startAt: start, endAt: fixture.date(2026, 7, 20, 10, 0), body: "项目记录正文")
        _ = fixture.addJournal(body: "同条目随记", linkedEntry: entry, source: .manual)
        _ = fixture.addMedia(kind: .photo, ownerID: entry.id, ownerKind: .timeEntry)

        let records = fixture.records()
        let entryRecord = records.first { $0.kind == .note }
        let journalRecord = records.first { $0.kind == .thought }
        #expect(records.count == 2)
        #expect(entryRecord?.relatedThoughtCount == 1)
        #expect(journalRecord?.isRelatedToNote == true)
        #expect(entryRecord?.noteText == "项目记录正文")
        #expect(records.allSatisfy { $0.capturedAt == start })
    }

    @Test func movingDraftEntryTimeMovesManualProjectionAutomatically() {
        var fixture = Fixture()
        let original = fixture.date(2026, 7, 20, 9, 0)
        let moved = fixture.date(2026, 7, 21, 14, 0)
        let movedEnd = fixture.date(2026, 7, 21, 15, 0)
        let entry = fixture.addEntry(startAt: original, endAt: original.addingTimeInterval(3_600), body: "可移动")
        _ = fixture.addJournal(body: "跟着走", linkedEntry: entry, source: .manual)

        #expect(fixture.records().allSatisfy { $0.capturedAt == original })
        entry.startAt = moved
        entry.endAt = movedEnd
        let after = fixture.records()
        #expect(after.allSatisfy { $0.capturedAt == moved })
        #expect(after.allSatisfy { $0.displayEndAt == movedEnd })
    }

    @Test func orphanManualJournalLinkFallsBackToOwnTime() {
        var fixture = Fixture()
        let captured = fixture.date(2026, 8, 6, 11, 0)
        let journal = fixture.addJournal(body: "孤儿随记", capturedAt: captured)
        fixture.journalLinks.append(JournalTimeLink(journalEntryID: journal.id, timeEntryID: UUID(), linkSource: .manual))

        let record = fixture.records().first
        #expect(record?.capturedAt == captured)
        #expect(record?.displayEndAt == nil)
        #expect(record?.linkedEntry == nil)
    }

    @Test func autoLinkedJournalKeepsOwnTimeEvenWhenEntryExists() {
        var fixture = Fixture()
        let start = fixture.date(2026, 7, 20, 9, 0)
        let capture = fixture.date(2026, 7, 20, 9, 30)
        let entry = fixture.addEntry(startAt: start, endAt: start.addingTimeInterval(7_200), body: "")
        _ = fixture.addJournal(body: "自动关联", capturedAt: capture, linkedEntry: entry, source: .auto)

        let record = fixture.records().first
        #expect(record?.kind == .thought)
        #expect(record?.capturedAt == capture)
        #expect(record?.displayEndAt == nil)
        #expect(record?.linkedEntry?.id == entry.id)
    }

    @Test func entryOnlyAttachmentsAppearWithoutText() {
        var fixture = Fixture()
        let entry = fixture.addEntry(body: "   ")
        _ = fixture.addMedia(kind: .photo, ownerID: entry.id, ownerKind: .timeEntry)

        let record = fixture.records().first
        #expect(record?.kind == .note)
        #expect(record?.hasText == false)
        #expect(record?.hasPhoto == true)
    }

    @Test func typeModeFiltersTimeEntriesAndJournals() {
        var fixture = Fixture()
        let entry = fixture.addEntry(body: "记录")
        _ = fixture.addJournal(body: "随记", linkedEntry: entry, source: .manual)
        let records = fixture.records()

        #expect(records.filter { TimelineTypeMode.notes.matches($0) }.map(\.kind) == [.note])
        #expect(records.filter { TimelineTypeMode.thoughts.matches($0) }.map(\.kind) == [.thought])
        #expect(records.filter { TimelineTypeMode.merged.matches($0) }.count == 2)
    }

    @Test func favoriteFilterMatchesFavoritedJournal() {
        var fixture = Fixture()
        let journal = fixture.addJournal(body: "收藏随记")
        journal.isFavorite = true

        let record = fixture.records().first
        #expect(record?.kind == .thought)
        #expect(TimelineContentFilter.favorite.matches(record!))
    }

    @Test func favoriteFilterDoesNotMatchUnfavoritedJournal() {
        var fixture = Fixture()
        _ = fixture.addJournal(body: "普通随记")

        let record = fixture.records().first
        #expect(record?.kind == .thought)
        #expect(!TimelineContentFilter.favorite.matches(record!))
    }

    @Test func favoriteFilterDoesNotMatchNoteRecord() {
        var fixture = Fixture()
        _ = fixture.addEntry(body: "时间记录")

        let record = fixture.records().first
        #expect(record?.kind == .note)
        #expect(!TimelineContentFilter.favorite.matches(record!))
    }
}

@MainActor
private struct Fixture {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var journals: [JournalEntry] = []
    var documents: [ContentDocument] = []
    var attachments: [ContentAttachment] = []
    var journalLinks: [JournalTimeLink] = []
    var media: [MediaMoment] = []
    var entries: [TimeEntry] = []

    mutating func addEntry(
        startAt: Date? = nil,
        endAt: Date? = nil,
        body: String = ""
    ) -> TimeEntry {
        let start = startAt ?? now.addingTimeInterval(-3_600)
        let entry = TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "语义项目",
            categoryNameSnapshot: "测试",
            startAt: start,
            endAt: endAt ?? start.addingTimeInterval(3_600)
        )
        entries.append(entry)
        documents.append(ContentDocument(id: entry.id, ownerID: entry.id, ownerKind: .timeEntry, body: body))
        return entry
    }

    mutating func addJournal(
        body: String,
        capturedAt: Date? = nil,
        linkedEntry: TimeEntry? = nil,
        source: ThoughtLinkSource = .none
    ) -> JournalEntry {
        let captured = capturedAt ?? now
        let journal = JournalEntry(capturedAt: captured, anchorAt: captured)
        journals.append(journal)
        documents.append(ContentDocument(id: journal.id, ownerID: journal.id, ownerKind: .journalEntry, body: body))
        if let linkedEntry {
            journalLinks.append(JournalTimeLink(
                id: journal.id,
                journalEntryID: journal.id,
                timeEntryID: linkedEntry.id,
                linkSource: source
            ))
        }
        return journal
    }

    mutating func addMedia(
        kind: MediaKind,
        ownerID: UUID,
        ownerKind: ContentOwnerKind,
        sortOrder: Int = 0,
        capturedAt: Date? = nil
    ) -> MediaMoment {
        let moment = MediaMoment(
            kind: kind,
            capturedAt: capturedAt ?? now,
            requestedStorage: .app,
            thumbnailData: Data([1])
        )
        media.append(moment)
        let document = documents.first {
            $0.ownerID == ownerID && $0.ownerKindEnum == ownerKind
        }!
        attachments.append(ContentAttachment(
            id: moment.id,
            contentDocumentID: document.id,
            mediaMomentID: moment.id,
            sortOrder: sortOrder,
            state: .ready
        ))
        return moment
    }

    func records() -> [TimelineRecord] {
        TimelineProjection.records(
            journals: journals,
            documents: documents,
            contentAttachments: attachments,
            journalLinks: journalLinks,
            mediaMoments: media,
            entries: entries
        )
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
