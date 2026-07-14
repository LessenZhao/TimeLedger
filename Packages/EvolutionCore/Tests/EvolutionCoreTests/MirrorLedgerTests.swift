import XCTest
@testable import EvolutionCore

final class MirrorLedgerTests: XCTestCase {
    func testCannotBookkeepWhenDisconnected() {
        var engine = MirrorLedgerEngine()
        XCTAssertThrowsError(try engine.quickRecord(projectId: "p1")) { error in
            XCTAssertEqual(error as? MirrorLedgerError, .notConnected)
        }
    }

    func testConnectAndQuickRecordUpdatesCursor() throws {
        var engine = MirrorLedgerEngine(macDeviceId: "mac-1")
        let snapshot = MirrorLedgerSnapshot(
            phoneDeviceId: "phone-1",
            cursor: MirrorCursor(cursorAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!),
            projects: [
                MirrorProject(id: "p1", name: "TimeLedger", categoryName: "开发")
            ]
        )
        engine.connect(with: snapshot)
        XCTAssertTrue(engine.canBookkeep)

        let now = ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        let entry = try engine.quickRecord(projectId: "p1", now: now)
        XCTAssertEqual(entry.status, "draft")
        XCTAssertEqual(engine.cursor?.cursorAt, now)
        XCTAssertEqual(engine.drafts(on: now, calendar: utcCalendar).count, 1)
        XCTAssertFalse(engine.pendingOutbound.isEmpty)
    }

    func testDisconnectClearsLedger() throws {
        var engine = MirrorLedgerEngine()
        engine.connect(with: MirrorLedgerSnapshot(
            phoneDeviceId: "phone",
            cursor: MirrorCursor(cursorAt: Date().addingTimeInterval(-3600)),
            projects: [MirrorProject(id: "p", name: "A", categoryName: "c")]
        ))
        _ = try engine.quickRecord(projectId: "p", now: Date())
        engine.disconnect()
        XCTAssertFalse(engine.canBookkeep)
        XCTAssertTrue(engine.timeEntries.isEmpty)
        XCTAssertThrowsError(try engine.quickRecord(projectId: "p"))
    }

    func testUpdateDraftEntry() throws {
        var engine = MirrorLedgerEngine(macDeviceId: "mac")
        engine.connect(with: MirrorLedgerSnapshot(
            phoneDeviceId: "phone",
            cursor: MirrorCursor(cursorAt: ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!),
            projects: [MirrorProject(id: "p1", name: "TL", categoryName: "开发")]
        ))
        let entry = try engine.quickRecord(
            projectId: "p1",
            now: ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        )
        try engine.updateDraftEntry(
            id: entry.id,
            startAt: ISO8601Codec.date(from: "2026-07-12T01:10:00Z")!,
            endAt: ISO8601Codec.date(from: "2026-07-12T01:50:00Z")!,
            note: "edited"
        )
        XCTAssertEqual(engine.timeEntries.first?.note, "edited")
        XCTAssertEqual(
            engine.timeEntries.first?.startAt,
            ISO8601Codec.date(from: "2026-07-12T01:10:00Z")!
        )
    }

    func testFrameCodecRoundTrip() {
        var buffer = Data()
        let a = Data("hello".utf8)
        let b = Data("world".utf8)
        buffer.append(MirrorFrameCodec.encode(a))
        buffer.append(MirrorFrameCodec.encode(b))
        let frames = MirrorFrameCodec.decodeFrames(buffer: &buffer)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(String(data: frames[0], encoding: .utf8), "hello")
        XCTAssertEqual(String(data: frames[1], encoding: .utf8), "world")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testSnapshotBuilderFromSyncBatch() throws {
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
        let env = try AnySyncEnvelope(
            deviceId: "phone",
            entityType: .timeEntry,
            entityId: "e1",
            revision: 2,
            updatedAt: payload.updatedAt,
            payload: payload
        )
        let proj = try AnySyncEnvelope(
            deviceId: "phone",
            entityType: .project,
            entityId: "p1",
            revision: 1,
            updatedAt: payload.updatedAt,
            payload: ProjectSyncPayload(id: "p1", name: "TL", categoryName: "开发")
        )
        let batch = SyncBatchFile(deviceId: "phone", envelopes: [proj, env])
        let snap = try MirrorSnapshotBuilder.fromSyncBatch(batch)
        XCTAssertEqual(snap.phoneDeviceId, "phone")
        XCTAssertEqual(snap.timeEntries.count, 1)
        XCTAssertEqual(snap.projects.count, 1)
    }

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
}
