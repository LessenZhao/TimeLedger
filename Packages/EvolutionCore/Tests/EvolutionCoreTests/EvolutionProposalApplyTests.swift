import Foundation
import XCTest
@testable import EvolutionCore

final class EvolutionProposalApplyTests: XCTestCase {
    func testCandidateRecordsUpdateByStableID() throws {
        let fixture = try ProposalFixture()
        let store = MemoryProposalStore()
        let ledger = EvolutionLedger(store: store)
        _ = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")

        var update = fixture.proposal
        update.jobId = "job-2"
        update.days[0].projectSlices[0].progress = "候选日已更新"
        update.projects[0].name = "候选项目已更新"
        update.projects[0].goal = "候选项目目标已经演化"
        update.projects[0].routes[0].summary = "候选路线已更新"
        update.nodes[0].detail = "候选节点已更新"
        _ = try ledger.apply(update, proposalDigest: "digest-2")

        let snapshot = try ledger.read(.all)
        XCTAssertEqual(snapshot.days[0].projectSlices[0].progress, "候选日已更新")
        let project = try XCTUnwrap(snapshot.projects.first { $0.id == fixture.projectId })
        XCTAssertEqual(project.name, "候选项目已更新")
        XCTAssertEqual(project.goal, "候选项目目标已经演化")
        XCTAssertEqual(project.routes[0].summary, "候选路线已更新")
        XCTAssertEqual(snapshot.nodes[0].detail, "候选节点已更新")
    }

    func testImportIsIdempotentAndPreservesUserLocksAndAnnotations() throws {
        let fixture = try ProposalFixture()
        let store = MemoryProposalStore()
        let ledger = EvolutionLedger(store: store)

        let first = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")
        XCTAssertEqual(first.status, .imported)
        XCTAssertEqual(first.acceptedDayIds, ["2026-07-17"])
        _ = try ledger.apply(.addAnnotation(fixture.annotation))
        _ = try ledger.apply(.confirmDay("2026-07-17"))
        _ = try ledger.apply(.confirmProject(fixture.projectId))
        let nodeId = try XCTUnwrap(fixture.proposal.nodes.first?.id)
        _ = try ledger.apply(.confirmNode(nodeId))

        let noOp = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")
        XCTAssertEqual(noOp.status, .noOp)

        var update = fixture.proposal
        update.jobId = "job-2"
        update.days[0].projectSlices[0].progress = "不应覆盖 confirmed day"
        update.projects[0].name = "不应覆盖 confirmed project"
        update.nodes[0].detail = "不应覆盖 confirmed node"
        var lockedRoute = update.projects[0].routes[0]
        lockedRoute.summary = "不应覆盖 confirmed route"
        store.document.projects[0].routes[0].reviewState = .confirmed
        let newRoute = ProjectRoute(
            id: EvolutionStableID.route(projectId: fixture.projectId, name: "新候选路线", repoPaths: ["/tmp/new"]),
            name: "新候选路线",
            summary: "允许追加",
            repoPaths: ["/tmp/new"],
            startedAt: proposalDate("2026-07-17T03:00:00Z"),
            endedAt: nil,
            status: .active,
            reviewState: .candidate
        )
        update.projects[0].routes = [lockedRoute, newRoute]
        let receipt = try ledger.apply(update, proposalDigest: "digest-2")

        XCTAssertEqual(receipt.status, .imported)
        XCTAssertTrue(receipt.skippedLockedIds.contains("2026-07-17"))
        XCTAssertTrue(receipt.skippedLockedIds.contains(fixture.projectId))
        XCTAssertTrue(receipt.skippedLockedIds.contains(nodeId))
        let snapshot = try ledger.read(.all)
        XCTAssertEqual(snapshot.annotations.map(\.body), ["用户纠正"])
        XCTAssertEqual(snapshot.days[0].projectSlices[0].progress, "完成结构校验")
        let project = try XCTUnwrap(snapshot.projects.first { $0.id == fixture.projectId })
        XCTAssertEqual(project.name, "Fixture")
        XCTAssertEqual(project.routes.first { $0.id == fixture.routeId }?.summary, "先验证闭环")
        XCTAssertEqual(project.routes.first { $0.id == newRoute.id }?.summary, "允许追加")
        XCTAssertEqual(snapshot.nodes.first { $0.id == nodeId }?.detail, "避免重型架构")
    }

