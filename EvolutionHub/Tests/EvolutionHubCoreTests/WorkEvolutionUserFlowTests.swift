import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

final class WorkEvolutionUserFlowTests: XCTestCase {
    @MainActor
    func testTrustedImportUserEditsConfirmationsAndReplayPreserveUserTruth() async throws {
        let fixture = try InboxTestFixture()
        let recognizedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-18T02:03:04Z"))
        let happenedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-06-01T01:00:00Z"))
        let proposal = try installProjectProposal(in: fixture)
        let project = try XCTUnwrap(proposal.projects.first)
        let day = try XCTUnwrap(proposal.days.first)
        let projectSlice = try XCTUnwrap(day.projectSlices.first)
        let node = try XCTUnwrap(proposal.nodes.first)
        let sourceSlice = try XCTUnwrap(day.sourceSlices.first)
        let store = WorkEvolutionHubStore(layout: fixture.layout, now: { recognizedAt })

        await store.refresh()

        XCTAssertEqual(store.receipts.map(\.status), [.imported])
        XCTAssertEqual(store.snapshot.days.map(\.date), [fixture.dateKey])
        XCTAssertEqual(store.snapshot.projects.map(\.id), [project.id])
        XCTAssertEqual(store.snapshot.days.first?.projectSlices.map(\.id), [projectSlice.id])
        XCTAssertEqual(store.snapshot.nodes.map(\.id), [node.id])
        XCTAssertEqual(store.snapshot.sourceSessions.map(\.id), [sourceSlice.sessionId])
        XCTAssertEqual(store.snapshot.days.first?.sourceSlices.map(\.id), [sourceSlice.id])
        XCTAssertEqual(store.snapshot.days.first?.sourceSlices.first?.projectIds, [project.id])

        try store.addAnnotation(
            target: AnnotationTarget(kind: .day, targetId: fixture.dateKey),
            kind: .supplement,
            body: "当天补充：真正完成的是价值沉淀闭环"
        )
        try store.addAnnotation(
            target: AnnotationTarget(kind: .evolutionNode, targetId: node.id),
            kind: .correction,
            body: "节点纠正：选择轻量路线不是放弃能力，而是先验证核心价值"
        )
        try store.addAnnotation(
            target: AnnotationTarget(kind: .evolutionNode, targetId: node.id),
            kind: .reflection,
            body: "后来认识：六月的复杂路线帮助确认最少必要架构",
            happenedAt: happenedAt
        )

        let projectionLedger = EvolutionLedger(
            store: JSONEvolutionDocumentStore(layout: fixture.layout)
        )
        let recognizedDay = try projectionLedger.read(.day("2026-07-18"))
        let reflection = try XCTUnwrap(
            recognizedDay.annotations.first(where: { $0.kind == .reflection })
        )
        XCTAssertEqual(reflection.happenedAt, happenedAt)
        XCTAssertEqual(reflection.recognizedAt, recognizedAt)
        XCTAssertEqual(recognizedDay.projects.map(\.id), [project.id])
        XCTAssertEqual(
            try projectionLedger.read(.day("2026-06-01")).annotations
                .filter { $0.id == reflection.id },
            []
        )
        XCTAssertEqual(
            try projectionLedger.read(.project(project.id)).annotations
                .first(where: { $0.id == reflection.id })?.body,
            reflection.body
        )

        try store.confirmDay(fixture.dateKey)
        try store.confirmProject(project.id)
        try store.confirmNode(node.id)

        try installSameSourceUpdate(
            from: proposal,
            fixture: fixture,
            jobId: "job-same-source-update"
        )
        await store.refresh()

        let updateReceipt = try XCTUnwrap(store.receipts.first)
        XCTAssertEqual(updateReceipt.status, .imported)
        XCTAssertTrue(updateReceipt.skippedLockedIds.contains(fixture.dateKey))
        XCTAssertTrue(updateReceipt.skippedLockedIds.contains(project.id))
        XCTAssertTrue(updateReceipt.skippedLockedIds.contains(node.id))
        assertUserTruthAndLocksPreserved(
            in: store.snapshot,
            originalProposal: proposal,
            expectedAnnotationCount: 3
        )

        let originalProcessed = fixture.layout.processedDirectoryURL
            .appendingPathComponent("\(fixture.jobId).json")
        try Data(contentsOf: originalProcessed).write(to: fixture.inboxURL, options: .atomic)
        await store.refresh()

        XCTAssertEqual(store.receipts.map(\.status), [.noOp])
        assertUserTruthAndLocksPreserved(
            in: store.snapshot,
            originalProposal: proposal,
            expectedAnnotationCount: 3
        )
        XCTAssertEqual(
            try projectionLedger.read(.project(project.id)).annotations
                .filter { $0.kind == .reflection }
                .map(\.body),
            ["后来认识：六月的复杂路线帮助确认最少必要架构"]
        )
    }
}

