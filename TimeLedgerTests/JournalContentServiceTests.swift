import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct JournalContentServiceTests {
    @Test func setFavoriteToTrueThenQueryReturnsTrue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let journal = JournalEntry()
        context.insert(journal)
        try context.save()

        try JournalContentService(modelContext: context).setFavorite(journal, true)

        let refetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(refetched.count == 1)
        #expect(refetched.first?.isFavorite == true)
    }

    @Test func setFavoriteToFalseThenQueryReturnsFalse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let journal = JournalEntry()
        journal.isFavorite = true
        context.insert(journal)
        try context.save()

        try JournalContentService(modelContext: context).setFavorite(journal, false)

        let refetched = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(refetched.count == 1)
        #expect(refetched.first?.isFavorite == false)
    }

    private func makeContainer() throws -> ModelContainer {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "JournalContentService-\(UUID().uuidString)", directoryHint: .isDirectory)
        let storeURL = rootURL.appending(path: "TimeLedger.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
    }
}