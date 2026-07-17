import Foundation

public enum EvolutionProposalScopeKind: String, Codable, Sendable, Hashable { case day, history }

public struct EvolutionProposalScope: Codable, Sendable, Hashable {
    public var kind: EvolutionProposalScopeKind
    public var dates: [String]

    public init(kind: EvolutionProposalScopeKind, dates: [String]) {
        self.kind = kind
        self.dates = dates
    }
}

public enum ProposalDiagnosticSeverity: String, Codable, Sendable, Hashable { case info, warning, error }

public struct ProposalDiagnostic: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var severity: ProposalDiagnosticSeverity
    public var code: String
    public var message: String
    public var relatedIds: [String]

    public init(id: String, severity: ProposalDiagnosticSeverity, code: String, message: String, relatedIds: [String]) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.relatedIds = relatedIds
    }
}

public enum ImportReceiptStatus: String, Codable, Sendable, Hashable { case imported, noOp, conflict, rejected }

public struct ImportReceipt: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(jobId):\(proposalDigest)" }
    public var jobId: String
    public var proposalDigest: String
    public var status: ImportReceiptStatus
    public var acceptedDayIds: [String]
    public var skippedLockedIds: [String]
    public var warnings: [String]
    public var errors: [String]
    public var importedAt: Date

    public init(jobId: String, proposalDigest: String, status: ImportReceiptStatus, acceptedDayIds: [String], skippedLockedIds: [String], warnings: [String], errors: [String], importedAt: Date) {
        self.jobId = jobId
        self.proposalDigest = proposalDigest
        self.status = status
        self.acceptedDayIds = acceptedDayIds
        self.skippedLockedIds = skippedLockedIds
        self.warnings = warnings
        self.errors = errors
        self.importedAt = importedAt
    }
}

public struct EvolutionProposalEnvelope: Codable, Sendable, Hashable, Identifiable {
    public var id: String { jobId }
    public var schemaVersion: Int
    public var jobId: String
    public var scope: EvolutionProposalScope
    public var createdAt: Date
    public var sourceCutoffAt: Date
    public var sourceDigest: String
    public var sessions: [SourceSessionRecord]
    public var days: [WorkEvolutionDayRecord]
    public var projects: [EvolutionProject]
    public var nodes: [EvolutionNode]
    public var worktreeEvidence: [WorktreeEvidenceSnapshot]
    public var userAnnotations: [UserAnnotation]
    public var diagnostics: [ProposalDiagnostic]

    public init(schemaVersion: Int = EvolutionSchema.current, jobId: String, scope: EvolutionProposalScope, createdAt: Date, sourceCutoffAt: Date, sourceDigest: String, sessions: [SourceSessionRecord], days: [WorkEvolutionDayRecord], projects: [EvolutionProject], nodes: [EvolutionNode], worktreeEvidence: [WorktreeEvidenceSnapshot], userAnnotations: [UserAnnotation], diagnostics: [ProposalDiagnostic]) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.scope = scope
        self.createdAt = createdAt
        self.sourceCutoffAt = sourceCutoffAt
        self.sourceDigest = sourceDigest
        self.sessions = sessions
        self.days = days
        self.projects = projects
        self.nodes = nodes
        self.worktreeEvidence = worktreeEvidence
        self.userAnnotations = userAnnotations
        self.diagnostics = diagnostics
    }
}

public struct EvolutionLedgerDocument: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var projects: [EvolutionProject]
    public var days: [WorkEvolutionDayRecord]
    public var nodes: [EvolutionNode]
    public var annotations: [UserAnnotation]
    public var sourceSessions: [SourceSessionRecord]
    public var worktreeEvidence: [WorktreeEvidenceSnapshot]
    public var imports: [ImportReceipt]
    public var updatedAt: Date

    public init(schemaVersion: Int = EvolutionSchema.current, projects: [EvolutionProject], days: [WorkEvolutionDayRecord], nodes: [EvolutionNode], annotations: [UserAnnotation], sourceSessions: [SourceSessionRecord], worktreeEvidence: [WorktreeEvidenceSnapshot], imports: [ImportReceipt], updatedAt: Date) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.days = days
        self.nodes = nodes
        self.annotations = annotations
        self.sourceSessions = sourceSessions
        self.worktreeEvidence = worktreeEvidence
        self.imports = imports
        self.updatedAt = updatedAt
    }
}
