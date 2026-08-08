import Foundation
import SwiftData
import Testing
@testable import TimeLedger

@MainActor
struct JournalFavoriteMigrationTests {
    @Test func v2JournalSurvivesReopenWithFavoriteDefaultFalse() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "JournalFavoriteMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        let storeURL = rootURL.appending(path: "TimeLedger.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let journalID = UUID()
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)

        do {
            let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
            )
            let context = ModelContext(container)
            context.insert(JournalEntry(id: journalID, capturedAt: anchor))
            try context.save()
        }

        let schema = Schema(versionedSchema: TimeLedgerSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeLedgerMigrationPlan.self,
            configurations: [ModelConfiguration("TimeLedger", schema: schema, url: storeURL)]
        )
        let context = ModelContext(container)
        let journals = try context.fetch(FetchDescriptor<JournalEntry>())

        #expect(journals.count == 1)
        #expect(journals.first?.id == journalID)
        #expect(journals.first?.isFavorite == false)
    }
}