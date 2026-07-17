import Foundation

public enum ReviewState: String, Codable, Sendable, Hashable { case candidate, confirmed }
public enum ProjectProgressStatus: String, Codable, Sendable, Hashable { case exploring, active, paused, ended }
public enum ProjectEndMode: String, Codable, Sendable, Hashable { case completed, abandoned, replaced }
public enum ArtifactStatus: String, Codable, Sendable, Hashable { case notFormed, pendingValidation, verifiedUsable, inUse, stopped }
public enum ProjectRouteStatus: String, Codable, Sendable, Hashable { case active, paused, stopped, replaced }
public enum ValueKind: String, Codable, Sendable, Hashable { case project, process, crossProject }
public enum ValueRealizationStatus: String, Codable, Sendable, Hashable { case realized, pending, notFormed }
public enum LearningKind: String, Codable, Sendable, Hashable { case mistake, failedAssumption, constraint, reusableMethod }
public enum EvolutionNodeKind: String, Codable, Sendable, Hashable { case purpose, decision, pivot, failedRoute, outcome, statusChange, reflection }
public enum EvolutionNodeOrigin: String, Codable, Sendable, Hashable { case user, assistant, joint }
public enum AnnotationTargetKind: String, Codable, Sendable, Hashable { case day, project, projectDaySlice, evolutionNode, sourceSession }
public enum AnnotationKind: String, Codable, Sendable, Hashable { case supplement, correction, reflection }

public enum EvolutionStableID {
    public static func shortHash(_ parts: [String]) -> String {
        String(ContentHasher.hashParts(parts).prefix(12))
    }

    public static func sourceSession(source: ContextSource, externalThreadId: String) -> String {
        "\(source.rawValue):\(externalThreadId)"
    }

    public static func dailySession(date: String, sessionId: String) -> String {
        "day-source:\(date):\(sessionId)"
    }

    public static func message(source: ContextSource, threadId: String, eventId: String, sourceFile: String, sourceLine: Int, contentHash: String) -> String {
        "message:\(shortHash([source.rawValue, threadId, eventId, sourceFile, String(sourceLine), contentHash]))"
    }

    public static func newProject(normalizedGoal: String) -> String {
        "project:\(shortHash([normalizeProjectGoal(normalizedGoal)]))"
    }

    public static func normalizeProjectGoal(_ goal: String) -> String {
        goal
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    public static func route(projectId: String, name: String, repoPaths: [String]) -> String {
        "route:\(projectId):\(shortHash([name] + repoPaths.sorted()))"
    }

    public static func projectDaySlice(date: String, projectId: String) -> String {
        "slice:\(date):\(projectId)"
    }

    public static func decision(projectDaySliceId: String, decision: String, reason: String) -> String {
        "decision:\(projectDaySliceId):\(shortHash([decision, reason]))"
    }

    public static func learning(projectDaySliceId: String, observation: String, lesson: String) -> String {
        "learning:\(projectDaySliceId):\(shortHash([observation, lesson]))"
    }

    public static func value(projectDaySliceId: String, kind: ValueKind, title: String, detail: String) -> String {
        "value:\(projectDaySliceId):\(kind.rawValue):\(shortHash([title, detail]))"
    }

    public static func independentThought(date: String, title: String, body: String) -> String {
        "thought:\(date):\(shortHash([title, body]))"
    }

    public static func evolutionNode(projectId: String, kind: EvolutionNodeKind, happenedAt: Date, title: String) -> String {
        "node:\(projectId):\(kind.rawValue):\(shortHash([ISO8601Codec.string(from: happenedAt), title]))"
    }

    public static func worktree(
        repoPath: String,
        branch: String,
        head: String,
        verificationStatus: EvidenceVerificationStatus,
        limitation: String?,
        sortedChanges: [String],
        sortedChecks: [String],
        sortedCommits: [String]
    ) -> String {
        let parts = worktreeSemanticParts(
            repoPath: repoPath,
            branch: branch,
            head: head,
            verificationStatus: verificationStatus,
            limitation: limitation,
            sortedChanges: sortedChanges,
            sortedChecks: sortedChecks,
            sortedCommits: sortedCommits
        )
        return "worktree:\(shortHash(parts))"
    }

    public static func worktreeContentHash(
        repoPath: String,
        branch: String,
        head: String,
        verificationStatus: EvidenceVerificationStatus,
        limitation: String?,
        sortedChanges: [String],
        sortedChecks: [String],
        sortedCommits: [String]
    ) -> String {
        ContentHasher.hashParts(worktreeSemanticParts(
            repoPath: repoPath,
            branch: branch,
            head: head,
            verificationStatus: verificationStatus,
            limitation: limitation,
            sortedChanges: sortedChanges,
            sortedChecks: sortedChecks,
            sortedCommits: sortedCommits
        ))
    }

    public static func worktreeFileChange(path: String, kind: WorktreeChangeKind, statusCode: String) -> String {
        "worktree-change:\(shortHash([path, kind.rawValue, statusCode]))"
    }

    public static func verificationCheck(command: [String]) -> String {
        "check:\(shortHash(command))"
    }

    public static func proposalDiagnostic(code: String, message: String, relatedIds: [String]) -> String {
        "diagnostic:\(shortHash([code, message] + relatedIds.sorted()))"
    }

    private static func worktreeSemanticParts(
        repoPath: String,
        branch: String,
        head: String,
        verificationStatus: EvidenceVerificationStatus,
        limitation: String?,
        sortedChanges: [String],
        sortedChecks: [String],
        sortedCommits: [String]
    ) -> [String] {
        [
            "worktree-v2",
            repoPath,
            branch,
            head,
            verificationStatus.rawValue,
            limitation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        ] + sortedChanges.sorted() + sortedChecks.sorted() + sortedCommits.sorted()
    }
}

/// The only canonical digest for the proposal's selected archive facts. Task 6
/// and every producer must call this function instead of reimplementing it.
public enum EvolutionSourceDigest {
    public static func make(
        sourceCutoffAt: Date,
        dateIDs: [String],
        sourceSliceIDs: [String],
        messageIDs: [String]
    ) -> String {
        ContentHasher.hashParts(
            ["proposal-source-v1", ISO8601Codec.string(from: sourceCutoffAt)]
                + Set(dateIDs).sorted()
                + Set(sourceSliceIDs).sorted()
                + Set(messageIDs).sorted()
        )
    }

