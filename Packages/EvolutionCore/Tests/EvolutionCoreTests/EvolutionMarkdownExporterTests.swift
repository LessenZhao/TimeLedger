import Foundation
import XCTest
@testable import EvolutionCore

final class EvolutionMarkdownExporterTests: XCTestCase {
    func testExportsCompleteDailyAndProjectMapsFromOneSnapshot() throws {
        let fixture = try ExportFixture()
        let exporter = EvolutionMarkdownExporter(layout: fixture.layout)

        try exporter.export(snapshot: fixture.snapshot)

        let dailyURL = fixture.layout.dailyMapsDirectoryURL.appendingPathComponent("2026-07-17.md")
        let projectURL = fixture.layout.projectEvolutionsDirectoryURL
            .appendingPathComponent("project-skill-manager-cli.md")
        let daily = try String(contentsOf: dailyURL, encoding: .utf8)
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        XCTAssertTrue(daily.hasPrefix(ExportFixture.derivedWarning))
        XCTAssertTrue(project.hasPrefix(ExportFixture.derivedWarning))

        XCTAssertTrue(daily.contains("Expected sessions: 4"))
        XCTAssertTrue(daily.contains("### Included\n\n- codex:included"))
        XCTAssertTrue(daily.contains("### Pending\n\n- codex:pending"))
        XCTAssertTrue(daily.contains("### Excluded\n\n- codex:excluded"))
        XCTAssertTrue(daily.contains("### Processor\n\n- codex:processor"))
        XCTAssertTrue(daily.contains("Purpose: 验证最小架构"))
        XCTAssertTrue(daily.contains("- 缩小桌面端范围"))
        XCTAssertTrue(daily.contains("Progress: 形成可运行闭环"))
        XCTAssertTrue(daily.contains("Decision: 改成轻量 CLI"))
        XCTAssertTrue(daily.contains("Lesson: 先验证闭环"))
        XCTAssertTrue(daily.contains("### Project Value"))
        XCTAssertTrue(daily.contains("### Process Value"))
        XCTAssertTrue(daily.contains("### Cross-project Value"))
        XCTAssertTrue(daily.contains("## Independent Thoughts"))
        XCTAssertTrue(daily.contains("不要让界面成为真源"))
        XCTAssertTrue(daily.contains("## Evolution Nodes Recognized Today"))
        XCTAssertTrue(daily.contains("轻量路线被确认"))
        XCTAssertTrue(daily.contains("## User Annotations"))
        XCTAssertTrue(daily.contains("真正价值是降低维护成本"))
        XCTAssertTrue(daily.contains("codex:included"))
        XCTAssertTrue(daily.contains("thread-included"))

        XCTAssertTrue(project.contains("Goal: 用最低复杂度管理 Agent Skills"))
        XCTAssertTrue(project.contains("Aliases: Skill Manager App, 技能管理器"))
        XCTAssertTrue(project.contains("Progress status: active"))
        XCTAssertTrue(project.contains("End mode: —"))
        XCTAssertTrue(project.contains("Artifact status: inUse"))
        XCTAssertTrue(project.contains("## Routes"))
        XCTAssertTrue(project.contains("旧桌面 App"))
        XCTAssertTrue(project.contains("轻量 CLI"))
        XCTAssertTrue(project.contains("## Evolution Timeline"))
        XCTAssertLessThan(
            try XCTUnwrap(project.range(of: "桌面路线过重")?.lowerBound),
            try XCTUnwrap(project.range(of: "轻量路线被确认")?.lowerBound)
        )
        XCTAssertTrue(project.contains("## Daily Contributions"))
        XCTAssertTrue(project.contains("## User Annotations"))
        XCTAssertTrue(project.contains("后来确认轻量路线可以复用"))
        XCTAssertFalse(project.contains("不相关项目补充"))
    }

    func testRepeatedAndReorderedExportsAreByteForByteIdentical() throws {
        let fixture = try ExportFixture()
        let exporter = EvolutionMarkdownExporter(layout: fixture.layout)
        let dailyURL = fixture.layout.dailyMapsDirectoryURL.appendingPathComponent("2026-07-17.md")
        let projectURL = fixture.layout.projectEvolutionsDirectoryURL
            .appendingPathComponent("project-skill-manager-cli.md")

        try exporter.export(snapshot: fixture.snapshot)
        let firstDaily = try Data(contentsOf: dailyURL)
        let firstProject = try Data(contentsOf: projectURL)

        var reordered = fixture.snapshot
        reordered.projects.reverse()
        reordered.days.reverse()
        reordered.nodes.reverse()
        reordered.annotations.reverse()
        reordered.sourceSessions.reverse()
        reordered.days[0].projectSlices.reverse()
        reordered.days[0].sourceSlices.reverse()
        reordered.days[0].projectSlices[0].actions.reverse()
        reordered.days[0].projectSlices[0].decisions.reverse()
        reordered.days[0].projectSlices[0].learnings.reverse()
        reordered.days[0].projectSlices[0].values.reverse()

        try exporter.export(snapshot: reordered)

        XCTAssertEqual(try Data(contentsOf: dailyURL), firstDaily)
        XCTAssertEqual(try Data(contentsOf: projectURL), firstProject)
    }

