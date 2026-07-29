import EvolutionCore
@testable import EvolutionHubCore
import Foundation
import XCTest

@MainActor
final class ReadingNotesStoreTests: XCTestCase {
    func testFilterByConversationAndAsset() throws {
        let fixture = try ChatConversationHubFixture()
        let store = ChatConversationHubStore(layout: fixture.layout)

        let sourceAnchor = try ReadingNote.sourceAnchor(
            conversationId: "conv-a",
            messageId: "msg-1",
            contentHash: "ch",
            locationUTF16: 0,
            lengthUTF16: 4,
            textHash: "th"
        )
        let otherSource = try ReadingNote.sourceAnchor(
            conversationId: "conv-b",
            messageId: "msg-2",
            contentHash: "ch2",
            locationUTF16: 1,
            lengthUTF16: 2,
            textHash: "th2"
        )
        let formalAnchor = try ReadingNote.formalAnchor(
            assetId: "asset-1",
            versionId: "ver-1",
            textHash: "body-hash",
            locationUTF16: 0,
            lengthUTF16: 3,
            quoteHash: "qh"
        )

        _ = try store.addNote(body: "n1", quoteSnapshot: "aaaa", anchor: sourceAnchor, id: "n-source-a")
        _ = try store.addHighlight(quoteSnapshot: "bb", anchor: otherSource, id: "n-source-b")
        _ = try store.addNote(body: "formal", quoteSnapshot: "ccc", anchor: formalAnchor, isHighlight: true, id: "n-formal")

        XCTAssertEqual(store.allNotes.map(\.id).sorted(), ["n-formal", "n-source-a", "n-source-b"])
        XCTAssertEqual(store.notes(forConversationID: "conv-a").map(\.id), ["n-source-a"])
        XCTAssertEqual(store.notes(forConversationID: "conv-b").map(\.id), ["n-source-b"])
        XCTAssertEqual(store.notes(forAssetID: "asset-1").map(\.id), ["n-formal"])
        XCTAssertEqual(store.notes(forMessageID: "msg-1").map(\.id), ["n-source-a"])
    }

    func testPersistAcrossStoreRestartAndNotWrittenIntoLedger() throws {
        let fixture = try ChatConversationHubFixture()
        let store = ChatConversationHubStore(layout: fixture.layout)
        let anchor = try ReadingNote.sourceAnchor(
            conversationId: "c1",
            messageId: "m1",
            contentHash: "ch",
            locationUTF16: 2,
            lengthUTF16: 5,
            textHash: "th"
        )
        _ = try store.addNote(body: "keep me", quoteSnapshot: "quote", anchor: anchor, id: "persist-note")
        try store.updateReadingNote(id: "persist-note", body: "updated body", isHighlight: true)

        let notesURL = fixture.layout.chatConversationReadingNotesFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesURL.path))
        XCTAssertEqual(notesURL.lastPathComponent, "chatgpt-reading-notes.json")

        // Ledger file may be missing or empty; must not contain reading note body.
        if FileManager.default.fileExists(atPath: fixture.layout.chatConversationLedgerFileURL.path) {
            let ledgerData = try Data(contentsOf: fixture.layout.chatConversationLedgerFileURL)
            let ledgerText = String(decoding: ledgerData, as: UTF8.self)
            XCTAssertFalse(ledgerText.contains("updated body"))
            XCTAssertFalse(ledgerText.contains("persist-note"))
        }

        let reloaded = ChatConversationHubStore(layout: fixture.layout)
        XCTAssertEqual(reloaded.allNotes.count, 1)
        XCTAssertEqual(reloaded.allNotes[0].id, "persist-note")
        XCTAssertEqual(reloaded.allNotes[0].body, "updated body")
        XCTAssertTrue(reloaded.allNotes[0].isHighlight)

        reloaded.deleteReadingNote(id: "persist-note")
        let afterDelete = ChatConversationHubStore(layout: fixture.layout)
        XCTAssertTrue(afterDelete.allNotes.isEmpty)
    }

    func testRejectEmptyRangeOnAdd() {
        let fixture = try! ChatConversationHubFixture()
        let store = ChatConversationHubStore(layout: fixture.layout)
        XCTAssertThrowsError(
            try store.addHighlight(
                quoteSnapshot: "x",
                anchor: .sourceMessageSpan(
                    SourceMessageSpanAnchor(
                        conversationId: "c",
                        messageId: "m",
                        contentHash: "h",
                        locationUTF16: 0,
                        lengthUTF16: 0,
                        textHash: "t"
                    )
                )
            )
        ) { error in
            XCTAssertEqual(error as? ReadingNoteError, .emptyRange)
        }
    }
}