private extension WorkEvolutionUserFlowTests {
    func installProjectProposal(
        in fixture: InboxTestFixture
    ) throws -> EvolutionProposalEnvelope {
        var sourceSlice = try XCTUnwrap(fixture.proposal.days.first?.sourceSlices.first)
        let projectGoal = "把每日工作沉淀为可复用价值"
        let projectId = EvolutionStableID.newProject(normalizedGoal: projectGoal)
        let routeId = EvolutionStableID.route(
            projectId: projectId,
            name: "最少必要架构",
            repoPaths: ["/tmp/project"]
        )
        let createdAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T10:00:00Z"))
        let recognizedAt = try XCTUnwrap(ISO8601Codec.date(from: "2026-07-17T11:00:00Z"))
        let messageId = try XCTUnwrap(sourceSlice.messageReferences.first?.id)

        sourceSlice.classification = .project
        sourceSlice.projectIds = [projectId]
        let route = ProjectRoute(
            id: routeId,
            name: "最少必要架构",
            summary: "先验证每日价值沉淀闭环",
            repoPaths: ["/tmp/project"],
            startedAt: createdAt,
            endedAt: nil,
            status: .active,
            reviewState: .candidate
        )
        let project = EvolutionProject(
            id: projectId,
            name: "Work Evolution",
            goal: projectGoal,
            aliases: ["每日价值地图"],
            routes: [route],
            progressStatus: .active,
            endMode: nil,
            artifactStatus: .pendingValidation,
            reviewState: .candidate,
            createdAt: createdAt,
            updatedAt: recognizedAt
        )
        let projectSliceId = EvolutionStableID.projectDaySlice(
            date: fixture.dateKey,
            projectId: projectId
        )
        let projectSlice = ProjectDaySlice(
            id: projectSliceId,
            date: fixture.dateKey,
            projectId: projectId,
            routeIds: [routeId],
            purpose: "验证按天和按项目的双轴价值地图",
            actions: ["建立可信来源", "形成演化节点"],
            progress: "完成第一版闭环",
            factLevel: .verified,
            decisions: [],
            learnings: [],
            values: [],
            sourceSliceIds: [sourceSlice.id],
            evidenceIds: [messageId],
            reviewState: .candidate
        )
        let nodeTitle = "从重架构转向最少必要架构"
        let node = EvolutionNode(
            id: EvolutionStableID.evolutionNode(
                projectId: projectId,
                kind: .pivot,
                happenedAt: createdAt,
                title: nodeTitle
            ),
            projectId: projectId,
            routeIds: [routeId],
            happenedAt: createdAt,
            recognizedAt: recognizedAt,
            kind: .pivot,
            title: nodeTitle,
            detail: "先用轻量闭环验证需求",
            reason: "复杂桌面架构的维护成本超过当前价值",
            origin: .joint,
            factLevel: .verified,
            sourceSliceIds: [sourceSlice.id],
            evidenceIds: [messageId],
            reviewState: .candidate
        )
        var day = try XCTUnwrap(fixture.proposal.days.first)
        day.projectSlices = [projectSlice]
        day.sourceSlices = [sourceSlice]
        day.coverage = SourceCoverage(
            expectedSessionCount: 1,
            includedSessionIds: [sourceSlice.sessionId],
            pendingSessionIds: [],
            excludedSessionIds: [],
            processorSessionIds: []
        )
        let sourceDigest = EvolutionSourceDigest.make(
            sourceCutoffAt: fixture.cutoffAt,
            days: [day]
        )
        let proposal = EvolutionProposalEnvelope(
            jobId: fixture.jobId,
            scope: EvolutionProposalScope(kind: .day, dates: [fixture.dateKey]),
            createdAt: fixture.proposal.createdAt,
            sourceCutoffAt: fixture.cutoffAt,
            sourceDigest: sourceDigest,
            sessions: fixture.proposal.sessions,
            days: [day],
            projects: [project],
            nodes: [node],
            worktreeEvidence: [],
            userAnnotations: [],
            diagnostics: []
        )
        var evidence = fixture.bundle
        evidence.sourceDigest = sourceDigest
        evidence.contentHash = evidence.recomputedContentHash()
        try ISO8601Codec.encoder.encode(proposal).write(to: fixture.inboxURL, options: .atomic)
        try ISO8601Codec.encoder.encode(evidence).write(to: fixture.evidenceURL, options: .atomic)
        return proposal
    }

