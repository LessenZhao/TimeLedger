import XCTest
@testable import EvolutionCore

private struct TimeEntryPayload: Codable, Sendable, Hashable {
    var id: String
    var projectName: String
    var startAt: Date
    var endAt: Date
}

final class SyncEnvelopeTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let payload = TimeEntryPayload(
            id: "te-1",
            projectName: "TimeLedger",
            startAt: ISO8601Codec.date(from: "2026-07-12T09:00:00+08:00")!,
            endAt: ISO8601Codec.date(from: "2026-07-12T10:00:00+08:00")!
        )
        let envelope = SyncEnvelope(
            deviceId: "iphone-1",
            entityType: .timeEntry,
            entityId: "te-1",
            operation: .upsert,
            revision: 3,
            updatedAt: ISO8601Codec.date(from: "2026-07-12T10:01:00+08:00")!,
            payload: payload
        )

        let data = try ISO8601Codec.encoder.encode(envelope)
        let decoded = try ISO8601Codec.decoder.decode(SyncEnvelope<TimeEntryPayload>.self, from: data)

        XCTAssertEqual(decoded.protocolVersion, EvolutionSchema.protocolVersion)
        XCTAssertEqual(decoded.revision, 3)
        XCTAssertEqual(decoded.payload.projectName, "TimeLedger")
        XCTAssertEqual(decoded.entityType, .timeEntry)
    }

    func testRevisionPolicyHigherWins() {
        let older = ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!
        let newer = ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        XCTAssertTrue(SyncRevisionPolicy.shouldAccept(
            existingRevision: 1,
            existingUpdatedAt: newer,
            incomingRevision: 2,
            incomingUpdatedAt: older
        ))
        XCTAssertFalse(SyncRevisionPolicy.shouldAccept(
            existingRevision: 2,
            existingUpdatedAt: older,
            incomingRevision: 1,
            incomingUpdatedAt: newer
        ))
    }

    func testRevisionPolicyTieBreaksOnUpdatedAt() {
        let older = ISO8601Codec.date(from: "2026-07-12T01:00:00Z")!
        let newer = ISO8601Codec.date(from: "2026-07-12T02:00:00Z")!
        XCTAssertTrue(SyncRevisionPolicy.shouldAccept(
            existingRevision: 5,
            existingUpdatedAt: older,
            incomingRevision: 5,
            incomingUpdatedAt: newer
        ))
        XCTAssertFalse(SyncRevisionPolicy.shouldAccept(
            existingRevision: 5,
            existingUpdatedAt: newer,
            incomingRevision: 5,
            incomingUpdatedAt: older
        ))
    }
}