    func testRecognitionOnlyDayGetsItsOwnDailyMap() throws {
        let fixture = try ExportFixture()
        let exporter = EvolutionMarkdownExporter(layout: fixture.layout)
        var snapshot = fixture.snapshot
        snapshot.annotations.append(
            makeAnnotation(
                id: "annotation:recognized-later",
                target: AnnotationTarget(kind: .project, targetId: "project:skill manager/cli"),
                body: "两天后才确认这条原则",
                happenedAt: date("2026-07-17T02:00:00Z"),
                recognizedAt: date("2026-07-19T02:00:00Z"),
                kind: .reflection
            )
        )

        try exporter.export(snapshot: snapshot)

        let happenedDay = try String(
            contentsOf: fixture.layout.dailyMapsDirectoryURL.appendingPathComponent("2026-07-17.md"),
            encoding: .utf8
        )
        let recognizedDay = try String(
            contentsOf: fixture.layout.dailyMapsDirectoryURL.appendingPathComponent("2026-07-19.md"),
            encoding: .utf8
        )

        XCTAssertFalse(happenedDay.contains("两天后才确认这条原则"))
        XCTAssertTrue(recognizedDay.contains("# Daily Map: 2026-07-19"))
        XCTAssertTrue(recognizedDay.contains("Expected sessions: 0"))
        XCTAssertTrue(recognizedDay.contains("两天后才确认这条原则"))
    }
}

private struct ExportFixture {
    static let derivedWarning = "<!-- Derived from records/ledger.json. Edit in TimeLedger, not in this file. -->\n"

