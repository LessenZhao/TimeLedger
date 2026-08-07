import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct ContentEditorTests {
    @Test func newTimeEntryCanSaveWithoutOptionalContent() {
        let newTimeEntrySession = ContentEditorSession(
            ownerID: UUID(),
            contentID: UUID(),
            baseRevision: 0,
            workingBody: "",
            workingAttachments: [],
            allowsEmptyContent: true
        )
        let standardContentSession = ContentEditorSession(
            ownerID: UUID(),
            contentID: UUID(),
            baseRevision: 0,
            workingBody: "",
            workingAttachments: []
        )

        #expect(newTimeEntrySession.hasContent)
        #expect(!standardContentSession.hasContent)
    }

    @Test func textThenPhotoAndVideoAreSavedWithoutReplacingBody() throws {
        let fixture = try ContentEditorFixture(body: "旧正文")
        let photo = fixture.insertMedia(kind: .photo)
        let video = fixture.insertMedia(kind: .video)
        let session = try fixture.session()

        session.updateBody("新正文")
        session.apply(.addMedia(photo.id))
        session.apply(.addMedia(video.id))
        try fixture.save(session)

        #expect(fixture.document.body == "新正文")
        #expect(Set(try fixture.attachments().map(\.mediaMomentID)) == Set([photo.id, video.id]))
    }

    @Test func mediaThenTextPreservesAllAttachmentDeltas() throws {
        let fixture = try ContentEditorFixture()
        let photo = fixture.insertMedia(kind: .photo)
        let session = try fixture.session()

        session.apply(.addMedia(photo.id))
        session.updateBody("媒体之后补文字")
        try fixture.save(session)

        #expect(fixture.document.body == "媒体之后补文字")
        #expect(try fixture.attachments().map(\.mediaMomentID) == [photo.id])
    }

    @Test func recoveredDraftAfterInterruptionKeepsBodyAndAttachmentIDs() throws {
        let fixture = try ContentEditorFixture()
        let photo = fixture.insertMedia(kind: .photo)
        let session = try fixture.session()
        session.updateBody("杀进程前")
        session.apply(.addMedia(photo.id))
        try fixture.draftStore.save(session)

        let recovered = try #require(try fixture.draftStore.load(ownerID: fixture.ownerID))
        #expect(recovered.workingBody == "杀进程前")
        #expect(recovered.workingAttachments.map(\.mediaMomentID) == [photo.id])
    }

    @Test func staleRevisionIsRejectedAndWorkingCopyIsPreserved() throws {
        let fixture = try ContentEditorFixture(body: "版本一")
        let stale = try fixture.session()
        stale.updateBody("我的未保存修改")
        fixture.document.body = "另一窗口已保存"
        fixture.document.revision += 1
        try fixture.context.save()

        #expect(throws: SaveContentError.revisionConflict) {
            try fixture.save(stale)
        }
        #expect(stale.workingBody == "我的未保存修改")
        #expect(fixture.document.body == "另一窗口已保存")
    }

    @Test func staleMediaDraftCannotOverwriteNewerCanonicalBody() async throws {
        let fixture = try ContentEditorFixture(body: "数据库新正文")
        let mediaDraftStore = ThoughtComposerDraftStore(
            rootURL: fixture.draftStore.rootURL.appending(path: "media-draft", directoryHint: .isDirectory)
        )
        _ = try await mediaDraftStore.addPhotoData(
            Data([1]),
            thumbnailData: Data(),
            fileExtension: "jpg"
        )
        _ = try mediaDraftStore.updateBody("旧草稿正文")

        let prepared = try mediaDraftStore.prepareExisting(
            ownerID: fixture.ownerID,
            contentID: fixture.document.id,
            baseRevision: fixture.document.revision,
            canonicalBody: fixture.document.body
        )

        #expect(prepared.body == "数据库新正文")
        #expect(prepared.attachments.count == 1)
    }

    @Test func failedAttachmentRetryIsIdempotent() throws {
        let fixture = try ContentEditorFixture()
        let photo = fixture.insertMedia(kind: .photo)
        let failed = ContentAttachment(
            contentDocumentID: fixture.document.id,
            mediaMomentID: photo.id,
            state: .failed
        )
        fixture.context.insert(failed)
        try fixture.context.save()
        let session = try fixture.session()

        try fixture.save(session)
        try fixture.save(try fixture.session())

        let attachments = try fixture.attachments()
        #expect(attachments.count == 1)
        #expect(attachments[0].stateEnum == .ready)
    }

    @Test func removingAttachmentNeverDeletesOriginalMediaMoment() throws {
        let fixture = try ContentEditorFixture()
        let photo = fixture.insertMedia(kind: .photo)
        fixture.context.insert(ContentAttachment(
            contentDocumentID: fixture.document.id,
            mediaMomentID: photo.id,
            state: .ready
        ))
        try fixture.context.save()
        let session = try fixture.session()
        session.apply(.removeMedia(photo.id))

        try fixture.save(session)

        #expect(try fixture.attachments().isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<MediaMoment>()) == 1)
    }

    @Test func cancelPerformsZeroDatabaseWrites() throws {
        let fixture = try ContentEditorFixture(body: "正式内容")
        let session = try fixture.session()
        session.updateBody("取消的内容")

        try fixture.draftStore.discard(ownerID: fixture.ownerID)

        #expect(fixture.document.body == "正式内容")
        #expect(fixture.document.revision == 1)
    }

    @Test func twoEntriesInSameProjectNeverShareDrafts() throws {
        let draftsRoot = FileManager.default.temporaryDirectory
            .appending(path: "ComposerDraftFactoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: draftsRoot) }
        let firstID = UUID()
        let secondID = UUID()
        let firstStore = ComposerDraftStoreFactory.timeEntry(
            firstID,
            draftsRootURL: draftsRoot
        )
        let secondStore = ComposerDraftStoreFactory.timeEntry(
            secondID,
            draftsRootURL: draftsRoot
        )

        _ = try firstStore.updateBody("第一条")
        _ = try secondStore.updateBody("第二条")

        #expect(firstStore.rootURL != secondStore.rootURL)
        #expect(try firstStore.load().body == "第一条")
        #expect(try secondStore.load().body == "第二条")
    }

    @Test func newEntryEditorFillsDocumentCreatedByTimeCursorWithoutSecondDocument() throws {
        let fixture = try ContentEditorFixture()
        let entry = TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "新记录",
            categoryNameSnapshot: "测试",
            startAt: Date().addingTimeInterval(-600),
            endAt: Date()
        )
        let cursorDocument = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry)
        fixture.context.insert(entry)
        fixture.context.insert(cursorDocument)
        try fixture.context.save()
        let session = ContentEditorSession(
            ownerID: UUID(),
            contentID: UUID(),
            baseRevision: 0,
            workingBody: "新建正文",
            workingAttachments: []
        )

        try SaveContent(modelContext: fixture.context).createTimeEntryDocumentAndSave(session, entry: entry)

        let documents = try fixture.context.fetch(FetchDescriptor<ContentDocument>())
            .filter { $0.ownerID == entry.id }
        #expect(documents.count == 1)
        #expect(documents[0].body == "新建正文")
    }

    @Test func automaticReconciliationNeverAbsorbsMediaOnlyJournal() throws {
        let fixture = try ContentEditorFixture()
        let now = Date()
        let entry = TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "时间记录",
            categoryNameSnapshot: "测试",
            startAt: now.addingTimeInterval(-1_800),
            endAt: now
        )
        let journal = JournalEntry(capturedAt: now.addingTimeInterval(-600), anchorAt: now.addingTimeInterval(-600))
        let document = ContentDocument(ownerID: journal.id, ownerKind: .journalEntry)
        let media = fixture.insertMedia(kind: .photo)
        fixture.context.insert(entry)
        fixture.context.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry))
        fixture.context.insert(journal)
        fixture.context.insert(document)
        fixture.context.insert(ContentAttachment(contentDocumentID: document.id, mediaMomentID: media.id))
        try fixture.context.save()

        #expect(try JournalContentService(modelContext: fixture.context).reconcileAutoLinks() == 0)
        #expect(try fixture.context.fetch(FetchDescriptor<JournalTimeLink>()).isEmpty)
    }
}