    public static func make(
        sourceCutoffAt: Date,
        days: [WorkEvolutionDayRecord]
    ) -> String {
        make(
            sourceCutoffAt: sourceCutoffAt,
            dateIDs: days.map(\.id),
            sourceSliceIDs: days.flatMap(\.sourceSlices).map(\.id),
            messageIDs: days.flatMap(\.sourceSlices).flatMap(\.messageReferences).map(\.id)
        )
    }
}

public struct ProjectRoute: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var repoPaths: [String]
    public var startedAt: Date
    public var endedAt: Date?
    public var status: ProjectRouteStatus
    public var reviewState: ReviewState

    public init(id: String, name: String, summary: String, repoPaths: [String], startedAt: Date, endedAt: Date?, status: ProjectRouteStatus, reviewState: ReviewState) {
        self.id = id
        self.name = name
        self.summary = summary
        self.repoPaths = repoPaths
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.reviewState = reviewState
    }
}

public struct EvolutionProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var goal: String
    public var aliases: [String]
    public var routes: [ProjectRoute]
    public var progressStatus: ProjectProgressStatus
    public var endMode: ProjectEndMode?
    public var artifactStatus: ArtifactStatus
    public var reviewState: ReviewState
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, name: String, goal: String, aliases: [String], routes: [ProjectRoute], progressStatus: ProjectProgressStatus, endMode: ProjectEndMode?, artifactStatus: ArtifactStatus, reviewState: ReviewState, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.goal = goal
        self.aliases = aliases
        self.routes = routes
        self.progressStatus = progressStatus
        self.endMode = endMode
        self.artifactStatus = artifactStatus
        self.reviewState = reviewState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DecisionRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var decision: String
    public var reason: String
    public var alternatives: [String]
    public var factLevel: FactLevel
    public var evidenceIds: [String]

    public init(id: String, title: String, decision: String, reason: String, alternatives: [String], factLevel: FactLevel, evidenceIds: [String]) {
        self.id = id
        self.title = title
        self.decision = decision
        self.reason = reason
        self.alternatives = alternatives
        self.factLevel = factLevel
        self.evidenceIds = evidenceIds
    }
}

public struct LearningRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: LearningKind
    public var observation: String
    public var lesson: String
    public var reusablePrinciple: String?
    public var factLevel: FactLevel
    public var evidenceIds: [String]

    public init(id: String, kind: LearningKind, observation: String, lesson: String, reusablePrinciple: String?, factLevel: FactLevel, evidenceIds: [String]) {
        self.id = id
        self.kind = kind
        self.observation = observation
        self.lesson = lesson
        self.reusablePrinciple = reusablePrinciple
        self.factLevel = factLevel
        self.evidenceIds = evidenceIds
    }
}

