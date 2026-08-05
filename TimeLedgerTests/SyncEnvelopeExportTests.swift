import Foundation
import SwiftData
import Testing
@testable import TimeLedger

struct SyncEnvelopeExportTests {
    @Test func exportSyncBatchContainsTimeEntryEnvelope() throws {
        let schema = Schema([Project.self, TimeEntry.self, ThoughtNote.self, TimeCursor.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
            note: "sync",
            status: .confirmed
        )
        context.insert(entry)
        try context.save()

        let json = try SyncEnvelopeExportService(modelContext: context, deviceId: "test-device").exportSyncBatchJSON()
        #expect(json.contains("\"protocolVersion\" : \"1.0\"" ) || json.contains("\"protocolVersion\": \"1.0\""))
        #expect(json.contains("timeEntry"))
        #expect(json.contains("test-device"))
        #expect(json.contains("payloadJSON"))
    }

    @Test func scopedSyncBatchExcludesDraftAndOutOfRangeEntries() throws {
        let schema = Schema([Project.self, TimeEntry.self, ThoughtNote.self, TimeCursor.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let project = Project(name: "TimeLedger", categoryName: "开发")
        context.insert(project)
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_100),
            endAt: Date(timeIntervalSince1970: 1_200),
            status: .confirmed
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 1_300),
            endAt: Date(timeIntervalSince1970: 1_400),
            status: .draft
        ))
        context.insert(TimeEntry(
            projectId: project.id,
            projectNameSnapshot: project.name,
            categoryNameSnapshot: project.categoryName,
            startAt: Date(timeIntervalSince1970: 2_100),
            endAt: Date(timeIntervalSince1970: 2_200),
            status: .confirmed
        ))
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
}
