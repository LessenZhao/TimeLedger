import EvolutionCore
import EvolutionHubCore
import XCTest

final class MirrorSessionControllerTests: XCTestCase {
    @MainActor
    func testConnectFromBatchThenRecord() throws {
        let payload = TimeEntrySyncPayload(
            id: "e1",
            projectId: "p1",
            projectNameSnapshot: "TL",
            categoryNameSnapshot: "开发",
            startAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!,
            endAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
            note: "",
            status: "confirmed",
            createdAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
            updatedAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        )
        let proj = try AnySyncEnvelope(
            deviceId: "phone",
            entityType: .project,
            entityId: "p1",
            revision: 1,
            updatedAt: Date(),
            payload: ProjectSyncPayload(id: "p1", name: "TL", categoryName: "开发")
        )
        let entry = try AnySyncEnvelope(
            deviceId: "phone",
            entityType: .timeEntry,
            entityId: "e1",
            revision: 1,
            updatedAt: Date(),
            payload: payload
        )
        let cursor = try AnySyncEnvelope(
            deviceId: "phone",
            entityType: .timeCursor,
            entityId: "cursor",
            revision: 1,
            updatedAt: Date(),
            payload: TimeCursorSyncPayload(
                cursorAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
                updatedAt: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!,
                revision: 1
            )
        )
        let batch = SyncBatchFile(deviceId: "phone", envelopes: [proj, entry, cursor])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mirror-test-\(UUID().uuidString).json")
        try ISO8601Codec.encoder.encode(batch).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = MirrorSessionController(macDeviceId: "mac-test")
        XCTAssertFalse(session.canBookkeep)
        try session.connectFromSyncBatchFile(url: url)
        XCTAssertTrue(session.canBookkeep)
        XCTAssertEqual(session.engine.projects.count, 1)

        // Move "now" via quickRecord with future end: controller uses session.now
        // Force by recording with engine directly after connect using known times
        var engine = session.engine
        let recorded = try engine.quickRecord(
            projectId: "p1",
            now: ISO8601Codec.date(from: "2026-07-12T03:00:00Z")!
        )
        XCTAssertEqual(recorded.status, "draft")
        XCTAssertEqual(engine.cursor?.cursorAt, ISO8601Codec.date(from: "2026-07-12T03:00:00Z")!)
    }
}
