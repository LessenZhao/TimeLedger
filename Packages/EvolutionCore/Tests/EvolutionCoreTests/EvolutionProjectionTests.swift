import Foundation
import XCTest
@testable import EvolutionCore

final class EvolutionProjectionTests: XCTestCase {
    func testLaterRecognitionAppearsTodayAndAtOriginalProjectPosition() throws {
        let fixture = try ProjectionFixture()
        let projectSnapshot = try fixture.ledger.read(.project(fixture.projectId))
        let recognitionDay = try fixture.ledger.read(.day("2026-07-17"))
        let happenedDay = try fixture.ledger.read(.day("2026-06-01"))

        XCTAssertEqual(projectSnapshot.nodes.map(\.id), ["node:old", "node:later"])
        XCTAssertEqual(projectSnapshot.days.flatMap(\.projectSlices).map(\.date), ["2026-06-01", "2026-07-17"])
        XCTAssertEqual(recognitionDay.nodes.map(\.id), ["node:later"])
        XCTAssertEqual(happenedDay.nodes.map(\.id), ["node:old"])
    }

    func testRecognitionDayResolvesOwningProjectAndAnnotatedSourceWithoutSameDayProjectWork() throws {
        let fixture = try ProjectionFixture()
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)
        var document = try store.load()
        let dayIndex = try XCTUnwrap(document.days.firstIndex { $0.date == "2026-07-17" })
        let historicalDayIndex = try XCTUnwrap(document.days.firstIndex { $0.date == "2026-06-01" })
        document.days[dayIndex].projectSlices = []
        document.days[historicalDayIndex].sourceSlices = [
            DailySessionSlice(
                id: "daily:historical",
                date: "2026-06-01",
                sessionId: "codex:thread-1",
                classification: .project,
                projectIds: [fixture.projectId],
                messageReferences: [],
                exclusionReason: nil
            )
        ]
        let nodeIndex = try XCTUnwrap(document.nodes.firstIndex { $0.id == "node:later" })
        document.nodes[nodeIndex].sourceSliceIds = ["daily:historical"]
        document.nodes[nodeIndex].evidenceIds = ["worktree:historical"]
        document.worktreeEvidence = [
            WorktreeEvidenceSnapshot(
                id: "worktree:historical",
                repoPath: "/tmp/project",
                branch: "main",
                head: "abc",
                capturedAt: date("2026-07-17T02:00:00Z"),
                relevantCommits: [],
                changes: [],
                checks: [],
                verificationStatus: .partial,
                limitation: "历史未提交状态不可还原",
                contentHash: "historical"
            )
        ]
        document.annotations = [
            annotation(
                id: "annotation:project-reflection",
                body: "今天才认识到旧项目的关键转向",
                target: AnnotationTarget(kind: .project, targetId: fixture.projectId),
                kind: .reflection,
                happenedAt: date("2026-06-01T01:00:00Z")
            ),
            annotation(
                id: "annotation:source-note",
                body: "补充原始会话上下文",
                target: AnnotationTarget(kind: .sourceSession, targetId: "codex:thread-1")
            ),
        ]
        try store.save(document)