    let layout: EvolutionLedgerLayout
    let snapshot: EvolutionSnapshot

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionMarkdownExporterTests-\(UUID().uuidString)", isDirectory: true)
        layout = EvolutionLedgerLayout(rootURL: root)
        let projectID = "project:skill manager/cli"
        let oldRouteID = "route:old"
        let newRouteID = "route:new"
        let project = EvolutionProject(
            id: projectID,
            name: "Skill Manager",
            goal: "用最低复杂度管理 Agent Skills",
            aliases: ["技能管理器", "Skill Manager App"],
            routes: [
                ProjectRoute(id: newRouteID, name: "轻量 CLI", summary: "缩小架构", repoPaths: ["/tmp/skill-manager-cli"], startedAt: date("2026-07-17T01:00:00Z"), endedAt: nil, status: .active, reviewState: .confirmed),
                ProjectRoute(id: oldRouteID, name: "旧桌面 App", summary: "可视化所有 Skill", repoPaths: ["/tmp/skill-manager-app"], startedAt: date("2026-07-01T01:00:00Z"), endedAt: date("2026-07-16T08:00:00Z"), status: .replaced, reviewState: .confirmed),
            ],
            progressStatus: .active,
            endMode: nil,
            artifactStatus: .inUse,
            reviewState: .confirmed,
            createdAt: date("2026-07-01T01:00:00Z"),
            updatedAt: date("2026-07-17T10:00:00Z")
        )
        let sliceID = "slice:2026-07-17:\(projectID)"
        let values = [
            ValueRecord(id: "value:process", kind: .process, status: .realized, title: "最小闭环", detail: "先验证再扩展", factLevel: .inferred, evidenceIds: []),
            ValueRecord(id: "value:cross", kind: .crossProject, status: .realized, title: "跨项目原则", detail: "界面不是真源", factLevel: .inferred, evidenceIds: []),
            ValueRecord(id: "value:project", kind: .project, status: .realized, title: "项目可用", detail: "CLI 已能管理 Skill", factLevel: .verified, evidenceIds: []),
        ]
        let slice = ProjectDaySlice(
            id: sliceID,
            date: "2026-07-17",
            projectId: projectID,
            routeIds: [newRouteID, oldRouteID],
            purpose: "验证最小架构",
            actions: ["核对真实仓库", "缩小桌面端范围"],
            progress: "形成可运行闭环",
            factLevel: .verified,
            decisions: [
                DecisionRecord(id: "decision:b", title: "选择实现", decision: "改成轻量 CLI", reason: "桌面 App 过重", alternatives: ["继续桌面 App"], factLevel: .inferred, evidenceIds: []),
                DecisionRecord(id: "decision:a", title: "保留真源", decision: "JSON 为唯一真源", reason: "避免双向同步", alternatives: [], factLevel: .verified, evidenceIds: []),
            ],
            learnings: [
                LearningRecord(id: "learning:b", kind: .mistake, observation: "一开始架构过重", lesson: "先验证闭环", reusablePrinciple: "先做最少必要架构", factLevel: .inferred, evidenceIds: []),
                LearningRecord(id: "learning:a", kind: .reusableMethod, observation: "会话和仓库互证", lesson: "不能只信总结", reusablePrinciple: nil, factLevel: .verified, evidenceIds: []),
            ],
            values: values,
            sourceSliceIds: ["day-source:included"],
            evidenceIds: [],
            reviewState: .confirmed
        )
        let thought = IndependentThought(
            id: "thought:architecture",
            date: "2026-07-17",
            title: "真源边界",
            body: "不要让界面成为真源",
            factLevel: .selfReported,
            decisions: [],
            learnings: [],
            values: [],
            sourceSliceIds: ["day-source:included"],
            evidenceIds: [],
            reviewState: .confirmed
        )
        let day = WorkEvolutionDayRecord(
            date: "2026-07-17",
            sourceCutoffAt: date("2026-07-17T15:59:00Z"),
            projectSlices: [slice],
            independentThoughts: [thought],
            sourceSlices: [
                DailySessionSlice(id: "day-source:processor", date: "2026-07-17", sessionId: "codex:processor", classification: .processor, projectIds: [], messageReferences: [], exclusionReason: "处理会话"),
                DailySessionSlice(id: "day-source:included", date: "2026-07-17", sessionId: "codex:included", classification: .project, projectIds: [projectID], messageReferences: [], exclusionReason: nil),
                DailySessionSlice(id: "day-source:excluded", date: "2026-07-17", sessionId: "codex:excluded", classification: .excluded, projectIds: [], messageReferences: [], exclusionReason: "纯闲聊"),
                DailySessionSlice(id: "day-source:pending", date: "2026-07-17", sessionId: "codex:pending", classification: .pending, projectIds: [], messageReferences: [], exclusionReason: nil),
            ],
            coverage: SourceCoverage(expectedSessionCount: 4, includedSessionIds: ["codex:included"], pendingSessionIds: ["codex:pending"], excludedSessionIds: ["codex:excluded"], processorSessionIds: ["codex:processor"]),
            reviewState: .confirmed,
            generatedAt: date("2026-07-17T16:00:00Z"),
            updatedAt: date("2026-07-17T16:00:00Z")
        )
        let oldNode = EvolutionNode(id: "node:old", projectId: projectID, routeIds: [oldRouteID], happenedAt: date("2026-07-10T01:00:00Z"), recognizedAt: date("2026-07-10T01:00:00Z"), kind: .failedRoute, title: "桌面路线过重", detail: "维护成本超过价值", reason: "界面和同步复杂", origin: .joint, factLevel: .verified, sourceSliceIds: [], evidenceIds: [], reviewState: .confirmed)
        let recognizedNode = EvolutionNode(id: "node:new", projectId: projectID, routeIds: [newRouteID], happenedAt: date("2026-07-17T02:00:00Z"), recognizedAt: date("2026-07-17T03:00:00Z"), kind: .pivot, title: "轻量路线被确认", detail: "转为 CLI", reason: "更适合个人使用", origin: .joint, factLevel: .verified, sourceSliceIds: ["day-source:included"], evidenceIds: [], reviewState: .confirmed)
        let dailyAnnotation = makeAnnotation(id: "annotation:day", target: AnnotationTarget(kind: .day, targetId: day.date), body: "真正价值是降低维护成本", recognizedAt: date("2026-07-17T08:00:00Z"))
        let projectAnnotation = makeAnnotation(id: "annotation:project", target: AnnotationTarget(kind: .project, targetId: projectID), body: "后来确认轻量路线可以复用", happenedAt: date("2026-07-17T02:00:00Z"), recognizedAt: date("2026-07-17T09:00:00Z"), kind: .reflection)
        let unrelated = makeAnnotation(id: "annotation:other", target: AnnotationTarget(kind: .project, targetId: "project:other"), body: "不相关项目补充", recognizedAt: date("2026-07-17T10:00:00Z"))
        let sourceSession = SourceSessionRecord(id: "codex:included", source: .codex, externalThreadId: "thread-included", title: "Skill Manager 实现", cwd: "/tmp/skill-manager-cli", createdAt: date("2026-07-17T00:00:00Z"), updatedAt: date("2026-07-17T12:00:00Z"), canonicalEventsPath: "/archive/events.jsonl", canonicalThreadsPath: "/archive/threads.jsonl", contentHash: "source")

        snapshot = EvolutionSnapshot(
            projects: [project],
            days: [day],
            nodes: [recognizedNode, oldNode],
            annotations: [unrelated, projectAnnotation, dailyAnnotation],
            sourceSessions: [sourceSession],
            worktreeEvidence: []
        )
    }

}

private func makeAnnotation(id: String, target: AnnotationTarget, body: String, happenedAt: Date? = nil, recognizedAt: Date, kind: AnnotationKind = .supplement) -> UserAnnotation {
    UserAnnotation(id: id, target: target, kind: kind, body: body, happenedAt: happenedAt, recognizedAt: recognizedAt, createdAt: recognizedAt, updatedAt: recognizedAt)
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