    func installSameSourceUpdate(
        from original: EvolutionProposalEnvelope,
        fixture: InboxTestFixture,
        jobId: String
    ) throws {
        var update = original
        update.jobId = jobId
        update.days[0].projectSlices[0].progress = "自动候选试图覆盖已确认日"
        update.projects[0].name = "自动候选试图覆盖已确认项目"
        update.nodes[0].detail = "自动候选试图覆盖已确认节点"

        var evidence = fixture.bundle
        evidence.jobId = jobId
        evidence.sourceDigest = update.sourceDigest
        evidence.contentHash = evidence.recomputedContentHash()
        let jobDirectory = fixture.layout.jobsDirectoryURL
            .appendingPathComponent(jobId, isDirectory: true)
        try FileManager.default.createDirectory(
            at: jobDirectory,
            withIntermediateDirectories: true
        )
        try ISO8601Codec.encoder.encode(update).write(
            to: fixture.layout.inboxDirectoryURL.appendingPathComponent("\(jobId).json"),
            options: .atomic
        )
        try ISO8601Codec.encoder.encode(evidence).write(
            to: jobDirectory.appendingPathComponent("evidence.json"),
            options: .atomic
        )
    }

    func assertUserTruthAndLocksPreserved(
        in snapshot: EvolutionSnapshot,
        originalProposal: EvolutionProposalEnvelope,
        expectedAnnotationCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let originalDay = originalProposal.days[0]
        let originalProject = originalProposal.projects[0]
        let originalNode = originalProposal.nodes[0]
        XCTAssertEqual(snapshot.days.first?.reviewState, .confirmed, file: file, line: line)
        XCTAssertEqual(snapshot.days.first?.projectSlices.first?.progress, originalDay.projectSlices[0].progress, file: file, line: line)
        XCTAssertEqual(snapshot.projects.first?.reviewState, .confirmed, file: file, line: line)
        XCTAssertEqual(snapshot.projects.first?.name, originalProject.name, file: file, line: line)
        XCTAssertEqual(snapshot.nodes.first?.reviewState, .confirmed, file: file, line: line)
        XCTAssertEqual(snapshot.nodes.first?.detail, originalNode.detail, file: file, line: line)
        XCTAssertEqual(snapshot.annotations.count, expectedAnnotationCount, file: file, line: line)
        XCTAssertEqual(
            Set(snapshot.annotations.map(\.body)),
            Set([
                "当天补充：真正完成的是价值沉淀闭环",
                "节点纠正：选择轻量路线不是放弃能力，而是先验证核心价值",
                "后来认识：六月的复杂路线帮助确认最少必要架构",
            ]),
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.annotations.first(where: { $0.kind == .supplement })?.target,
            AnnotationTarget(kind: .day, targetId: originalDay.date),
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.annotations.filter { $0.kind != .supplement }.map(\.target),
            Array(repeating: AnnotationTarget(kind: .evolutionNode, targetId: originalNode.id), count: 2),
            file: file,
            line: line
        )
    }
}
