import EvolutionCore
import EvolutionHubCore
import XCTest

final class SyncAndNormalizeTests: XCTestCase {
    @MainActor
    func testSyncBatchRoundTripImport() throws {
        let payload = TimeEntrySyncPayload(
            id: "entry-1",
            projectId: "proj-1",
            projectNameSnapshot: "TimeLedger",
            categoryNameSnapshot: "开发",
            startAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
            endAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
            note: "n",
            status: "confirmed",
            createdAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
            updatedAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        )
        let env = try AnySyncEnvelope(
            deviceId: "iphone",
            entityType: .timeEntry,
            entityId: "entry-1",
            revision: 2,
            updatedAt: payload.updatedAt,
            payload: payload
        )
        let batch = SyncBatchFile(deviceId: "iphone", envelopes: [env])
        let data = try ISO8601Codec.encoder.encode(batch)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try SyncBatchImporter.importFile(at: url)
        XCTAssertEqual(decoded.envelopes.count, 1)

        let store = HubStore(
            selectedDay: ISO8601Codec.date(from: "2026-07-12T12:00:00Z")!,
            calendar: {
                var c = Calendar(identifier: .gregorian)
                c.timeZone = TimeZone(secondsFromGMT: 0)!
                return c
            }()
        )
        let result = try SyncBatchImporter.applyToStore(batch: decoded, store: store)
        XCTAssertEqual(result.accepted, 1)
        XCTAssertEqual(store.timeEntries.count, 1)
        // re-import same revision should not duplicate
        let again = try SyncBatchImporter.applyToStore(batch: decoded, store: store)
        XCTAssertEqual(again.accepted, 0)
        XCTAssertEqual(store.timeEntries.count, 1)
    }

    func testCodexAdapterNormalizesJSONL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let thread = """
        {"thread_id":"tid-1","title":"Hello","cwd":"/Users/x/TimeLedger","created_at":"2026-07-12T01:00:00Z","updated_at":"2026-07-12T02:00:00Z","preview":"hi","source_file":"/tmp/a.jsonl"}
        """
        let event = """
        {"event_id":"ev1","thread_id":"tid-1","role":"user","text":"build hub","created_at":"2026-07-12T01:10:00Z","source_file":"/tmp/a.jsonl","source_line":1}
        """
        try thread.write(to: root.appendingPathComponent("threads-index.jsonl"), atomically: true, encoding: .utf8)
        try event.write(to: root.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let window = NaturalDayWindow.forDate(ISO8601Codec.date(from: "2026-07-12T12:00:00Z")!, calendar: cal)
        let pkg = try CodexClaudeAdapter.normalize(source: .codex, outputRoot: root, dayWindow: window)
        XCTAssertEqual(pkg.threads.count, 1)
        XCTAssertEqual(pkg.events.count, 1)
        XCTAssertEqual(pkg.messages.count, 1)
        XCTAssertEqual(pkg.threads[0].projectHint, "TimeLedger")
    }
}
