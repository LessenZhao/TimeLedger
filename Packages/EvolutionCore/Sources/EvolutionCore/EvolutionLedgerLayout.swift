import Foundation

public struct EvolutionLedgerLayout: Sendable, Hashable {
    public var rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public var recordsDirectoryURL: URL {
        rootURL.appendingPathComponent("records", isDirectory: true)
    }

    public var ledgerFileURL: URL {
        recordsDirectoryURL.appendingPathComponent("ledger.json", isDirectory: false)
    }

    public var chatConversationLedgerFileURL: URL {
        recordsDirectoryURL.appendingPathComponent("chatgpt-ledger.json", isDirectory: false)
    }

    /// Local user marks (stars) for imported ChatGPT sessions/turns. Not part of the formal ledger.
    public var chatConversationUserMarksFileURL: URL {
        recordsDirectoryURL.appendingPathComponent("chatgpt-user-marks.json", isDirectory: false)
    }

    /// Personal reading notes / highlights. Parallel to ledger assets; never written into chatgpt-ledger.json.
    public var chatConversationReadingNotesFileURL: URL {
        recordsDirectoryURL.appendingPathComponent("chatgpt-reading-notes-v2.json", isDirectory: false)
    }

    /// Read-only v1 location. It is intentionally never migrated into v2.
    public var legacyChatConversationReadingNotesFileURL: URL {
        recordsDirectoryURL.appendingPathComponent("chatgpt-reading-notes.json", isDirectory: false)
    }

    public var chatConversationExchangeDirectoryURL: URL {
        rootURL.appendingPathComponent("exchange/chatgpt", isDirectory: true)
    }

    public var chatConversationJobsDirectoryURL: URL {
        chatConversationExchangeDirectoryURL.appendingPathComponent("jobs", isDirectory: true)
    }

    public var chatConversationProposalInboxDirectoryURL: URL {
        chatConversationExchangeDirectoryURL.appendingPathComponent("inbox", isDirectory: true)
    }

    public var chatConversationProcessedDirectoryURL: URL {
        chatConversationExchangeDirectoryURL.appendingPathComponent("processed", isDirectory: true)
    }

    public func chatConversationJobURL(jobId: String) -> URL {
        chatConversationJobsDirectoryURL.appendingPathComponent("\(jobId).json", isDirectory: false)
    }

    public func chatConversationReceiptURL(jobId: String) -> URL {
        chatConversationProcessedDirectoryURL.appendingPathComponent("\(jobId).json", isDirectory: false)
    }

    public var inboxDirectoryURL: URL {
        rootURL.appendingPathComponent("exchange/inbox", isDirectory: true)
    }

    public var processedDirectoryURL: URL {
        rootURL.appendingPathComponent("exchange/processed", isDirectory: true)
    }

    public var jobsDirectoryURL: URL {
        rootURL.appendingPathComponent("exchange/jobs", isDirectory: true)
    }

    public var dailyMapsDirectoryURL: URL {
        rootURL.appendingPathComponent("exports/Daily Maps", isDirectory: true)
    }

    public var projectEvolutionsDirectoryURL: URL {
        rootURL.appendingPathComponent("exports/Project Evolutions", isDirectory: true)
    }

    public var requiredDirectories: [URL] {
        [
            recordsDirectoryURL,
            chatConversationJobsDirectoryURL,
            chatConversationProposalInboxDirectoryURL,
            chatConversationProcessedDirectoryURL,
            inboxDirectoryURL,
            processedDirectoryURL,
            jobsDirectoryURL,
            dailyMapsDirectoryURL,
            projectEvolutionsDirectoryURL,
        ]
    }

    public static func defaultDocuments(fileManager: FileManager = .default) -> EvolutionLedgerLayout {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return EvolutionLedgerLayout(
            rootURL: documents.appendingPathComponent("Personal Evolution", isDirectory: true)
        )
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for directory in requiredDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
