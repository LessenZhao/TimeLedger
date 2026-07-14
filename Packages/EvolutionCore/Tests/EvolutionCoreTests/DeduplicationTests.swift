import XCTest
@testable import EvolutionCore

final class DeduplicationTests: XCTestCase {
    func testPreferredExternalIdKey() {
        let key = DeduplicationKey.resolve(
            source: .codex,
            externalId: "019e8778",
            sourcePath: "/tmp/a.jsonl",
            sourceLine: 7,
            contentHash: "abc"
        )
        XCTAssertEqual(key, .external(source: .codex, externalId: "019e8778"))
        XCTAssertEqual(key.stringValue, "ext:codex:019e8778")
    }

    func testFallbackWhenExternalIdMissing() {
        let hash = ContentHasher.hash("hello")
        let key = DeduplicationKey.resolve(
            source: .claude,
            externalId: nil,
            sourcePath: "/tmp/b.jsonl",
            sourceLine: 12,
            contentHash: hash
        )
        XCTAssertEqual(
            key,
            .fallback(source: .claude, sourcePath: "/tmp/b.jsonl", sourceLine: 12, contentHash: hash)
        )
    }

    func testRepeatedImportIsIdempotent() {
        var deduper = ImportDeduper()
        let key = DeduplicationKey.external(source: .chatgpt, externalId: "conv-1")

        XCTAssertTrue(deduper.register(key))
        XCTAssertFalse(deduper.register(key))
        XCTAssertFalse(deduper.register(key))
        XCTAssertEqual(deduper.count, 1)
        XCTAssertTrue(deduper.contains(key))
    }

    func testDifferentSourcesDoNotCollide() {
        var deduper = ImportDeduper()
        let a = DeduplicationKey.external(source: .codex, externalId: "same")
        let b = DeduplicationKey.external(source: .claude, externalId: "same")
        XCTAssertTrue(deduper.register(a))
        XCTAssertTrue(deduper.register(b))
        XCTAssertEqual(deduper.count, 2)
    }

    func testContentHashStable() {
        XCTAssertEqual(ContentHasher.hash("x"), ContentHasher.hash("x"))
        XCTAssertNotEqual(ContentHasher.hash("x"), ContentHasher.hash("y"))
    }
}
