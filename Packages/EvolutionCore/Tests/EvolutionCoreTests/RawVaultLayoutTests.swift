import XCTest
@testable import EvolutionCore

final class RawVaultLayoutTests: XCTestCase {
    func testRequiredDirectoriesIncludeSources() {
        let root = URL(fileURLWithPath: "/tmp/PersonalEvolutionEngine-test")
        let layout = RawVaultLayout(rootURL: root)

        let paths = layout.requiredDirectories.map(\.path)
        XCTAssertTrue(paths.contains(root.appendingPathComponent("raw/codex").path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("raw/claude").path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("raw/chatgpt").path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("normalized").path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("sync").path))
    }

    func testEnsureDirectoriesCreatesTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pee-vault-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let layout = RawVaultLayout(rootURL: root)
        try layout.ensureDirectories()

        for url in layout.requiredDirectories {
            var isDir: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
            XCTAssertTrue(isDir.boolValue)
        }
    }
}
