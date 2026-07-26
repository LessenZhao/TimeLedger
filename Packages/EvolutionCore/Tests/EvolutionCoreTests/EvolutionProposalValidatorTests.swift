import Foundation
import XCTest
@testable import EvolutionCore

final class EvolutionProposalValidatorTests: XCTestCase {
    func testValidSeventeenSourceProposalPassesAllCoverageBuckets() throws {
        let fixture = try ProposalFixture()
        try EvolutionProposalValidator().validate(fixture.proposal)

        let coverage = try XCTUnwrap(fixture.proposal.days.first?.coverage)
        let buckets = coverage.includedSessionIds
            + coverage.pendingSessionIds
            + coverage.excludedSessionIds
            + coverage.processorSessionIds
        XCTAssertEqual(coverage.expectedSessionCount, 17)
        XCTAssertEqual(Set(buckets).count, 17)
        XCTAssertEqual(Set(buckets), Set(fixture.proposal.days[0].sourceSlices.map(\.sessionId)))
        XCTAssertEqual(Set(fixture.proposal.days[0].sourceSlices.map(\.classification)), Set(DailySourceClassification.allFixtureCases))
    }

    func testRejectsSchemaCoverageAndSourceIdentityViolations() throws {
        let fixture = try ProposalFixture()

        var wrongSchema = fixture.proposal
        wrongSchema.schemaVersion += 1
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongSchema)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .unsupportedSchema(wrongSchema.schemaVersion))
        }

        var wrongCount = fixture.proposal
        wrongCount.days[0].coverage.expectedSessionCount = 16
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongCount)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .coverageCountMismatch("2026-07-17"))
        }

        var duplicate = fixture.proposal
        duplicate.days[0].coverage.processorSessionIds.append(duplicate.days[0].coverage.includedSessionIds[0])
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(duplicate)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .duplicateCoverageMembership("2026-07-17"))
        }

        var wrongIdentity = fixture.proposal
        wrongIdentity.days[0].sourceSlices.removeLast()
        refreshSourceDigest(&wrongIdentity)
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongIdentity)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .coverageIdentityMismatch("2026-07-17"))
        }
    }

    func testRejectsDatesCutoffStableIDsAndDanglingReferences() throws {
        let fixture = try ProposalFixture()

        var wrongDigest = fixture.proposal
        wrongDigest.sourceDigest = "tampered"
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongDigest)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .sourceDigestMismatch)
        }

        var omittedSource = fixture.proposal
        omittedSource.days[0].sourceSlices.removeLast()
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(omittedSource)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .sourceDigestMismatch)
        }

        var wrongScope = fixture.proposal
        wrongScope.scope.dates = ["2026-07-16"]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongScope))

        var wrongDate = fixture.proposal
        wrongDate.days[0].sourceSlices[0].date = "2026-07-16"
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongDate))

        var afterCutoff = fixture.proposal
        afterCutoff.days[0].sourceSlices[0].messageReferences[0].createdAt = proposalDate("2026-07-17T15:01:00Z")
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(afterCutoff))

        var wrongStableID = fixture.proposal
        wrongStableID.days[0].projectSlices[0].id = "slice:wrong"
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongStableID))

        var danglingRoute = fixture.proposal
        danglingRoute.days[0].projectSlices[0].routeIds = ["route:missing"]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(danglingRoute))

        var danglingEvidence = fixture.proposal
        danglingEvidence.days[0].projectSlices[0].values[0].evidenceIds = ["evidence:missing"]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(danglingEvidence))
    }

    func testRejectsCanonicalMismatchProcessorContributionAndHistoricalOverclaim() throws {
        let fixture = try ProposalFixture()

        var canonicalMismatch = fixture.proposal
        canonicalMismatch.days[0].sourceSlices[0].messageReferences[0].contentHash = "tampered"
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(canonicalMismatch)) {
            guard case .canonicalMessageMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }

        var processorContribution = fixture.proposal
        let processorSlice = try XCTUnwrap(processorContribution.days[0].sourceSlices.first { $0.classification == .processor })
        processorContribution.days[0].projectSlices[0].sourceSliceIds = [processorSlice.id]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(processorContribution)) {
            guard case .ineligibleSourceContribution = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }

        var historical = fixture.proposal
        historical.days[0].projectSlices[0].evidenceIds = [fixture.worktreeId]
        historical.createdAt = proposalDate("2026-07-18T10:00:00Z")
        historical.worktreeEvidence[0].verificationStatus = .verified
        historical.worktreeEvidence[0].limitation = nil
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(historical)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .historicalWorktreeOverclaim(fixture.worktreeId))
        }

        var honestHistorical = fixture.proposal
        honestHistorical.createdAt = proposalDate("2026-07-18T10:00:00Z")
        rekeyWorktree(
            in: &honestHistorical,
            verificationStatus: .partial,
            limitation: "当前工作树不能证明历史未提交内容。"
        )
        try EvolutionProposalValidator().validate(honestHistorical)
    }

    func testRejectsUserAuthoredOrConfirmedProposalContent() throws {
        let fixture = try ProposalFixture()
        var annotation = fixture.proposal
        annotation.userAnnotations = [fixture.annotation]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(annotation)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .proposalContainsUserAnnotations)
        }

        var confirmed = fixture.proposal
        confirmed.projects[0].reviewState = .confirmed
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(confirmed)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .proposalContainsConfirmed("project", fixture.projectId))
        }
    }

    func testAllowsFixedSensitiveExcerptRedactionWithoutDroppingCanonicalReference() throws {
        let fixture = try ProposalFixture()
        var redacted = fixture.proposal
        let originalDigest = redacted.sourceDigest
        redacted.days[0].sourceSlices[0].messageReferences[0].excerpt = MessageReference.sensitiveExcerptRedaction

        XCTAssertEqual(redacted.sourceDigest, originalDigest)
        XCTAssertNoThrow(try EvolutionProposalValidator().validate(redacted))

        var invented = fixture.proposal
        invented.days[0].sourceSlices[0].messageReferences[0].excerpt = "任意伪造摘要"
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(invented)) {
            guard case .canonicalMessageMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }
    }

    func testEvidenceMustBelongToOwnersDeclaredSourceSlices() throws {
        let fixture = try ProposalFixture()
        let thoughtMessage = try XCTUnwrap(
            fixture.proposal.days[0].sourceSlices
                .first { $0.classification == .independentThought }?
                .messageReferences.first?.id
        )

        var projectMismatch = fixture.proposal
        projectMismatch.days[0].projectSlices[0].evidenceIds = [thoughtMessage]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(projectMismatch)) {
            guard case .ownerEvidenceMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }

        var nodeMismatch = fixture.proposal
        nodeMismatch.nodes[0].evidenceIds = [thoughtMessage]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(nodeMismatch)) {
            guard case .ownerEvidenceMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }

        var nodeProjectMismatch = fixture.proposal
        nodeProjectMismatch.nodes[0].projectId = fixture.secondProjectId
        nodeProjectMismatch.nodes[0].routeIds = []
        nodeProjectMismatch.nodes[0].id = EvolutionStableID.evolutionNode(
            projectId: fixture.secondProjectId,
            kind: nodeProjectMismatch.nodes[0].kind,
            happenedAt: nodeProjectMismatch.nodes[0].happenedAt,
            title: nodeProjectMismatch.nodes[0].title
        )
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(nodeProjectMismatch)) {
            guard case .sourceProjectMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }
    }

    func testClassificationProjectIDsAreExactAndReverseDerivedFromProjectSlices() throws {
        let fixture = try ProposalFixture()
        let crossIndex = try XCTUnwrap(
            fixture.proposal.days[0].sourceSlices.firstIndex { $0.classification == .crossProject }
        )

        var wrongCardinality = fixture.proposal
        wrongCardinality.days[0].sourceSlices[crossIndex].projectIds = [fixture.projectId]
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongCardinality)) {
            guard case .classificationCoverageMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }

        var wrongReverseMap = fixture.proposal
        let secondSliceIndex = try XCTUnwrap(
            wrongReverseMap.days[0].projectSlices.firstIndex { $0.projectId == fixture.secondProjectId }
        )
        wrongReverseMap.days[0].projectSlices[secondSliceIndex].sourceSliceIds = []
        wrongReverseMap.days[0].projectSlices[secondSliceIndex].evidenceIds = []
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(wrongReverseMap)) {
            guard case .classificationCoverageMismatch = $0 as? EvolutionProposalValidationError else {
                return XCTFail("unexpected error: \($0)")
            }
        }
    }

    func testWorktreeCaptureAllowsFiveMinuteSkewButRejectsAnythingLater() throws {
        let fixture = try ProposalFixture()
        var allowed = fixture.proposal
        allowed.worktreeEvidence[0].capturedAt = allowed.createdAt.addingTimeInterval(300)
        try EvolutionProposalValidator().validate(allowed)

        var tooLate = fixture.proposal
        tooLate.worktreeEvidence[0].capturedAt = tooLate.createdAt.addingTimeInterval(301)
        XCTAssertThrowsError(try EvolutionProposalValidator().validate(tooLate)) {
            XCTAssertEqual($0 as? EvolutionProposalValidationError, .invalidWorktreeEvidence(fixture.worktreeId))
        }
    }
}