public struct ValueRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ValueKind
    public var status: ValueRealizationStatus
    public var title: String
    public var detail: String
    public var factLevel: FactLevel
    public var evidenceIds: [String]

    public init(id: String, kind: ValueKind, status: ValueRealizationStatus, title: String, detail: String, factLevel: FactLevel, evidenceIds: [String]) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.factLevel = factLevel
        self.evidenceIds = evidenceIds
    }
}

public struct ProjectDaySlice: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: String
    public var projectId: String
    public var routeIds: [String]
    public var purpose: String
    public var actions: [String]
    public var progress: String
    public var factLevel: FactLevel
    public var decisions: [DecisionRecord]
    public var learnings: [LearningRecord]
    public var values: [ValueRecord]
    public var sourceSliceIds: [String]
    public var evidenceIds: [String]
    public var reviewState: ReviewState

    public init(id: String, date: String, projectId: String, routeIds: [String], purpose: String, actions: [String], progress: String, factLevel: FactLevel, decisions: [DecisionRecord], learnings: [LearningRecord], values: [ValueRecord], sourceSliceIds: [String], evidenceIds: [String], reviewState: ReviewState) {
        self.id = id
        self.date = date
        self.projectId = projectId
        self.routeIds = routeIds
        self.purpose = purpose
        self.actions = actions
        self.progress = progress
        self.factLevel = factLevel
        self.decisions = decisions
        self.learnings = learnings
        self.values = values
        self.sourceSliceIds = sourceSliceIds
        self.evidenceIds = evidenceIds
        self.reviewState = reviewState
    }
}

public struct IndependentThought: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: String
    public var title: String
    public var body: String
    public var factLevel: FactLevel
    public var sourceSliceIds: [String]
    public var evidenceIds: [String]
    public var reviewState: ReviewState
    public var decisions: [DecisionRecord]
    public var learnings: [LearningRecord]
    public var values: [ValueRecord]

    public init(id: String, date: String, title: String, body: String, factLevel: FactLevel, decisions: [DecisionRecord], learnings: [LearningRecord], values: [ValueRecord], sourceSliceIds: [String], evidenceIds: [String], reviewState: ReviewState) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.factLevel = factLevel
        self.decisions = decisions
        self.learnings = learnings
        self.values = values
        self.sourceSliceIds = sourceSliceIds
        self.evidenceIds = evidenceIds
        self.reviewState = reviewState
    }
}

public struct EvolutionNode: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var projectId: String
    public var routeIds: [String]
    public var happenedAt: Date
    public var recognizedAt: Date
    public var kind: EvolutionNodeKind
    public var title: String
    public var detail: String
    public var reason: String
    public var origin: EvolutionNodeOrigin
    public var factLevel: FactLevel
    public var sourceSliceIds: [String]
    public var evidenceIds: [String]
    public var reviewState: ReviewState

    public init(id: String, projectId: String, routeIds: [String], happenedAt: Date, recognizedAt: Date, kind: EvolutionNodeKind, title: String, detail: String, reason: String, origin: EvolutionNodeOrigin, factLevel: FactLevel, sourceSliceIds: [String], evidenceIds: [String], reviewState: ReviewState) {
        self.id = id
        self.projectId = projectId
        self.routeIds = routeIds
        self.happenedAt = happenedAt
        self.recognizedAt = recognizedAt
        self.kind = kind
        self.title = title
        self.detail = detail
        self.reason = reason
        self.origin = origin
        self.factLevel = factLevel
        self.sourceSliceIds = sourceSliceIds
        self.evidenceIds = evidenceIds
        self.reviewState = reviewState
    }
}

public struct AnnotationTarget: Codable, Sendable, Hashable {
    public var kind: AnnotationTargetKind
    public var targetId: String

    public init(kind: AnnotationTargetKind, targetId: String) {
        self.kind = kind
        self.targetId = targetId
    }
}

public struct UserAnnotation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var target: AnnotationTarget
    public var kind: AnnotationKind
    public var body: String
    public var happenedAt: Date?
    public var recognizedAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, target: AnnotationTarget, kind: AnnotationKind, body: String, happenedAt: Date?, recognizedAt: Date, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.target = target
        self.kind = kind
        self.body = body
        self.happenedAt = happenedAt
        self.recognizedAt = recognizedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