@MainActor
private final class ContentEditorFixture {
    let ownerID = UUID()
    let context: ModelContext
    let document: ContentDocument
    let draftStore: ContentEditorDraftStore

    init(body: String = "") throws {
        let schema = Schema(TimeLedgerModels.all)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        document = ContentDocument(
            ownerID: ownerID,
            ownerKind: .timeEntry,
            body: body
        )
        context.insert(document)
        try context.save()
        draftStore = ContentEditorDraftStore(
            rootURL: FileManager.default.temporaryDirectory
                .appending(path: "ContentEditorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
    }

    func insertMedia(kind: MediaKind) -> MediaMoment {
        let media = MediaMoment(
            kind: kind,
            requestedStorage: .app,
            storedLocation: .app,
            appRelativePath: "Media/\(UUID().uuidString)",
            thumbnailData: Data(),
            status: .saved
        )
        context.insert(media)
        try? context.save()
        return media
    }

    func session() throws -> ContentEditorSession {
        try ContentEditorSession.load(document: document, modelContext: context)
    }

    func save(_ session: ContentEditorSession) throws {
        try SaveContent(modelContext: context).save(session)
    }

    func attachments() throws -> [ContentAttachment] {
        try context.fetch(FetchDescriptor<ContentAttachment>())
            .filter { $0.contentDocumentID == document.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