        let snapshot = try EvolutionLedger(store: store).read(.day("2026-07-17"))
        XCTAssertEqual(snapshot.nodes.map(\.id), ["node:later"])
        XCTAssertEqual(snapshot.projects.map(\.id), [fixture.projectId])
        XCTAssertEqual(Set(snapshot.annotations.map(\.id)), ["annotation:project-reflection", "annotation:source-note"])
        XCTAssertEqual(snapshot.sourceSessions.map(\.id), ["codex:thread-1"])
        XCTAssertEqual(snapshot.worktreeEvidence.map(\.id), ["worktree:historical"])
        XCTAssertEqual(
            try EvolutionLedger(store: store).read(.project(fixture.projectId)).sourceSessions.map(\.id),
            ["codex:thread-1"]
        )
    }

    func testDayAndProjectViewsReuseTheSameStableProjectDaySlice() throws {
        let fixture = try ProjectionFixture()

        let daySlice = try XCTUnwrap(
            fixture.ledger.read(.day("2026-07-17")).days.first?.projectSlices.first
        )
        let projectSlice = try XCTUnwrap(
            fixture.ledger.read(.project(fixture.projectId)).days
                .flatMap(\.projectSlices)
                .first(where: { $0.date == "2026-07-17" })
        )

        XCTAssertEqual(daySlice, projectSlice)
        XCTAssertEqual(daySlice.id, "slice:2026-07-17:\(fixture.projectId)")
    }

    func testProjectViewDoesNotLeakIndependentThoughtsOrUnrelatedDailyCoverage() throws {
        let fixture = try ProjectionFixture()
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)
        var document = try store.load()
        let relevantSessionId = "codex:thread-1"
        let unrelatedSessionId = "codex:thread-other"
        let relevantSliceId = "daily:relevant"
        let unrelatedSliceId = "daily:unrelated"
        let dayIndex = try XCTUnwrap(document.days.firstIndex { $0.date == "2026-07-17" })
        document.days[dayIndex].projectSlices[0].sourceSliceIds = [relevantSliceId]
        document.days[dayIndex].independentThoughts = [
            IndependentThought(
                id: "thought:unrelated",
                date: "2026-07-17",
                title: "跨项目思考",
                body: "不应泄入单项目演化",
                factLevel: .inferred,
                decisions: [],
                learnings: [],
                values: [],
                sourceSliceIds: [unrelatedSliceId],
                evidenceIds: [],
                reviewState: .candidate
            )
        ]
        document.days[dayIndex].sourceSlices = [
            DailySessionSlice(
                id: relevantSliceId,
                date: "2026-07-17",
                sessionId: relevantSessionId,
                classification: .project,
                projectIds: [fixture.projectId],
                messageReferences: [],
                exclusionReason: nil
            ),
            DailySessionSlice(
                id: unrelatedSliceId,
                date: "2026-07-17",
                sessionId: unrelatedSessionId,
                classification: .pending,
                projectIds: [],
                messageReferences: [],
                exclusionReason: nil
            ),
        ]
        document.days[dayIndex].coverage = SourceCoverage(
            expectedSessionCount: 2,
            includedSessionIds: [relevantSessionId],
            pendingSessionIds: [unrelatedSessionId],
            excludedSessionIds: [],
            processorSessionIds: []
        )
        document.sourceSessions.append(
            SourceSessionRecord(
                id: unrelatedSessionId,
                source: .codex,
                externalThreadId: "thread-other",
                title: "其他会话",
                cwd: nil,
                createdAt: date("2026-07-17T00:00:00Z"),
                updatedAt: date("2026-07-17T01:00:00Z"),
                canonicalEventsPath: "/tmp/events.jsonl",
                canonicalThreadsPath: "/tmp/threads.jsonl",
                contentHash: "other"
            )
        )
        try store.save(document)

        let snapshot = try EvolutionLedger(store: store).read(.project(fixture.projectId))
        let projectedDay = try XCTUnwrap(snapshot.days.first { $0.date == "2026-07-17" })
        XCTAssertTrue(projectedDay.independentThoughts.isEmpty)
        XCTAssertEqual(projectedDay.sourceSlices.map(\.id), [relevantSliceId])
        XCTAssertEqual(projectedDay.coverage.expectedSessionCount, 1)
        XCTAssertEqual(projectedDay.coverage.includedSessionIds, [relevantSessionId])
        XCTAssertTrue(projectedDay.coverage.pendingSessionIds.isEmpty)
        XCTAssertEqual(snapshot.sourceSessions.map(\.id), [relevantSessionId])
    }

    func testReflectionUsesRecognitionDayButReturnsToTargetProject() throws {
        let fixture = try ProjectionFixture()
        let reflection = UserAnnotation(
            id: "annotation:reflection",
            target: AnnotationTarget(kind: .project, targetId: fixture.projectId),
            kind: .reflection,
            body: "一个月后确认轻量路线更适合长期维护",
            happenedAt: date("2026-06-01T01:00:00Z"),
            recognizedAt: date("2026-07-17T08:00:00Z"),
            createdAt: date("2026-07-17T08:00:00Z"),
            updatedAt: date("2026-07-17T08:00:00Z")
        )

        _ = try fixture.ledger.apply(.addAnnotation(reflection))

        XCTAssertEqual(try fixture.ledger.read(.day("2026-07-17")).annotations.map(\.id), [reflection.id])
        XCTAssertEqual(try fixture.ledger.read(.day("2026-06-01")).annotations, [])
        XCTAssertEqual(try fixture.ledger.read(.project(fixture.projectId)).annotations.map(\.id), [reflection.id])
    }

    func testAnnotationValidationRejectsInvalidUserContentAndMissingTargets() throws {
        let fixture = try ProjectionFixture()
        let validTarget = AnnotationTarget(kind: .day, targetId: "2026-07-17")

        XCTAssertThrowsError(try fixture.ledger.apply(.addAnnotation(annotation(body: "  ", target: validTarget)))) { error in
            XCTAssertEqual(error as? EvolutionLedgerError, .emptyAnnotationBody)
        }
        XCTAssertThrowsError(
            try fixture.ledger.apply(.addAnnotation(annotation(
                body: "后来认识",
                target: validTarget,
                kind: .reflection,
                happenedAt: nil
            )))
        ) { error in
            XCTAssertEqual(error as? EvolutionLedgerError, .reflectionRequiresHappenedAt)
        }
        let missing = AnnotationTarget(kind: .project, targetId: "project:missing")
        XCTAssertThrowsError(try fixture.ledger.apply(.addAnnotation(annotation(body: "纠正", target: missing)))) { error in
            XCTAssertEqual(error as? EvolutionLedgerError, .targetNotFound(missing))
        }
    }

    func testEveryAnnotationTargetKindMustResolveToAuthoritativeDocument() throws {
        let fixture = try ProjectionFixture()
        let targets = [
            AnnotationTarget(kind: .day, targetId: "2026-07-17"),
            AnnotationTarget(kind: .project, targetId: fixture.projectId),
            AnnotationTarget(kind: .projectDaySlice, targetId: "slice:2026-07-17:\(fixture.projectId)"),
            AnnotationTarget(kind: .evolutionNode, targetId: "node:later"),
            AnnotationTarget(kind: .sourceSession, targetId: "codex:thread-1"),
        ]

        for (index, target) in targets.enumerated() {
            _ = try fixture.ledger.apply(.addAnnotation(annotation(id: "annotation:\(index)", body: "补充 \(index)", target: target)))
        }

        XCTAssertEqual(try fixture.ledger.read(.all).annotations.count, targets.count)
    }

    func testAnnotationUpsertAndConfirmationPersistAcrossLedgerRecreation() throws {
        let fixture = try ProjectionFixture()
        let target = AnnotationTarget(kind: .project, targetId: fixture.projectId)
        let first = annotation(id: "annotation:stable", body: "第一版", target: target)
        var corrected = first
        corrected.body = "用户纠正后的版本"
        corrected.updatedAt = date("2026-07-17T10:00:00Z")

        _ = try fixture.ledger.apply(.addAnnotation(first))
        _ = try fixture.ledger.apply(.addAnnotation(corrected))
        _ = try fixture.ledger.apply(.confirmDay("2026-07-17"))
        _ = try fixture.ledger.apply(.confirmProject(fixture.projectId))
        _ = try fixture.ledger.apply(.confirmNode("node:later"))

        let reloaded = EvolutionLedger(store: JSONEvolutionDocumentStore(layout: fixture.layout))
        let snapshot = try reloaded.read(.all)
        XCTAssertEqual(snapshot.annotations.count, 1)
        XCTAssertEqual(snapshot.annotations.first?.body, "用户纠正后的版本")
        XCTAssertEqual(snapshot.days.first(where: { $0.date == "2026-07-17" })?.reviewState, .confirmed)
        XCTAssertEqual(snapshot.projects.first?.reviewState, .confirmed)
        XCTAssertEqual(snapshot.nodes.first(where: { $0.id == "node:later" })?.reviewState, .confirmed)
    }

    func testConfirmationOfMissingTargetThrowsExplicitError() throws {
        let fixture = try ProjectionFixture()

        XCTAssertThrowsError(try fixture.ledger.apply(.confirmDay("2099-01-01"))) { error in
            XCTAssertEqual(
                error as? EvolutionLedgerError,
                .targetNotFound(AnnotationTarget(kind: .day, targetId: "2099-01-01"))
            )
        }
        XCTAssertThrowsError(try fixture.ledger.apply(.confirmNode("node:missing"))) { error in
            XCTAssertEqual(
                error as? EvolutionLedgerError,
                .targetNotFound(AnnotationTarget(kind: .evolutionNode, targetId: "node:missing"))
            )
        }
    }

    func testConfirmNodeTouchesOwningProjectWithoutChangingEventTimes() throws {
        let fixture = try ProjectionFixture()
        let before = try XCTUnwrap(fixture.ledger.read(.all).nodes.first { $0.id == "node:later" })
        let projectUpdatedAt = try XCTUnwrap(fixture.ledger.read(.all).projects.first?.updatedAt)

        _ = try fixture.ledger.apply(.confirmNode(before.id))

        let snapshot = try fixture.ledger.read(.all)
        let after = try XCTUnwrap(snapshot.nodes.first { $0.id == before.id })
        XCTAssertEqual(after.reviewState, .confirmed)
        XCTAssertEqual(after.happenedAt, before.happenedAt)
        XCTAssertEqual(after.recognizedAt, before.recognizedAt)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.projects.first?.updatedAt), projectUpdatedAt)
    }
}