extension DailySourceClassification {
    static let allFixtureCases: [DailySourceClassification] = [
        .project, .crossProject, .independentThought, .pending, .excluded, .processor,
    ]
}

struct ProposalFixture {
    let root: URL
    let eventsURL: URL
    let threadsURL: URL
    let projectId: String
    let secondProjectId: String
    let routeId: String
    let worktreeId: String
    let proposal: EvolutionProposalEnvelope
    let annotation: UserAnnotation

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvolutionProposalFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        eventsURL = root.appendingPathComponent("events.jsonl")
        threadsURL = root.appendingPathComponent("threads.jsonl")
        projectId = EvolutionStableID.newProject(normalizedGoal: "  验证沉淀   闭环 ")
        secondProjectId = EvolutionStableID.newProject(normalizedGoal: "验证跨项目复用")

        var eventLines: [String] = []
        var threadLines: [String] = []
        var sessions: [SourceSessionRecord] = []
        var sourceSlices: [DailySessionSlice] = []
        let classifications: [DailySourceClassification] = [
            .project, .crossProject, .independentThought, .pending, .excluded, .processor,
        ] + Array(repeating: .pending, count: 11)

        for index in 0..<17 {
            let thread = "thread-\(index)"
            let event = "event-\(index)"
            let text = "message \(index)"
            let createdAt = proposalDate(String(format: "2026-07-17T01:%02d:00Z", index))
            let sourceFile = "archive-\(index).jsonl"
            let contentHash = ContentHasher.hash(text)
            let message = MessageReference(
                id: EvolutionStableID.message(source: .codex, threadId: thread, eventId: event, sourceFile: sourceFile, sourceLine: index + 1, contentHash: contentHash),
                source: .codex,
                threadId: thread,
                eventId: event,
                createdAt: createdAt,
                role: .user,
                sourceFile: sourceFile,
                sourceLine: index + 1,
                excerpt: text,
                contentHash: contentHash
            )
            let sessionId = EvolutionStableID.sourceSession(source: .codex, externalThreadId: thread)
            sessions.append(SourceSessionRecord(
                id: sessionId,
                source: .codex,
                externalThreadId: thread,
                title: thread,
                cwd: nil,
                createdAt: createdAt,
                updatedAt: createdAt,
                canonicalEventsPath: eventsURL.path,
                canonicalThreadsPath: threadsURL.path,
                contentHash: ContentHasher.hashParts([message.id])
            ))
            let classification = classifications[index]
            let projectIDs: [String]
            switch classification {
            case .project:
                projectIDs = [projectId]
            case .crossProject:
                projectIDs = [projectId, secondProjectId]
            case .independentThought, .pending, .excluded, .processor:
                projectIDs = []
            }
            sourceSlices.append(DailySessionSlice(
                id: EvolutionStableID.dailySession(date: "2026-07-17", sessionId: sessionId),
                date: "2026-07-17",
                sessionId: sessionId,
                classification: classification,
                projectIds: projectIDs,
                messageReferences: [message],
                exclusionReason: classification == .excluded ? "not work" : nil
            ))
            eventLines.append("{\"event_id\":\"\(event)\",\"thread_id\":\"\(thread)\",\"created_at\":\"\(ISO8601Codec.string(from: createdAt))\",\"role\":\"user\",\"text\":\"\(text)\",\"source_file\":\"\(sourceFile)\",\"source_line\":\(index + 1)}")
            threadLines.append("{\"thread_id\":\"\(thread)\",\"title\":\"\(thread)\"}")
        }
        try Data((eventLines.joined(separator: "\n") + "\n").utf8).write(to: eventsURL)
        try Data((threadLines.joined(separator: "\n") + "\n").utf8).write(to: threadsURL)

