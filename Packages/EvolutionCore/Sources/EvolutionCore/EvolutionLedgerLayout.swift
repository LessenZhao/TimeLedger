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
            inboxDirectoryURL,
            processedDirectoryURL,
            jobsDirectoryURL,
            dailyMapsDirectoryURL,
            projectEvolutionsDirectoryURL,
        ]
    }

    public static func defaultDocuments(fileManager: FileManager = .default) -> EvolutionLedgerLayout {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
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
