import Foundation
import SwiftData
import Testing
@testable import TimeLedger

struct SyncEnvelopeExportTests {
    @Test func exportSyncBatchContainsTimeEntryEnvelope() throws {
        let schema = Schema(TimeLedgerModels.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let project = Project(name: "TimeLedger", categoryName: "开发")
        context.insert(project)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_784_000_000),
            endAt: Date(timeIntervalSince1970: 1_784_003_600),
            status: .confirmed
        )
        context.insert(entry)
        context.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "sync"))
        try context.save()

        let json = try SyncEnvelopeExportService(modelContext: context, deviceId: "test-device").exportSyncBatchJSON()
        #expect(json.contains("\"protocolVersion\" : \"1.0\"" ) || json.contains("\"protocolVersion\": \"1.0\""))
        #expect(json.contains("timeEntry"))
        #expect(json.contains("test-device"))
        #expect(json.contains("payloadJSON"))
    }

    @Test func scopedSyncBatchExcludesDraftAndOutOfRangeEntries() throws {
        let schema = Schema(TimeLedgerModels.all)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let project = Project(name: "TimeLedger", categoryName: "开发")
        context.insert(project)
        let inRange = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_100),
            endAt: Date(timeIntervalSince1970: 1_200),
            status: .confirmed
        )
        let draft = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_300),
            endAt: Date(timeIntervalSince1970: 1_400),
            status: .draft
        )
        let outOfRange = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 2_100),
            endAt: Date(timeIntervalSince1970: 2_200),
            status: .confirmed
        )
        for entry in [inRange, draft, outOfRange] {
            context.insert(entry)
            context.insert(ContentDocument(ownerID: entry.id, ownerKind: .timeEntry))
        }
        try context.save()

        let prepared = try SyncEnvelopeExportService(
            modelContext: context,
            deviceId: "test-device"
        ).prepareSyncBatchJSON(
            range: ExportDateRange(
                start: Date(timeIntervalSince1970: 1_000),
                endExclusive: Date(timeIntervalSince1970: 2_000)
            ),
            onlyConfirmed: true
        )

        let data = try #require(prepared.json.data(using: .utf8))
        let batch = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let envelopes = try #require(batch["envelopes"] as? [[String: Any]])
        let entryEnvelopes = envelopes.filter { $0["entityType"] as? String == "timeEntry" }

        #expect(prepared.entryCount == 1)
        #expect(entryEnvelopes.count == 1)
        #expect(envelopes.contains { $0["entityType"] as? String == "timeCursor" } == false)
    }

    @Test func v1RoundTripProjectsUnifiedContentWithoutAddingEntityTypes() throws {
        let sourceSchema = Schema(TimeLedgerModels.all)
        let source = ModelContext(try ModelContainer(
            for: sourceSchema,
            configurations: [ModelConfiguration(schema: sourceSchema, isStoredInMemoryOnly: true)]
        ))
        let project = Project(name: "往返项目", categoryName: "测试")
        let start = Date(timeIntervalSince1970: 1_800_100_000)
        let entry = TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: start,
            endAt: start.addingTimeInterval(1_800),
            status: .confirmed
        )
        let entryDocument = ContentDocument(ownerID: entry.id, ownerKind: .timeEntry, body: "记录正文")
        let journal = JournalEntry(capturedAt: start.addingTimeInterval(600), anchorAt: start.addingTimeInterval(600))
        let journalDocument = ContentDocument(ownerID: journal.id, ownerKind: .journalEntry, body: "关联随记")
        let link = JournalTimeLink(journalEntryID: journal.id, timeEntryID: entry.id, linkSource: .manual)
        for model in [project] { source.insert(model) }
        source.insert(entry); source.insert(entryDocument); source.insert(journal); source.insert(journalDocument); source.insert(link)
        try source.save()

        let json = try SyncEnvelopeExportService(modelContext: source, deviceId: "roundtrip").exportSyncBatchJSON()
        let root = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let envelopes = try #require(root["envelopes"] as? [[String: Any]])
        let entityTypes = Set(envelopes.compactMap { $0["entityType"] as? String })
        #expect(entityTypes.isSubset(of: ["project", "timeCursor", "timeEntry", "thoughtNote"]))

        let destinationSchema = Schema(TimeLedgerModels.all)
        let destination = ModelContext(try ModelContainer(
            for: destinationSchema,
            configurations: [ModelConfiguration(schema: destinationSchema, isStoredInMemoryOnly: true)]
        ))
        #expect(try MirrorSyncImportService(modelContext: destination).importMacBatchJSON(json) >= 3)
        let documents = try destination.fetch(FetchDescriptor<ContentDocument>())
        #expect(documents.first { $0.ownerID == entry.id }?.body == "记录正文")
        #expect(documents.first { $0.ownerID == journal.id }?.body == "关联随记")
        let importedLink = try destination.fetch(FetchDescriptor<JournalTimeLink>()).first
        #expect(importedLink?.timeEntryID == entry.id)
        #expect(importedLink?.linkSource == ThoughtLinkSource.manual.rawValue)
    }
}
