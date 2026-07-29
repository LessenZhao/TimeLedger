import Foundation
import XCTest

final class ObsidianReaderOfflineRendererTests: XCTestCase {
    func testReaderHTMLReferencesResourcesAtTheSwiftPMProcessedBundleRoot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = root.appendingPathComponent("Sources/EvolutionHub/Resources/ObsidianReader")
        let html = try String(contentsOf: resources.appendingPathComponent("index.html"), encoding: .utf8)

        XCTAssertTrue(html.contains("src=\"markdown-it-14.1.0.min.js\""))
        XCTAssertTrue(html.contains("src=\"markdown-it-footnote-4.0.0.min.js\""))
        XCTAssertFalse(html.contains("src=\"vendor/"))
    }

    func testVendoredMarkdownItRendersRequiredMarkdownWithoutExecutingRawScript() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vendor = root.appendingPathComponent("Sources/EvolutionHub/Resources/ObsidianReader/vendor")
        let script = """
        const fs = require('fs'), vm = require('vm');
        const vendor = process.argv[1], sandbox = {};
        sandbox.globalThis = sandbox;
        vm.runInNewContext(fs.readFileSync(vendor + '/markdown-it-14.1.0.min.js', 'utf8'), sandbox);
        vm.runInNewContext(fs.readFileSync(vendor + '/markdown-it-footnote-4.0.0.min.js', 'utf8'), sandbox);
        const md = sandbox.markdownit({ html: false }).use(sandbox.markdownitFootnote);
        const html = md.render('# H1\\n\\n## H2\\n\\n- item\\n\\n**bold** *italic* `code`\\n\\n> quote\\n\\n[link](https://example.com)\\n\\n| a | b |\\n| - | - |\\n| 1 | 2 |\\n\\nfoot[^1]\\n\\n[^1]: note\\n\\n<script>window.badBridge=1</script>');
        const required = ['<h1>', '<h2>', '<ul>', '<strong>', '<em>', '<code>', '<blockquote>', 'href="https://example.com"', '<table>', 'footnote-ref', '&lt;script&gt;'];
        if (required.some(part => !html.includes(part)) || html.includes('<script>window.badBridge')) process.exit(1);
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", script, vendor.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