        routeId = EvolutionStableID.route(projectId: projectId, name: "轻量路线", repoPaths: ["/tmp/repo"])
        let route = ProjectRoute(
            id: routeId,
            name: "轻量路线",
            summary: "先验证闭环",
            repoPaths: ["/tmp/repo"],
            startedAt: proposalDate("2026-07-17T01:00:00Z"),
            endedAt: nil,
            status: .active,
            reviewState: .candidate
        )
        let project = EvolutionProject(
            id: projectId,
            name: "Fixture",
            goal: "验证沉淀 闭环",
            aliases: [],
            routes: [route],
            progressStatus: .active,
            endMode: nil,
            artifactStatus: .pendingValidation,
            reviewState: .candidate,
            createdAt: proposalDate("2026-07-17T01:00:00Z"),
            updatedAt: proposalDate("2026-07-17T02:00:00Z")
        )
        let secondProject = EvolutionProject(
            id: secondProjectId,
            name: "Cross Project",
            goal: "验证跨项目复用",
            aliases: [],
            routes: [],
            progressStatus: .exploring,
            endMode: nil,
            artifactStatus: .notFormed,
            reviewState: .candidate,
            createdAt: proposalDate("2026-07-17T01:00:00Z"),
            updatedAt: proposalDate("2026-07-17T02:00:00Z")
        )
        let projectSliceId = EvolutionStableID.projectDaySlice(date: "2026-07-17", projectId: projectId)
        let decision = DecisionRecord(
            id: EvolutionStableID.decision(projectDaySliceId: projectSliceId, decision: "采用轻量路线", reason: "降低复杂度"),
            title: "路线选择",
            decision: "采用轻量路线",
            reason: "降低复杂度",
            alternatives: ["桌面重应用"],
            factLevel: .verified,
            evidenceIds: [sourceSlices[0].messageReferences[0].id]
        )
        let learning = LearningRecord(
            id: EvolutionStableID.learning(projectDaySliceId: projectSliceId, observation: "重架构成本高", lesson: "先验证价值闭环"),
            kind: .failedAssumption,
            observation: "重架构成本高",
            lesson: "先验证价值闭环",
            reusablePrinciple: "最少必要架构",
            factLevel: .verified,
            evidenceIds: [sourceSlices[0].messageReferences[0].id]
        )
        let value = ValueRecord(
            id: EvolutionStableID.value(projectDaySliceId: projectSliceId, kind: .project, title: "形成日账本", detail: "可回看当天价值"),
            kind: .project,
            status: .pending,
            title: "形成日账本",
            detail: "可回看当天价值",
            factLevel: .verified,
            evidenceIds: [sourceSlices[0].messageReferences[0].id]
        )
        let projectSlice = ProjectDaySlice(
            id: projectSliceId,
            date: "2026-07-17",
            projectId: projectId,
            routeIds: [routeId],
            purpose: "验证工作价值沉淀",
            actions: ["实现 validator"],
            progress: "完成结构校验",
            factLevel: .verified,
            decisions: [decision],
            learnings: [learning],
            values: [value],
            sourceSliceIds: [sourceSlices[0].id, sourceSlices[1].id],
            evidenceIds: [sourceSlices[0].messageReferences[0].id],
            reviewState: .candidate
        )
        let secondProjectSlice = ProjectDaySlice(
            id: EvolutionStableID.projectDaySlice(date: "2026-07-17", projectId: secondProjectId),
            date: "2026-07-17",
            projectId: secondProjectId,
            routeIds: [],
            purpose: "验证跨项目价值",
            actions: ["关联共同来源"],
            progress: "形成交叉映射",
            factLevel: .verified,
            decisions: [],
            learnings: [],
            values: [],
            sourceSliceIds: [sourceSlices[1].id],
            evidenceIds: [sourceSlices[1].messageReferences[0].id],
            reviewState: .candidate
        )
        let thought = IndependentThought(
            id: EvolutionStableID.independentThought(date: "2026-07-17", title: "跨项目原则", body: "高价值动作必须可回看"),
            date: "2026-07-17",
            title: "跨项目原则",
            body: "高价值动作必须可回看",
            factLevel: .inferred,
            decisions: [],
            learnings: [],
            values: [],
            sourceSliceIds: [sourceSlices[2].id],
            evidenceIds: [sourceSlices[2].messageReferences[0].id],
            reviewState: .candidate
        )
        let change = WorktreeFileChange(
            id: EvolutionStableID.worktreeFileChange(path: "Sources/A.swift", kind: .unstaged, statusCode: "M"),
            path: "Sources/A.swift",
            kind: .unstaged,
            statusCode: "M"
        )
        let check = VerificationCheck(
            id: EvolutionStableID.verificationCheck(command: ["swift", "test"]),
            command: ["swift", "test"],
            status: .passed,
            summary: "passed"
        )
        let changeFingerprint = [change.path, change.kind.rawValue, change.statusCode].joined(separator: "\u{1f}")
        let checkFingerprint = [check.command.joined(separator: "\u{1d}"), check.status.rawValue, check.summary].joined(separator: "\u{1f}")
        worktreeId = EvolutionStableID.worktree(
            repoPath: "/tmp/repo",
            branch: "main",
            head: "abc",
            verificationStatus: .verified,
            limitation: nil,
            sortedChanges: [changeFingerprint],
            sortedChecks: [checkFingerprint],
            sortedCommits: []
        )
        let worktreeContentHash = EvolutionStableID.worktreeContentHash(
            repoPath: "/tmp/repo",
            branch: "main",
            head: "abc",
            verificationStatus: .verified,
            limitation: nil,
            sortedChanges: [changeFingerprint],
            sortedChecks: [checkFingerprint],
            sortedCommits: []
        )
        let worktree = WorktreeEvidenceSnapshot(
            id: worktreeId,
            repoPath: "/tmp/repo",
            branch: "main",
            head: "abc",
            capturedAt: proposalDate("2026-07-17T10:00:00Z"),
            relevantCommits: [],
            changes: [change],
            checks: [check],
            verificationStatus: .verified,
            limitation: nil,
            contentHash: worktreeContentHash
        )
        let included = sourceSlices.filter { [.project, .crossProject, .independentThought].contains($0.classification) }.map(\.sessionId)
        let pending = sourceSlices.filter { $0.classification == .pending }.map(\.sessionId)
        let excluded = sourceSlices.filter { $0.classification == .excluded }.map(\.sessionId)
        let processor = sourceSlices.filter { $0.classification == .processor }.map(\.sessionId)
        let day = WorkEvolutionDayRecord(
            date: "2026-07-17",
            sourceCutoffAt: proposalDate("2026-07-17T15:00:00Z"),
            projectSlices: [projectSlice, secondProjectSlice],
            independentThoughts: [thought],
            sourceSlices: sourceSlices,
            coverage: SourceCoverage(expectedSessionCount: 17, includedSessionIds: included, pendingSessionIds: pending, excludedSessionIds: excluded, processorSessionIds: processor),
            reviewState: .candidate,
            generatedAt: proposalDate("2026-07-17T15:00:00Z"),
            updatedAt: proposalDate("2026-07-17T15:00:00Z")
        )
        let node = EvolutionNode(
            id: EvolutionStableID.evolutionNode(projectId: projectId, kind: .decision, happenedAt: proposalDate("2026-07-17T01:00:00Z"), title: "采用轻量路线"),
            projectId: projectId,
            routeIds: [routeId],
            happenedAt: proposalDate("2026-07-17T01:00:00Z"),
            recognizedAt: proposalDate("2026-07-17T02:00:00Z"),
            kind: .decision,
            title: "采用轻量路线",
            detail: "避免重型架构",
            reason: "先验证闭环",
            origin: .joint,
            factLevel: .verified,
            sourceSliceIds: [sourceSlices[0].id],
            evidenceIds: [sourceSlices[0].messageReferences[0].id, worktreeId],
            reviewState: .candidate
        )
        let sourceCutoffAt = proposalDate("2026-07-17T15:00:00Z")
        proposal = EvolutionProposalEnvelope(
            jobId: "job-1",
            scope: EvolutionProposalScope(kind: .day, dates: ["2026-07-17"]),
            createdAt: proposalDate("2026-07-17T15:00:00Z"),
            sourceCutoffAt: sourceCutoffAt,
            sourceDigest: EvolutionSourceDigest.make(sourceCutoffAt: sourceCutoffAt, days: [day]),
            sessions: sessions,
            days: [day],
            projects: [project, secondProject],
            nodes: [node],
            worktreeEvidence: [worktree],
            userAnnotations: [],
            diagnostics: []
        )
        annotation = UserAnnotation(
            id: "annotation:user",
            target: AnnotationTarget(kind: .project, targetId: projectId),
            kind: .correction,
            body: "用户纠正",
            happenedAt: nil,
            recognizedAt: proposalDate("2026-07-17T15:01:00Z"),
            createdAt: proposalDate("2026-07-17T15:01:00Z"),
            updatedAt: proposalDate("2026-07-17T15:01:00Z")
        )
    }
}

