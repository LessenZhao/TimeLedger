import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct ThoughtMediaLinkTests {
    @Test func linkGroupsMediaAndSynchronizesTimeEntryAssociation() throws {
        let context = try makeContext()
        let entry = TimeEntry(
            projectId: UUID(),
            projectNameSnapshot: "项目",
            categoryNameSnapshot: "工作",
            startAt: Date(timeIntervalSince1970: 1_799_999_000),
            endAt: Date(timeIntervalSince1970: 1_800_001_000)
        )
        let thought = ThoughtNote(
            body: "带照片",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            linkedEntryId: entry.id,
            linkSource: .manual
        )
        let moment = MediaMoment(
            kind: .photo,
            capturedAt: thought.capturedAt,
            requestedStorage: .app,
            thumbnailData: Data([1])
        )
        context.insert(entry)
        context.insert(thought)
        context.insert(moment)
        try context.save()

        let service = ThoughtMediaLinkService(modelContext: context)
        _ = try service.link(moment, to: thought, sortOrder: 0)

        #expect(try service.mediaMoments(for: thought).map(\.id) == [moment.id])
        #expect(moment.anchorAt == thought.anchorAt)
        #expect(moment.linkedEntryId == entry.id)
        #expect(moment.linkSourceEnum == .manual)
    }

    @Test func additiveLinkSchemaKeepsExistingMediaStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ThoughtMediaLinkMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "TimeLedger.store")
        let previousModels: [any PersistentModel.Type] = [
            Project.self,
            TimeCursor.self,
            TimeEntry.self,
            AppSettings.self,
            ThoughtNote.self,
            ActionItem.self,
            ActionCompletion.self,
            MediaMoment.self,
        ]
        let previousSchema = Schema(previousModels)
        var previousContainer: ModelContainer? = try ModelContainer(
            for: previousSchema,
            configurations: [
                ModelConfiguration("ThoughtMediaLinkMigration", schema: previousSchema, url: storeURL)
            ]
        )
        let previousContext = ModelContext(previousContainer!)
        previousContext.insert(ThoughtNote(body: "已有思考"))
        previousContext.insert(MediaMoment(
            kind: .photo,
            requestedStorage: .app,
            thumbnailData: Data([1])
        ))
        try previousContext.save()
        previousContainer = nil

        let currentSchema = Schema(TimeLedgerModels.all)
        let currentContainer = try ModelContainer(
            for: currentSchema,
            configurations: [
                ModelConfiguration("ThoughtMediaLinkMigration", schema: currentSchema, url: storeURL)
            ]
        )
        let currentContext = ModelContext(currentContainer)

        #expect(try currentContext.fetch(FetchDescriptor<ThoughtNote>()).count == 1)
        #expect(try currentContext.fetch(FetchDescriptor<MediaMoment>()).count == 1)
        #expect(try currentContext.fetch(FetchDescriptor<ThoughtMediaLink>()).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(TimeLedgerModels.all)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(
            try ModelContainer(for: schema, configurations: [configuration])
        )
    }
}
