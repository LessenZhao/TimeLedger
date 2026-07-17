import CryptoKit
import EvolutionCore
import Foundation

public enum EvolutionProposalInboxError: Error, Sendable, Equatable {
    case processedConflict(String)
}

extension EvolutionProposalInboxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .processedConflict(let jobId):
            return "processed 已存在不同内容，未覆盖：\(jobId)。"
        }
    }
}

/// Crash-safe adapter between Codex's proposal exchange folder and the
/// authoritative EvolutionLedger. All semantic validation and merge rules stay
/// in EvolutionCore; this type only establishes package trust and I/O ordering.
public struct EvolutionProposalInbox: @unchecked Sendable {
    public let layout: EvolutionLedgerLayout

    private let ledger: EvolutionLedger
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        layout: EvolutionLedgerLayout,
        ledger: EvolutionLedger,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.layout = layout
        self.ledger = ledger
        self.fileManager = fileManager
        self.now = now
    }

    public func importPending() throws -> [ImportReceipt] {
        lock.lock()
        defer { lock.unlock() }

        try layout.ensureDirectories(fileManager: fileManager)
        let pending = try fileManager.contentsOfDirectory(
            at: layout.inboxDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            guard url.pathExtension.lowercased() == "json" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try pending.map(importOne)
    }

    public static func proposalDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func importOne(_ inboxURL: URL) throws -> ImportReceipt {
        let filenameJobId = inboxURL.deletingPathExtension().lastPathComponent
        let processedURL = layout.processedDirectoryURL.appendingPathComponent(inboxURL.lastPathComponent)
        let proposalData = try Data(contentsOf: inboxURL)
        let proposalDigest = Self.proposalDigest(for: proposalData)
        let processedAlreadyContainsSameBytes = try preflightProcessedDestination(
            processedURL,
            incomingData: proposalData,
            jobId: filenameJobId
        )

        let proposal: EvolutionProposalEnvelope
        do {
            proposal = try ISO8601Codec.decoder.decode(EvolutionProposalEnvelope.self, from: proposalData)
        } catch {
            return try rejectAndFinish(
                jobId: filenameJobId,
                proposalDigest: proposalDigest,
                reason: "proposal decode failed: \(error.localizedDescription)",
                inboxURL: inboxURL,
                processedURL: processedURL,
                processedAlreadyContainsSameBytes: processedAlreadyContainsSameBytes
            )
        }

        do {
            try verifyJobTrust(
                filenameJobId: filenameJobId,
                proposal: proposal
            )
        } catch {
            return try rejectAndFinish(
                jobId: filenameJobId,
                proposalDigest: proposalDigest,
                reason: error.localizedDescription,
                inboxURL: inboxURL,
                processedURL: processedURL,
                processedAlreadyContainsSameBytes: processedAlreadyContainsSameBytes
            )
        }

        let receipt: ImportReceipt
        do {
            receipt = try ledger.apply(proposal, proposalDigest: proposalDigest)
        } catch let error as EvolutionProposalValidationError {
            return try rejectAndFinish(
                jobId: filenameJobId,
                proposalDigest: proposalDigest,
                reason: error.localizedDescription,
                inboxURL: inboxURL,
                processedURL: processedURL,
                processedAlreadyContainsSameBytes: processedAlreadyContainsSameBytes
            )
        }

        // Ledger is authoritative before the receipt. A crash after this point is
        // recovered by EvolutionLedger's persisted jobId + digest idempotency.
        try writeReceipt(receipt, jobId: filenameJobId)
        try finishMove(
            inboxURL: inboxURL,
            processedURL: processedURL,
            processedAlreadyContainsSameBytes: processedAlreadyContainsSameBytes
        )
        return receipt
    }

    private func verifyJobTrust(
        filenameJobId: String,
        proposal: EvolutionProposalEnvelope
    ) throws {
        guard proposal.jobId == filenameJobId else {
            throw PackageTrustError.jobIdMismatch(
                filename: filenameJobId,
                proposal: proposal.jobId,
                evidence: nil
            )
        }
        let evidenceURL = layout.jobsDirectoryURL
            .appendingPathComponent(filenameJobId, isDirectory: true)
            .appendingPathComponent("evidence.json")
        let evidenceData: Data
        do {
            evidenceData = try Data(contentsOf: evidenceURL)
        } catch {
            throw PackageTrustError.missingEvidence(filenameJobId)
        }
        let evidence: EvidenceBundle
        do {
            evidence = try ISO8601Codec.decoder.decode(EvidenceBundle.self, from: evidenceData)
        } catch {
            throw PackageTrustError.invalidEvidence(filenameJobId)
        }
        guard evidence.jobId == filenameJobId,
              evidence.jobId == proposal.jobId else {
            throw PackageTrustError.jobIdMismatch(
                filename: filenameJobId,
                proposal: proposal.jobId,
                evidence: evidence.jobId
            )
        }
        guard evidence.schemaVersion == EvolutionSchema.current else {
            throw PackageTrustError.unsupportedEvidenceSchema(evidence.schemaVersion)
        }
        guard evidence.contentHash == evidence.recomputedContentHash() else {
            throw PackageTrustError.evidenceContentHashMismatch(filenameJobId)
        }
        guard proposal.sourceDigest == evidence.sourceDigest else {
            throw PackageTrustError.sourceDigestMismatch(filenameJobId)
        }
        let proposalSessions = proposal.sessions.sorted { $0.id < $1.id }
        let evidenceSessions = evidence.archiveDays.flatMap(\.sessions).sorted { $0.id < $1.id }
        guard proposalSessions == evidenceSessions else {
            throw PackageTrustError.proposalSessionsMismatch(filenameJobId)
        }
        guard proposal.worktreeEvidence.sorted(by: { $0.id < $1.id })
            == evidence.worktrees.sorted(by: { $0.id < $1.id }) else {
            throw PackageTrustError.proposalWorktreesMismatch(filenameJobId)
        }
    }

    private func rejectAndFinish(
        jobId: String,
        proposalDigest: String,
        reason: String,
        inboxURL: URL,
        processedURL: URL,
        processedAlreadyContainsSameBytes: Bool
    ) throws -> ImportReceipt {
        let receipt = ImportReceipt(
            jobId: jobId,
            proposalDigest: proposalDigest,
            status: .rejected,
            acceptedDayIds: [],
            skippedLockedIds: [],
            warnings: [],
            errors: [reason],
            importedAt: now()
        )
        // Do not move the proposal unless the durable rejection receipt exists.
        try writeReceipt(receipt, jobId: jobId)
        try finishMove(
            inboxURL: inboxURL,
            processedURL: processedURL,
            processedAlreadyContainsSameBytes: processedAlreadyContainsSameBytes
        )
        return receipt
    }

    private func writeReceipt(_ receipt: ImportReceipt, jobId: String) throws {
        let jobDirectory = layout.jobsDirectoryURL.appendingPathComponent(jobId, isDirectory: true)
        try fileManager.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        let receiptURL = jobDirectory.appendingPathComponent("receipt.json")
        let data = try ISO8601Codec.encoder.encode(receipt)
        try data.write(to: receiptURL, options: .atomic)
    }

    private func preflightProcessedDestination(
        _ processedURL: URL,
        incomingData: Data,
        jobId: String
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: processedURL.path) else { return false }
        let existingData = try Data(contentsOf: processedURL)
        guard existingData == incomingData else {
            throw EvolutionProposalInboxError.processedConflict(jobId)
        }
        return true
    }

    private func finishMove(
        inboxURL: URL,
        processedURL: URL,
        processedAlreadyContainsSameBytes: Bool
    ) throws {
        if processedAlreadyContainsSameBytes {
            // The processed copy is byte-identical, so the inbox copy is not the
            // only evidence. Removing only this duplicate closes crash recovery.
            try fileManager.removeItem(at: inboxURL)
        } else {
            try fileManager.moveItem(at: inboxURL, to: processedURL)
        }
    }
}