private struct ProjectionFixture {
    let layout: EvolutionLedgerLayout
    let projectId = "project:skill-manager"
    let ledger: EvolutionLedger

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionProjectionTests-\(UUID().uuidString)", isDirectory: true)
        layout = EvolutionLedgerLayout(rootURL: root)
        let store = JSONEvolutionDocumentStore(layout: layout)
        let project = EvolutionProject(
            id: projectId,
            name: "Skill Manager",
            goal: "用最低复杂度管理 Skills",
            aliases: [],
            routes: [],
            progressStatus: .active,
            endMode: nil,
            artifactStatus: .pendingValidation,
            reviewState: .candidate,
            createdAt: date("2026-06-01T00:00:00Z"),
            updatedAt: date("2026-07-17T00:00:00Z")
        )
        let sourceSession = SourceSessionRecord(
            id: "codex:thread-1",
            source: .codex,
            externalThreadId: "thread-1",
            title: "Skill Manager",
            cwd: "/tmp/skill-manager",
            createdAt: date("2026-06-01T00:00:00Z"),
            updatedAt: date("2026-07-17T00:00:00Z"),
            canonicalEventsPath: "/tmp/events.jsonl",
            canonicalThreadsPath: "/tmp/threads-index.jsonl",
            contentHash: "hash"
        )
        let document = EvolutionLedgerDocument(
            projects: [project],
            days: [
                makeProjectionDay(date: "2026-07-17", projectId: projectId),
                makeProjectionDay(date: "2026-06-01", projectId: projectId),
            ],
            nodes: [
                makeProjectionNode(
                    id: "node:later",
                    projectId: projectId,
                    happenedAt: date("2026-06-01T01:00:00Z"),
                    recognizedAt: date("2026-07-17T01:00:00Z")
                ),
                makeProjectionNode(
                    id: "node:old",
                    projectId: projectId,
                    happenedAt: date("2026-05-01T01:00:00Z"),
                    recognizedAt: date("2026-06-01T01:00:00Z")
                ),
            ],
            annotations: [],
            sourceSessions: [sourceSession],
            worktreeEvidence: [],
            imports: [],
            updatedAt: date("2026-07-17T02:00:00Z")
        )
        try store.save(document)
        ledger = EvolutionLedger(store: store)
    }
}

