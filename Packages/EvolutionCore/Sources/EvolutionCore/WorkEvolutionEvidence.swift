import Foundation

public enum DailySourceClassification: String, Codable, Sendable, Hashable { case project, crossProject, independentThought, pending, excluded, processor }
public enum EvidenceVerificationStatus: String, Codable, Sendable, Hashable { case verified, partial, unverified, failed }
public enum WorktreeChangeKind: String, Codable, Sendable, Hashable { case staged, unstaged, untracked }
public enum VerificationCheckStatus: String, Codable, Sendable, Hashable { case passed, failed, notRun }

public struct MessageReference: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var source: ContextSource
    public var threadId: String
    public var eventId: String
    public var createdAt: Date
    public var role: ContextMessageRole
    public var sourceFile: String
    public var sourceLine: Int
    public var excerpt: String
    public var contentHash: String

    public init(id: String, source: ContextSource, threadId: String, eventId: String, createdAt: Date, role: ContextMessageRole, sourceFile: String, sourceLine: Int, excerpt: String, contentHash: String) {
        self.id = id
        self.source = source
        self.threadId = threadId
        self.eventId = eventId
        self.createdAt = createdAt
        self.role = role
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        self.excerpt = excerpt
        self.contentHash = contentHash
    }
}

public struct SourceSessionRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var source: ContextSource
    public var externalThreadId: String
    public var title: String
    public var cwd: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var canonicalEventsPath: String
    public var canonicalThreadsPath: String
    public var contentHash: String

    public init(id: String, source: ContextSource, externalThreadId: String, title: String, cwd: String?, createdAt: Date, updatedAt: Date, canonicalEventsPath: String, canonicalThreadsPath: String, contentHash: String) {
        self.id = id
        self.source = source
        self.externalThreadId = externalThreadId
        self.title = title
        self.cwd = cwd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canonicalEventsPath = canonicalEventsPath
        self.canonicalThreadsPath = canonicalThreadsPath
        self.contentHash = contentHash
    }
}

public struct DailySessionSlice: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: String
    public var sessionId: String
    public var classification: DailySourceClassification
    public var projectIds: [String]
    public var messageReferences: [MessageReference]
    public var exclusionReason: String?

    public init(id: String, date: String, sessionId: String, classification: DailySourceClassification, projectIds: [String], messageReferences: [MessageReference], exclusionReason: String?) {
        self.id = id
        self.date = date
        self.sessionId = sessionId
        self.classification = classification
        self.projectIds = projectIds
        self.messageReferences = messageReferences
        self.exclusionReason = exclusionReason
    }
}

public struct SourceCoverage: Codable, Sendable, Hashable {
    public var expectedSessionCount: Int
    public var includedSessionIds: [String]
    public var pendingSessionIds: [String]
    public var excludedSessionIds: [String]
    public var processorSessionIds: [String]

    public init(expectedSessionCount: Int, includedSessionIds: [String], pendingSessionIds: [String], excludedSessionIds: [String], processorSessionIds: [String]) {
        self.expectedSessionCount = expectedSessionCount
        self.includedSessionIds = includedSessionIds
        self.pendingSessionIds = pendingSessionIds
        self.excludedSessionIds = excludedSessionIds
        self.processorSessionIds = processorSessionIds
    }
}

public struct WorkEvolutionDayRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { date }
    public var date: String
    public var sourceCutoffAt: Date
    public var projectSlices: [ProjectDaySlice]
    public var independentThoughts: [IndependentThought]
    public var sourceSlices: [DailySessionSlice]
    public var coverage: SourceCoverage
    public var reviewState: ReviewState
    public var generatedAt: Date
    public var updatedAt: Date

    public init(date: String, sourceCutoffAt: Date, projectSlices: [ProjectDaySlice], independentThoughts: [IndependentThought], sourceSlices: [DailySessionSlice], coverage: SourceCoverage, reviewState: ReviewState, generatedAt: Date, updatedAt: Date) {
        self.date = date
        self.sourceCutoffAt = sourceCutoffAt
        self.projectSlices = projectSlices
        self.independentThoughts = independentThoughts
        self.sourceSlices = sourceSlices
        self.coverage = coverage
        self.reviewState = reviewState
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }
}

public struct WorktreeFileChange: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var kind: WorktreeChangeKind
    public var statusCode: String

    public init(id: String, path: String, kind: WorktreeChangeKind, statusCode: String) {
        self.id = id
        self.path = path
        self.kind = kind
        self.statusCode = statusCode
    }
}

public struct VerificationCheck: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var command: [String]
    public var status: VerificationCheckStatus
    public var summary: String

    public init(id: String, command: [String], status: VerificationCheckStatus, summary: String) {
        self.id = id
        self.command = command
        self.status = status
        self.summary = summary
    }
}

