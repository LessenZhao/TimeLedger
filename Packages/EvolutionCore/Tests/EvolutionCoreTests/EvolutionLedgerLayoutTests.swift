import XCTest
@testable import EvolutionCore

final class EvolutionLedgerLayoutTests: XCTestCase {
    func testLayoutProducesExactSharedPaths() {
        let root = URL(fileURLWithPath: "/tmp/Personal Evolution", isDirectory: true)
        let layout = EvolutionLedgerLayout(rootURL: root)

        XCTAssertEqual(layout.ledgerFileURL.path, root.appendingPathComponent("records/ledger.json").path)
        XCTAssertEqual(layout.chatConversationLedgerFileURL.path, root.appendingPathComponent("records/chatgpt-ledger.json").path)
        XCTAssertEqual(layout.chatConversationJobsDirectoryURL.path, root.appendingPathComponent("exchange/chatgpt/jobs").path)
        XCTAssertEqual(layout.chatConversationProposalInboxDirectoryURL.path, root.appendingPathComponent("exchange/chatgpt/inbox").path)
        XCTAssertEqual(layout.chatConversationProcessedDirectoryURL.path, root.appendingPathComponent("exchange/chatgpt/processed").path)
        XCTAssertEqual(layout.inboxDirectoryURL.path, root.appendingPathComponent("exchange/inbox").path)
        XCTAssertEqual(layout.processedDirectoryURL.path, root.appendingPathComponent("exchange/processed").path)
        XCTAssertEqual(layout.jobsDirectoryURL.path, root.appendingPathComponent("exchange/jobs").path)
        XCTAssertEqual(layout.dailyMapsDirectoryURL.path, root.appendingPathComponent("exports/Daily Maps").path)
        XCTAssertEqual(layout.projectEvolutionsDirectoryURL.path, root.appendingPathComponent("exports/Project Evolutions").path)
    }

    func testEnsureDirectoriesCreatesRequiredTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("work-evolution-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let layout = EvolutionLedgerLayout(rootURL: root)
        try layout.ensureDirectories()

        for url in layout.requiredDirectories {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue, "Expected directory at \(url.path)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.ledgerFileURL.path))
    }
}
