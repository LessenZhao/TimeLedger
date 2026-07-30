import XCTest
@testable import EvolutionCore

final class ReadingNoteTests: XCTestCase {
    func testMakeRejectsEmptyRangeForSourceAndFormalAnchors() {
        XCTAssertThrowsError(
            try ReadingNote.sourceAnchor(
                conversationId: "c1",
                messageId: "m1",
                contentHash: "ch",
                locationUTF16: 0,
                lengthUTF16: 0,
                textHash: "th"
            )
        ) { error in
            XCTAssertEqual(error as? ReadingNoteError, .emptyRange)
        }

        XCTAssertThrowsError(
            try ReadingNote.formalAnchor(
                assetId: "a1",
                versionId: "v1",
                textHash: "th",
                locationUTF16: 3,
                lengthUTF16: 0,
                quoteHash: "qh"
            )
        ) { error in
            XCTAssertEqual(error as? ReadingNoteError, .emptyRange)
        }

        XCTAssertThrowsError(
            try ReadingNote.make(
                isHighlight: true,
                quoteSnapshot: "",
                anchor: .sourceMessageSpan(
                    SourceMessageSpanAnchor(
                        conversationId: "c1",
                        messageId: "m1",
                        contentHash: "ch",
                        locationUTF16: 0,
                        lengthUTF16: 4,
                        textHash: "th"
                    )
                )
            )
        ) { error in
            XCTAssertEqual(error as? ReadingNoteError, .emptyQuote)
        }
    }

    func testBothAnchorKindsRoundTripThroughDocument() throws {
        let sourceAnchor = try ReadingNote.sourceAnchor(
            conversationId: "conv-1",
            messageId: "msg-1",
            contentHash: ContentHasher.hash("hello world"),
            locationUTF16: 0,
            lengthUTF16: 5,
            textHash: ContentHasher.hash("hello"),
            sourceHash: ContentHasher.hash("# hello world"),
            visibleTextHash: ContentHasher.hash("hello world"),
            exact: "hello",
            prefix: "",
            suffix: " world"
        )
        let formalAnchor = try ReadingNote.formalAnchor(
            assetId: "asset-1",
            versionId: "ver-1",
            textHash: ContentHasher.hash("body text"),
            locationUTF16: 2,
            lengthUTF16: 4,
            quoteHash: ContentHasher.hash("dy t"),
            sourceHash: ContentHasher.hash("## body text"),
            visibleTextHash: ContentHasher.hash("body text"),
            exact: "dy t",
            prefix: "bo",
            suffix: "ext"
        )
        let sourceNote = try ReadingNote.make(
            id: "note-source",
            body: "想法 A",
            isHighlight: false,
            quoteSnapshot: "hello",
            anchor: sourceAnchor
        )
        let formalNote = try ReadingNote.make(
            id: "note-formal",
            body: nil,
            isHighlight: true,
            quoteSnapshot: "dy t",
            anchor: formalAnchor
        )

        let document = ReadingNotesDocument(notes: [sourceNote, formalNote])
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ReadingNotesDocument.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, ReadingNotesDocument.currentSchemaVersion)
        XCTAssertEqual(decoded.notes.count, 2)
        XCTAssertEqual(decoded.notes[0], sourceNote)
        XCTAssertEqual(decoded.notes[1], formalNote)

        if case .sourceMessageSpan(let span) = decoded.notes[0].anchor {
            XCTAssertEqual(span.conversationId, "conv-1")
            XCTAssertEqual(span.messageId, "msg-1")
            XCTAssertEqual(span.locationUTF16, 0)
            XCTAssertEqual(span.lengthUTF16, 5)
            XCTAssertEqual(span.offsetUnit, "utf16")
            XCTAssertEqual(span.positionStart, 0)
            XCTAssertEqual(span.positionEnd, 5)
            XCTAssertEqual(span.exact, "hello")
            XCTAssertEqual(span.suffix, " world")
        } else {
            XCTFail("expected source anchor")
        }

        if case .formalAssetSpan(let span) = decoded.notes[1].anchor {
            XCTAssertEqual(span.assetId, "asset-1")
            XCTAssertEqual(span.versionId, "ver-1")
            XCTAssertEqual(span.locationUTF16, 2)
            XCTAssertEqual(span.lengthUTF16, 4)
            XCTAssertEqual(span.quoteHash, ContentHasher.hash("dy t"))
            XCTAssertEqual(span.exact, "dy t")
            XCTAssertEqual(span.prefix, "bo")
        } else {
            XCTFail("expected formal anchor")
        }
    }

    func testFileStoreAtomicRoundTripAndCorruptFileThrows() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-notes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let layout = EvolutionLedgerLayout(rootURL: root)
        let url = layout.chatConversationReadingNotesFileURL
        XCTAssertEqual(url.lastPathComponent, "chatgpt-reading-notes-v2.json")
        XCTAssertTrue(url.path.hasSuffix("records/chatgpt-reading-notes-v2.json"))

        XCTAssertEqual(try ReadingNotesFileStore.load(from: url).notes, [])

        let note = try ReadingNote.make(
            id: "persist-1",
            body: "boundary",
            isHighlight: true,
            quoteSnapshot: "quote",
            anchor: try ReadingNote.sourceAnchor(
                conversationId: "c",
                messageId: "m",
                contentHash: "ch",
                locationUTF16: 1,
                lengthUTF16: 5,
                textHash: "th"
            )
        )
        try ReadingNotesFileStore.save(ReadingNotesDocument(notes: [note]), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = try ReadingNotesFileStore.load(from: url)
        XCTAssertEqual(loaded.notes, [note])

        try Data("not-json".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try ReadingNotesFileStore.load(from: url))
    }

    func testReadingNotesPathDoesNotCollideWithLedgerOrUserMarks() {
        let layout = EvolutionLedgerLayout(rootURL: URL(fileURLWithPath: "/tmp/pe", isDirectory: true))
        XCTAssertEqual(
            layout.chatConversationReadingNotesFileURL.path,
            "/tmp/pe/records/chatgpt-reading-notes-v2.json"
        )
        XCTAssertNotEqual(
            layout.chatConversationReadingNotesFileURL,
            layout.chatConversationLedgerFileURL
        )
        XCTAssertNotEqual(
            layout.chatConversationReadingNotesFileURL,
            layout.chatConversationUserMarksFileURL
        )
        XCTAssertEqual(
            layout.legacyChatConversationReadingNotesFileURL.path,
            "/tmp/pe/records/chatgpt-reading-notes.json"
        )
    }
}