public struct WorktreeEvidenceSnapshot: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var repoPath: String
    public var branch: String
    public var head: String
    public var capturedAt: Date
    public var relevantCommits: [GitEvidenceSummary]
    public var changes: [WorktreeFileChange]
    public var checks: [VerificationCheck]
    public var verificationStatus: EvidenceVerificationStatus
    public var limitation: String?
    public var contentHash: String

    public init(id: String, repoPath: String, branch: String, head: String, capturedAt: Date, relevantCommits: [GitEvidenceSummary], changes: [WorktreeFileChange], checks: [VerificationCheck], verificationStatus: EvidenceVerificationStatus, limitation: String?, contentHash: String) {
        self.id = id
        self.repoPath = repoPath
        self.branch = branch
        self.head = head
        self.capturedAt = capturedAt
        self.relevantCommits = relevantCommits
        self.changes = changes
        self.checks = checks
        self.verificationStatus = verificationStatus
        self.limitation = limitation
        self.contentHash = contentHash
    }
}

public struct EvolutionPrepareRequest: Codable, Sendable, Hashable {
    public var date: String
    public var timeZoneIdentifier: String
    public var cutoffAt: Date
    public var archives: [SourceArchiveLocation]
    public var explicitProcessorThreadIds: [String]

    public init(
        date: String,
        timeZoneIdentifier: String,
        cutoffAt: Date,
        archives: [SourceArchiveLocation],
        explicitProcessorThreadIds: [String]
    ) {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.cutoffAt = cutoffAt
        self.archives = archives
        self.explicitProcessorThreadIds = explicitProcessorThreadIds
    }

    fileprivate var stableFingerprint: [String] {
        let archiveParts = archives.map {
            [$0.source.rawValue, $0.eventsPath, $0.threadsPath].joined(separator: "\u{1f}")
        }.sorted()
        return [
            "prepare-request-v1",
            date,
            timeZoneIdentifier,
            ISO8601Codec.string(from: cutoffAt),
        ] + archiveParts + explicitProcessorThreadIds.sorted()
    }
}

public struct EvidenceBundle: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var jobId: String
    public var request: EvolutionPrepareRequest
    public var archiveDays: [PreparedArchiveDay]
    public var worktrees: [WorktreeEvidenceSnapshot]
    public var diagnostics: [ProposalDiagnostic]
    public var sourceDigest: String
    public var contentHash: String

    public init(
        schemaVersion: Int = EvolutionSchema.current,
        jobId: String,
        request: EvolutionPrepareRequest,
        archiveDays: [PreparedArchiveDay],
        worktrees: [WorktreeEvidenceSnapshot],
        diagnostics: [ProposalDiagnostic],
        sourceDigest: String,
        contentHash: String
    ) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.request = request
        self.archiveDays = archiveDays
        self.worktrees = worktrees
        self.diagnostics = diagnostics
        self.sourceDigest = sourceDigest
        self.contentHash = contentHash
    }

    public func recomputedContentHash() -> String {
        let diagnosticParts = diagnostics.map {
            [$0.severity.rawValue, $0.code, $0.message] + $0.relatedIds.sorted()
        }.map { $0.joined(separator: "\u{1f}") }.sorted()
        let archiveParts = archiveDays.flatMap(Self.archiveFingerprints).sorted()
        let worktreeParts = worktrees.map {
            [
                $0.contentHash,
                ISO8601Codec.string(from: $0.capturedAt),
            ].joined(separator: "\u{1f}")
        }.sorted()
        return ContentHasher.hashParts(
            ["evidence-bundle-v1", String(schemaVersion), jobId]
                + request.stableFingerprint
                + [sourceDigest]
                + archiveParts
                + worktreeParts
                + diagnosticParts
        )
    }

    private static func archiveFingerprints(_ day: PreparedArchiveDay) -> [String] {
        var parts = ["archive-day\u{1f}\(day.date)\u{1f}\(day.sourceDigest)"]
        parts += day.sessions.map { session in
            [
                "session", session.id, session.source.rawValue, session.externalThreadId,
                session.title, session.cwd ?? "", ISO8601Codec.string(from: session.createdAt),
                ISO8601Codec.string(from: session.updatedAt), session.canonicalEventsPath,
                session.canonicalThreadsPath, session.contentHash,
            ].joined(separator: "\u{1f}")
        }
        parts += day.slices.map { slice in
            [
                "slice", slice.id, slice.date, slice.sessionId, slice.classification.rawValue,
                slice.projectIds.sorted().joined(separator: "\u{1d}"), slice.exclusionReason ?? "",
                slice.messageReferences.map(\.id).sorted().joined(separator: "\u{1d}"),
            ].joined(separator: "\u{1f}")
        }
        parts += day.messages.map { message in
            [
                "message", message.id, ISO8601Codec.string(from: message.reference.createdAt),
                message.reference.role.rawValue, message.reference.contentHash,
            ].joined(separator: "\u{1f}")
        }
        parts.append([
            "coverage", String(day.coverage.expectedSessionCount),
            day.coverage.includedSessionIds.sorted().joined(separator: "\u{1d}"),
            day.coverage.pendingSessionIds.sorted().joined(separator: "\u{1d}"),
            day.coverage.excludedSessionIds.sorted().joined(separator: "\u{1d}"),
            day.coverage.processorSessionIds.sorted().joined(separator: "\u{1d}"),
        ].joined(separator: "\u{1f}"))
        return parts
    }
}
