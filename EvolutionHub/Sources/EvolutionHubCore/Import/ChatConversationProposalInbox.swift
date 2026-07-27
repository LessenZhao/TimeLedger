import EvolutionCore
import Foundation

public enum ChatConversationProposalInboxError: Error, Sendable, Equatable {
    case invalidJobId(String)
    case jobIdMismatch(filename: String, proposal: String)
}

/// Read-only boundary for Skill-produced ChatGPT candidates. This type never
/// applies a proposal or changes the formal ChatGPT ledger.
public struct ChatConversationProposalInbox: @unchecked Sendable {
    public let layout: EvolutionLedgerLayout

    private let fileManager: FileManager

    public init(layout: EvolutionLedgerLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func readPending() throws -> [ChatConversationProposal] {
        try layout.ensureDirectories(fileManager: fileManager)
        let urls = try fileManager.contentsOfDirectory(
            at: layout.chatConversationProposalInboxDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            guard url.pathExtension.lowercased() == "json" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try urls.map { url in
            let jobId = url.deletingPathExtension().lastPathComponent
            guard isSafeJobID(jobId) else {
                throw ChatConversationProposalInboxError.invalidJobId(jobId)
            }
            let proposal = try JSONDecoder().decode(ChatConversationProposal.self, from: Data(contentsOf: url))
            guard proposal.jobId == jobId else {
                throw ChatConversationProposalInboxError.jobIdMismatch(filename: jobId, proposal: proposal.jobId)
            }
            return proposal
        }
    }

    private func isSafeJobID(_ jobId: String) -> Bool {
        guard !jobId.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return jobId.unicodeScalars.allSatisfy(allowed.contains)
    }
}
