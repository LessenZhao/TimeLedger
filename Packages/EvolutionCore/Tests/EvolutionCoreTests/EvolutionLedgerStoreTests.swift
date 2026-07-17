import Foundation
import XCTest
@testable import EvolutionCore

final class EvolutionLedgerStoreTests: XCTestCase {
    func testMissingLedgerLoadsDeterministicEmptyDocument() throws {
        let fixture = try StoreFixture()
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)

        let document = try store.load()

        XCTAssertEqual(document.schemaVersion, EvolutionSchema.current)
        XCTAssertEqual(document.projects, [])
        XCTAssertEqual(document.days, [])
        XCTAssertEqual(document.nodes, [])
        XCTAssertEqual(document.annotations, [])
        XCTAssertEqual(document.sourceSessions, [])
        XCTAssertEqual(document.worktreeEvidence, [])
        XCTAssertEqual(document.imports, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.layout.ledgerFileURL.path))
    }

    func testSaveAndReloadPreservesEveryAuthoritativeArray() throws {
        let fixture = try StoreFixture()
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)
        let original = makeDocument()

        try store.save(original)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded, original)
    }

    func testCorruptLedgerThrowsWithoutReplacingOriginalBytes() throws {
        let fixture = try StoreFixture()
        try fixture.layout.ensureDirectories()
        let corrupt = Data("{ definitely-not-json".utf8)
        try corrupt.write(to: fixture.layout.ledgerFileURL)
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fixture.layout.ledgerFileURL), corrupt)
    }

    func testAtomicSaveLeavesOnlyLedgerJSONInRecordsDirectory() throws {
        let fixture = try StoreFixture()
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)

        try store.save(makeDocument())

        let names = try FileManager.default.contentsOfDirectory(
            at: fixture.layout.recordsDirectoryURL,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
        XCTAssertEqual(names, ["ledger.json"])
    }

    func testSaveCanonicalizesTopLevelOrderingToReduceMeaninglessDiffs() throws {
        let fixture = try StoreFixture()
        let store = JSONEvolutionDocumentStore(layout: fixture.layout)
        var document = makeDocument()
        let earlierProject = makeProject(id: "project:a", name: "Alpha")
        let laterDay = makeDay(date: "2026-07-18", projectId: document.projects[0].id)
        let earlierNode = makeNode(
            id: "node:earlier",
            projectId: document.projects[0].id,
            happenedAt: date("2026-05-01T00:00:00Z"),
            recognizedAt: date("2026-07-18T00:00:00Z")
        )
        document.projects.insert(earlierProject, at: 0)
        document.days.insert(laterDay, at: 0)
        document.nodes.insert(earlierNode, at: 0)

        try store.save(document)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.projects.map(\.name), ["Alpha", "Skill Manager"])
        XCTAssertEqual(reloaded.days.map(\.date), ["2026-07-17", "2026-07-18"])
        XCTAssertEqual(reloaded.nodes.map(\.id), ["node:earlier", "node:1"])
    }
}

private struct StoreFixture {
    let rootURL: URL
    let layout: EvolutionLedgerLayout

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionLedgerStoreTests-\(UUID().uuidString)", isDirectory: true)
        layout = EvolutionLedgerLayout(rootURL: rootURL)
    }
}

private func makeDocument() -> EvolutionLedgerDocument {
    let project = makeProject(id: "project:1", name: "Skill Manager")
    let day = makeDay(date: "2026-07-17", projectId: project.id)
    let node = makeNode(
        id: "node:1",
        projectId: project.id,
        happenedAt: date("2026-06-01T01:00:00Z"),
        recognizedAt: date("2026-07-17T01:00:00Z")
    )
    let annotation = UserAnnotation(
        id: "annotation:1",
        target: AnnotationTarget(kind: .project, targetId: project.id),
        kind: .supplement,
        body: "用户补充不会丢",
        happenedAt: nil,
        recognizedAt: date("2026-07-17T02:00:00Z"),
        createdAt: date("2026-07-17T02:00:00Z"),
        updatedAt: date("2026-07-17T02:00:00Z")
    )
    let session = SourceSessionRecord(
        id: "codex:thread-1",
        source: .codex,
        externalThreadId: "thread-1",
        title: "实现 Skill Manager",
        cwd: "/tmp/skill-manager",
        createdAt: date("2026-07-17T00:00:00Z"),
        updatedAt: date("2026-07-17T01:00:00Z"),
        canonicalEventsPath: "/tmp/archive/events.jsonl",
        canonicalThreadsPath: "/tmp/archive/threads-index.jsonl",
        contentHash: "session-hash"
    )
    let evidence = WorktreeEvidenceSnapshot(
        id: "worktree:1",
        repoPath: "/tmp/skill-manager",
        branch: "main",
        head: "abc123",
        capturedAt: date("2026-07-17T03:00:00Z"),
        relevantCommits: [],
        changes: [],
        checks: [],
        verificationStatus: .partial,
        limitation: "无法证明历史未提交状态",
        contentHash: "worktree-hash"
    )
    let receipt = ImportReceipt(
        jobId: "job:1",
        proposalDigest: "proposal-hash",
        status: .imported,
        acceptedDayIds: [day.date],
        skippedLockedIds: [],
        warnings: [],
        errors: [],
        importedAt: date("2026-07-17T04:00:00Z")
    )
    return EvolutionLedgerDocument(
        projects: [project],
        days: [day],
        nodes: [node],
        annotations: [annotation],
        sourceSessions: [session],
        worktreeEvidence: [evidence],
        imports: [receipt],
        updatedAt: date("2026-07-17T05:00:00Z")
    )
}

private func makeProject(id: String, name: String) -> EvolutionProject {
    EvolutionProject(
        id: id,
        name: name,
        goal: "降低复杂度",
        aliases: [],
        routes: [],
        progressStatus: .active,
        endMode: nil,
        artifactStatus: .pendingValidation,
        reviewState: .candidate,
        createdAt: date("2026-06-01T00:00:00Z"),
        updatedAt: date("2026-07-17T00:00:00Z")
    )
}

private func makeDay(date key: String, projectId: String) -> WorkEvolutionDayRecord {
    WorkEvolutionDayRecord(
        date: key,
        sourceCutoffAt: date("2026-07-18T00:00:00Z"),
        projectSlices: [
            ProjectDaySlice(
                id: "slice:\(key):\(projectId)",
                date: key,
                projectId: projectId,
                routeIds: [],
                purpose: "验证轻架构",
                actions: ["缩小架构"],
                progress: "形成最小闭环",
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

private func makeNode(id: String, projectId: String, happenedAt: Date, recognizedAt: Date) -> EvolutionNode {
    EvolutionNode(
        id: id,
        projectId: projectId,
        routeIds: [],
        happenedAt: happenedAt,
        recognizedAt: recognizedAt,
        kind: .reflection,
        title: "后来认识到复杂度过高",
        detail: "改为轻量路线",
        reason: "维护成本超过收益",
        origin: .joint,
        factLevel: .verified,
        sourceSliceIds: [],
        evidenceIds: [],
        reviewState: .candidate
    )
}

private func date(_ value: String) -> Date {
    ISO8601Codec.date(from: value)!
}
