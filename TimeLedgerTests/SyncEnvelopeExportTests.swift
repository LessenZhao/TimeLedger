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
}