    func testDifferentDigestForSameJobReturnsConflictWithoutChangingLedgerBytes() throws {
        let fixture = try ProposalFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionConflict-\(UUID().uuidString)", isDirectory: true)
        let layout = EvolutionLedgerLayout(rootURL: root)
        let ledger = EvolutionLedger(store: JSONEvolutionDocumentStore(layout: layout))
        _ = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")
        let before = try Data(contentsOf: layout.ledgerFileURL)

        let receipt = try ledger.apply(fixture.proposal, proposalDigest: "digest-other")

        XCTAssertEqual(receipt.status, .conflict)
        XCTAssertFalse(receipt.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: layout.ledgerFileURL), before)
    }

    func testStructuralValidationHappensBeforeLoadingOrSaving() throws {
        let fixture = try ProposalFixture()
        var invalid = fixture.proposal
        invalid.schemaVersion += 1
        let store = MemoryProposalStore()

        XCTAssertThrowsError(try EvolutionLedger(store: store).apply(invalid, proposalDigest: "bad"))
        XCTAssertEqual(store.loadCount, 0)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testPreflightRejectsMutableEvidenceSessionIdentityAndProjectSplitsWithoutSaving() throws {
        let fixture = try ProposalFixture()

        do {
            let store = MemoryProposalStore()
            let ledger = EvolutionLedger(store: store)
            _ = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")
            store.document.worktreeEvidence[0].contentHash = "different-existing-bytes"
            let saves = store.saveCount
            var update = fixture.proposal
            update.jobId = "worktree-conflict"
            let receipt = try ledger.apply(update, proposalDigest: "digest-2")
            XCTAssertEqual(receipt.status, .conflict)
            XCTAssertEqual(store.saveCount, saves)
        }

        do {
            let store = MemoryProposalStore()
            let ledger = EvolutionLedger(store: store)
            _ = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")
            store.document.sourceSessions[0].canonicalEventsPath = "/different/archive.jsonl"
            let saves = store.saveCount
            var update = fixture.proposal
            update.jobId = "session-conflict"
            let receipt = try ledger.apply(update, proposalDigest: "digest-2")
            XCTAssertEqual(receipt.status, .conflict)
            XCTAssertEqual(store.saveCount, saves)
        }

        do {
            let store = MemoryProposalStore()
            let ledger = EvolutionLedger(store: store)
            var invalidNewProject = fixture.proposal
            invalidNewProject.jobId = "invalid-new-project"
            invalidNewProject.projects[0].goal = "与稳定 ID 不对应的新目标"
            let receipt = try ledger.apply(invalidNewProject, proposalDigest: "digest")
            XCTAssertEqual(receipt.status, .conflict)
            XCTAssertEqual(store.saveCount, 0)
        }

        do {
            let store = MemoryProposalStore()
            var split = fixture.proposal.projects[0]
            split.id = "project:legacy-split"
            split.routes = []
            store.document.projects = [split]
            let receipt = try EvolutionLedger(store: store).apply(fixture.proposal, proposalDigest: "digest")
            XCTAssertEqual(receipt.status, .conflict)
            XCTAssertTrue(receipt.errors.first?.contains("split identity") == true)
            XCTAssertEqual(store.saveCount, 0)
        }
    }

    func testConfirmedDayDependenciesRemainFrozenWhileSessionMetadataUpdates() throws {
        let fixture = try ProposalFixture()
        let store = MemoryProposalStore()
        let ledger = EvolutionLedger(store: store)
        _ = try ledger.apply(fixture.proposal, proposalDigest: "digest-1")
        _ = try ledger.apply(.confirmDay("2026-07-17"))
        let frozenDay = try XCTUnwrap(store.document.days.first { $0.date == "2026-07-17" })
        let immutableCapturedAt = try XCTUnwrap(store.document.worktreeEvidence.first?.capturedAt)

        var update = fixture.proposal
        update.jobId = "metadata-update"
        update.sessions[0].title = "更新后的会话标题"
        update.sessions[0].cwd = "/tmp/new-cwd"
        update.sessions[0].updatedAt = proposalDate("2026-07-17T14:00:00Z")
        update.worktreeEvidence[0].capturedAt = immutableCapturedAt.addingTimeInterval(60)
        let receipt = try ledger.apply(update, proposalDigest: "digest-2")

        XCTAssertEqual(receipt.status, .imported)
        XCTAssertTrue(receipt.skippedLockedIds.contains("2026-07-17"))
        XCTAssertEqual(store.document.days.first { $0.date == "2026-07-17" }, frozenDay)
        XCTAssertEqual(store.document.sourceSessions.first { $0.id == update.sessions[0].id }?.title, "更新后的会话标题")
        XCTAssertEqual(store.document.worktreeEvidence.first?.capturedAt, immutableCapturedAt)
    }
}

final class MemoryProposalStore: EvolutionDocumentStore, @unchecked Sendable {
    var document = EvolutionLedgerDocument(
        projects: [],
        days: [],
        nodes: [],
        annotations: [],
        sourceSessions: [],
        worktreeEvidence: [],
        imports: [],
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    var loadCount = 0
    var saveCount = 0

    func load() throws -> EvolutionLedgerDocument {
        loadCount += 1
        return document
    }

    func save(_ document: EvolutionLedgerDocument) throws {
        saveCount += 1
        self.document = document
    }
}