private func makeProjectionDay(date key: String, projectId: String) -> WorkEvolutionDayRecord {
    WorkEvolutionDayRecord(
        date: key,
        sourceCutoffAt: date("2026-07-18T00:00:00Z"),
        projectSlices: [
            ProjectDaySlice(
                id: "slice:\(key):\(projectId)",
                date: key,
                projectId: projectId,
                routeIds: [],
                purpose: "验证路线",
                actions: ["实现"],
                progress: "推进",
                factLevel: .verified,
                decisions: [],
                learnings: [],
                values: [],
                sourceSliceIds: [],
                evidenceIds: [],
                reviewState: .candidate
            )
        ],
        independentThoughts: [],
        sourceSlices: [],
        coverage: SourceCoverage(
            expectedSessionCount: 0,
            includedSessionIds: [],
            pendingSessionIds: [],
            excludedSessionIds: [],
            processorSessionIds: []
        ),
        reviewState: .candidate,
        generatedAt: date("2026-07-17T00:00:00Z"),
        updatedAt: date("2026-07-17T00:00:00Z")
    )
}

private func makeProjectionNode(id: String, projectId: String, happenedAt: Date, recognizedAt: Date) -> EvolutionNode {
    EvolutionNode(
        id: id,
        projectId: projectId,
        routeIds: [],
        happenedAt: happenedAt,
        recognizedAt: recognizedAt,
        kind: .reflection,
        title: id,
        detail: "",
        reason: "",
        origin: .joint,
        factLevel: .verified,
        sourceSliceIds: [],
        evidenceIds: [],
        reviewState: .candidate
    )
}

private func annotation(
    id: String = "annotation:test",
    body: String,
    target: AnnotationTarget,
    kind: AnnotationKind = .supplement,
    happenedAt: Date? = nil
) -> UserAnnotation {
    UserAnnotation(
        id: id,
        target: target,
        kind: kind,
        body: body,
        happenedAt: happenedAt,
        recognizedAt: date("2026-07-17T08:00:00Z"),
        createdAt: date("2026-07-17T08:00:00Z"),
        updatedAt: date("2026-07-17T08:00:00Z")
    )
}

private func date(_ value: String) -> Date {
    ISO8601Codec.date(from: value)!
}