func proposalDate(_ value: String) -> Date {
    ISO8601Codec.date(from: value)!
}

func refreshSourceDigest(_ proposal: inout EvolutionProposalEnvelope) {
    proposal.sourceDigest = EvolutionSourceDigest.make(
        sourceCutoffAt: proposal.sourceCutoffAt,
        days: proposal.days
    )
}

func rekeyWorktree(
    in proposal: inout EvolutionProposalEnvelope,
    verificationStatus: EvidenceVerificationStatus,
    limitation: String?
) {
    var snapshot = proposal.worktreeEvidence[0]
    let oldID = snapshot.id
    let changes = snapshot.changes.map {
        [$0.path, $0.kind.rawValue, $0.statusCode].joined(separator: "\u{1f}")
    }.sorted()
    let checks = snapshot.checks.map {
        [$0.command.joined(separator: "\u{1d}"), $0.status.rawValue, $0.summary]
            .joined(separator: "\u{1f}")
    }.sorted()
    let commits = snapshot.relevantCommits.map {
        [
            $0.repoPath, $0.commitHash, $0.commitMessage,
            String($0.changedFiles), String($0.insertions), String($0.deletions),
            $0.buildStatus ?? "", $0.testStatus ?? "", ISO8601Codec.string(from: $0.capturedAt),
        ].joined(separator: "\u{1f}")
    }.sorted()
    snapshot.verificationStatus = verificationStatus
    snapshot.limitation = limitation
    snapshot.id = EvolutionStableID.worktree(
        repoPath: snapshot.repoPath,
        branch: snapshot.branch,
        head: snapshot.head,
        verificationStatus: verificationStatus,
        limitation: limitation,
        sortedChanges: changes,
        sortedChecks: checks,
        sortedCommits: commits
    )
    snapshot.contentHash = EvolutionStableID.worktreeContentHash(
        repoPath: snapshot.repoPath,
        branch: snapshot.branch,
        head: snapshot.head,
        verificationStatus: verificationStatus,
        limitation: limitation,
        sortedChanges: changes,
        sortedChecks: checks,
        sortedCommits: commits
    )
    proposal.worktreeEvidence[0] = snapshot

    func replaced(_ ids: [String]) -> [String] {
        ids.map { $0 == oldID ? snapshot.id : $0 }
    }
    for dayIndex in proposal.days.indices {
        for sliceIndex in proposal.days[dayIndex].projectSlices.indices {
            proposal.days[dayIndex].projectSlices[sliceIndex].evidenceIds = replaced(
                proposal.days[dayIndex].projectSlices[sliceIndex].evidenceIds
            )
            for index in proposal.days[dayIndex].projectSlices[sliceIndex].decisions.indices {
                proposal.days[dayIndex].projectSlices[sliceIndex].decisions[index].evidenceIds = replaced(
                    proposal.days[dayIndex].projectSlices[sliceIndex].decisions[index].evidenceIds
                )
            }
            for index in proposal.days[dayIndex].projectSlices[sliceIndex].learnings.indices {
                proposal.days[dayIndex].projectSlices[sliceIndex].learnings[index].evidenceIds = replaced(
                    proposal.days[dayIndex].projectSlices[sliceIndex].learnings[index].evidenceIds
                )
            }
            for index in proposal.days[dayIndex].projectSlices[sliceIndex].values.indices {
                proposal.days[dayIndex].projectSlices[sliceIndex].values[index].evidenceIds = replaced(
                    proposal.days[dayIndex].projectSlices[sliceIndex].values[index].evidenceIds
                )
            }
        }
    }
    for index in proposal.nodes.indices {
        proposal.nodes[index].evidenceIds = replaced(proposal.nodes[index].evidenceIds)
    }
}
