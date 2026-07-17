import XCTest
@testable import EvolutionCore

final class WorkEvolutionCodingTests: XCTestCase {
    func testLedgerDocumentRoundTripPreservesTwoAxesAndUserContent() throws {
        let goal = "用最低复杂度管理 Agent Skills"
        let projectId = EvolutionStableID.newProject(normalizedGoal: goal)
        let appRouteId = EvolutionStableID.route(
            projectId: projectId,
            name: "桌面 App",
            repoPaths: ["/tmp/skill-manager-app"]
        )
        let cliRouteId = EvolutionStableID.route(
            projectId: projectId,
            name: "轻量 CLI",
            repoPaths: ["/tmp/skill-manager"]
        )
        let project = EvolutionProject(
            id: projectId,
            name: "Skill Manager",
            goal: goal,
            aliases: ["Skill Manager App"],
            routes: [
                ProjectRoute(
                    id: appRouteId,
                    name: "桌面 App",
                    summary: "初始重架构",
                    repoPaths: ["/tmp/skill-manager-app"],
                    startedAt: date("2026-07-15T08:00:00Z"),
                    endedAt: date("2026-07-16T08:00:00Z"),
                    status: .replaced,
                    reviewState: .confirmed
                ),
                ProjectRoute(
                    id: cliRouteId,
                    name: "轻量 CLI",
                    summary: "替代桌面 App",
                    repoPaths: ["/tmp/skill-manager"],
                    startedAt: date("2026-07-16T08:00:00Z"),
                    endedAt: nil,
                    status: .active,
                    reviewState: .confirmed
                )
            ],
            progressStatus: .active,
            endMode: nil,
            artifactStatus: .pendingValidation,
            reviewState: .candidate,
            createdAt: date("2026-07-16T08:00:00Z"),
            updatedAt: date("2026-07-17T08:00:00Z")
        )
        let day = WorkEvolutionDayRecord(
            date: "2026-07-17",
            sourceCutoffAt: date("2026-07-17T15:00:00Z"),
            projectSlices: [
                ProjectDaySlice(
                    id: EvolutionStableID.projectDaySlice(date: "2026-07-17", projectId: project.id),
                    date: "2026-07-17",
                    projectId: project.id,
                    routeIds: [appRouteId, cliRouteId],
                    purpose: "验证轻架构",
                    actions: ["缩小架构"],
                    progress: "形成可运行 CLI",
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
            generatedAt: date("2026-07-17T15:01:00Z"),
            updatedAt: date("2026-07-17T15:01:00Z")
        )
        let note = UserAnnotation(
            id: "11111111-1111-1111-1111-111111111111",
            target: AnnotationTarget(kind: .day, targetId: day.date),
            kind: .supplement,
            body: "真正价值是降低维护成本",
            happenedAt: nil,
            recognizedAt: date("2026-07-17T16:00:00Z"),
            createdAt: date("2026-07-17T16:00:00Z"),
            updatedAt: date("2026-07-17T16:00:00Z")
        )
        let original = EvolutionLedgerDocument(
            projects: [project],
            days: [day],
            nodes: [],
            annotations: [note],
            sourceSessions: [],
            worktreeEvidence: [],
            imports: [],
            updatedAt: date("2026-07-17T16:00:00Z")
        )

        let data = try ISO8601Codec.encoder.encode(original)
        let decoded = try ISO8601Codec.decoder.decode(EvolutionLedgerDocument.self, from: data)

        XCTAssertEqual(decoded.projects.single?.goal, "用最低复杂度管理 Agent Skills")
        XCTAssertEqual(decoded.days.single?.projectSlices.single?.projectId, project.id)
        XCTAssertEqual(decoded.annotations.single?.body, "真正价值是降低维护成本")
        XCTAssertTrue(decoded.projects.single?.routes.allSatisfy { $0.reviewState == .confirmed } == true)
        XCTAssertEqual(decoded.days.single?.projectSlices.single?.routeIds, [appRouteId, cliRouteId])
        XCTAssertEqual(decoded.days.single?.projectSlices.single?.factLevel, .verified)
        XCTAssertEqual(decoded.schemaVersion, EvolutionSchema.current)
    }

    func testReflectionPreservesHappenedAndRecognizedTimes() throws {
        let reflection = UserAnnotation(
            id: "note:reflection",
            target: AnnotationTarget(kind: .evolutionNode, targetId: "node:1"),
            kind: .reflection,
            body: "桌面 App 路线的复杂度不值得",
            happenedAt: date("2026-07-01T08:00:00Z"),
            recognizedAt: date("2026-07-17T08:00:00Z"),
            createdAt: date("2026-07-17T08:01:00Z"),
            updatedAt: date("2026-07-17T08:01:00Z")
        )

        let data = try ISO8601Codec.encoder.encode(reflection)
        let decoded = try ISO8601Codec.decoder.decode(UserAnnotation.self, from: data)

        XCTAssertEqual(decoded.happenedAt, reflection.happenedAt)
        XCTAssertEqual(decoded.recognizedAt, reflection.recognizedAt)
    }

    func testStableIDsAreDeterministicAndOrderInsensitiveWhereRequired() {
        XCTAssertEqual(
            EvolutionStableID.route(projectId: "project:1", name: "CLI", repoPaths: ["/b", "/a"]),
            EvolutionStableID.route(projectId: "project:1", name: "CLI", repoPaths: ["/a", "/b"])
        )
        XCTAssertEqual(
            EvolutionStableID.sourceSession(source: .codex, externalThreadId: "thread-1"),
            "codex:thread-1"
        )
        XCTAssertEqual(
            EvolutionStableID.projectDaySlice(date: "2026-07-17", projectId: "project:1"),
            "slice:2026-07-17:project:1"
        )
        XCTAssertEqual(
            EvolutionStableID.newProject(normalizedGoal: "  Ship   THE\nLedger "),
            EvolutionStableID.newProject(normalizedGoal: "ship the ledger")
        )
        XCTAssertEqual(
            EvolutionStableID.shortHash(["same", "input"]),
            String(ContentHasher.hashParts(["same", "input"]).prefix(12))
        )
        XCTAssertEqual(
            EvolutionStableID.proposalDiagnostic(code: "coverage", message: "missing", relatedIds: ["b", "a"]),
            EvolutionStableID.proposalDiagnostic(code: "coverage", message: "missing", relatedIds: ["a", "b"])
        )
        XCTAssertEqual(
            EvolutionStableID.worktree(
                repoPath: "/repo",
                branch: "main",
                head: "abc",
                verificationStatus: .partial,
                limitation: "historical",
                sortedChanges: ["b", "a"],
                sortedChecks: ["test", "build"],
                sortedCommits: ["commit-b", "commit-a"]
            ),
            EvolutionStableID.worktree(
                repoPath: "/repo",
                branch: "main",
                head: "abc",
                verificationStatus: .partial,
                limitation: "historical",
                sortedChanges: ["a", "b"],
                sortedChecks: ["build", "test"],
                sortedCommits: ["commit-a", "commit-b"]
            )
        )
        XCTAssertNotEqual(
            EvolutionStableID.value(
                projectDaySliceId: "slice:1",
                kind: .process,
                title: "轻架构",
                detail: "降低复杂度"
            ),
            EvolutionStableID.value(
                projectDaySliceId: "slice:1",
                kind: .process,
                title: "轻架构",
                detail: "只改变文案也应形成不同候选内容 ID"
            )
        )
    }

    private func date(_ iso: String) -> Date {
        guard let value = ISO8601Codec.date(from: iso) else {
            XCTFail("bad date \(iso)")
            return Date()
        }
        return value
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