private enum PackageTrustError: Error, LocalizedError {
    case missingEvidence(String)
    case invalidEvidence(String)
    case jobIdMismatch(filename: String, proposal: String, evidence: String?)
    case unsupportedEvidenceSchema(Int)
    case evidenceContentHashMismatch(String)
    case sourceDigestMismatch(String)
    case proposalSessionsMismatch(String)
    case proposalWorktreesMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingEvidence(let jobId):
            return "missing jobs/\(jobId)/evidence.json"
        case .invalidEvidence(let jobId):
            return "invalid jobs/\(jobId)/evidence.json"
        case let .jobIdMismatch(filename, proposal, evidence):
            return "jobId mismatch: filename=\(filename), proposal=\(proposal), evidence=\(evidence ?? "missing")"
        case .unsupportedEvidenceSchema(let version):
            return "unsupported evidence schema: \(version)"
        case .evidenceContentHashMismatch(let jobId):
            return "evidence contentHash mismatch: \(jobId)"
        case .sourceDigestMismatch(let jobId):
            return "proposal/evidence sourceDigest mismatch: \(jobId)"
        case .proposalSessionsMismatch(let jobId):
            return "proposal/evidence sessions mismatch: \(jobId)"
        case .proposalWorktreesMismatch(let jobId):
            return "proposal/evidence worktrees mismatch: \(jobId)"
        }
    }
}
