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
        XCTAssertTrue(html.contains("href=\"recogito-text-annotator-4.2.5.css\""))
        XCTAssertTrue(html.contains("src=\"recogito-env.js\""))
        XCTAssertTrue(html.contains("src=\"recogito-text-annotator-4.2.5.umd.js\""))
        XCTAssertFalse(html.contains("src=\"vendor/"))

        let css = try String(contentsOf: resources.appendingPathComponent("reader.css"), encoding: .utf8)
        XCTAssertTrue(css.contains(".selection-toolbar[hidden] { display: none; }"))
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

    func testRuntimeResourceGateRequiresRecogitoEnvironmentShim() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reader = root.appendingPathComponent(
            "Sources/EvolutionHub/ChatConversations/ObsidianReader/ObsidianMarkdownReader.swift"
        )
        let source = try String(contentsOf: reader, encoding: .utf8)

        XCTAssertTrue(source.contains("(\"recogito-env\", \"js\")"))
    }

    func testSavedAnchorsHashRenderedVisibleTextInsteadOfMarkdownSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceView = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/EvolutionHub/ChatConversations/ChatConversationSourceView.swift"
            ),
            encoding: .utf8
        )
        let ledgerView = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/EvolutionHub/ChatConversations/ChatConversationLedgerView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(sourceView.contains("visibleTextHash: ContentHasher.hash(selection.visibleText)"))
        XCTAssertTrue(ledgerView.contains("visibleTextHash: ContentHasher.hash(selection.visibleText)"))
    }

    func testRenderedTextHashDisambiguatesStableDuplicateAndRejectsAmbiguousRecovery() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reader = root.appendingPathComponent("Sources/EvolutionHub/Resources/ObsidianReader/reader.js")
        let script = #"""
        const fs = require('fs');
        const vm = require('vm');
        const { createHash } = require('crypto');
        const annotations = [];
        const rendered = {
          isConnected: true,
          textContent: '',
          innerHTML: '',
          style: {},
          querySelectorAll() { return []; },
          contains() { return true; }
        };
        const documentRoot = {
          replaceChildren() {},
          appendChild() {},
          setAttribute() {}
        };
        const toolbar = {
          hidden: true,
          style: {},
          addEventListener() {}
        };
        const document = {
          getElementById(id) {
            return id === 'reader-document' ? documentRoot : toolbar;
          },
          createElement(tag) {
            if (tag === 'div') return rendered;
            return {
              className: '',
              dataset: {},
              style: {},
              appendChild() {}
            };
          },
          querySelector() { return rendered; },
          querySelectorAll() { return []; },
          addEventListener() {}
        };
        const sandbox = {
          atob,
          console,
          CSS: { escape: value => value },
          document,
          NodeFilter: { SHOW_TEXT: 4 },
          TextDecoder,
          TextEncoder,
          Uint8Array,
          window: {
            getSelection() {
              return { removeAllRanges() {} };
            },
            markdownit() {
              return {
                use() { return this; },
                render() { return '<p>rendered</p>'; }
              };
            },
            markdownitFootnote() {},
            RecogitoJS: {
              createTextAnnotator() {
                return {
                  destroy() {},
                  removeAnnotation() {},
                  setAnnotations(value) { annotations.push(value); },
                  addAnnotation() {},
                  on() {}
                };
              }
            }
          }
        };
        sandbox.window.window = sandbox.window;
        vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), sandbox);
        const hash = text => createHash('sha256').update(text, 'utf8').digest('hex');

        (async () => {
          rendered.textContent = '重复 🧭 重复';
          await sandbox.window.obsidianReader.load(Buffer.from(JSON.stringify({
            sections: [{ id: 'stable', markdown: '**重复** 🧭 重复', sourceHash: 'source-hash' }],
            notes: [{
              id: 'second-dup',
              sectionID: 'stable',
              sourceHash: 'source-hash',
              visibleTextHash: hash('重复 🧭 重复'),
              positionStart: 6,
              positionEnd: 8,
              exact: '重复',
              prefix: '',
              suffix: ''
            }],
            allowsAnnotations: true,
            bodyFontSize: 16
          })).toString('base64'));
          if (annotations[0]?.length !== 1 ||
              annotations[0][0].target.selector[0].start !== 6) {
            throw new Error(`stable duplicate rebound incorrectly: ${JSON.stringify(annotations[0])}`);
          }

          rendered.textContent = 'x same x same';
          await sandbox.window.obsidianReader.load(Buffer.from(JSON.stringify({
            sections: [{ id: 'ambiguous', markdown: 'x same x same', sourceHash: 'source-hash-2' }],
            notes: [{
              id: 'ambiguous-same',
              sectionID: 'ambiguous',
              sourceHash: 'source-hash-2',
              visibleTextHash: 'stale-visible-hash',
              positionStart: 2,
              positionEnd: 6,
              exact: 'same',
              prefix: 'x ',
              suffix: ''
            }],
            allowsAnnotations: true,
            bodyFontSize: 16
          })).toString('base64'));
          if (annotations[1]?.length !== 0) {
            throw new Error(`ambiguous duplicate must stay orphaned: ${JSON.stringify(annotations[1])}`);
          }
        })().catch(error => {
          console.error(error);
          process.exitCode = 1;
        });
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", script, reader.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testReaderPayloadEncodingIsCanonicalBeforeRawPayloadDeduplication() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reader = root.appendingPathComponent(
            "Sources/EvolutionHub/ChatConversations/ObsidianReader/ObsidianMarkdownReader.swift"
        )
        let source = try String(contentsOf: reader, encoding: .utf8)

        XCTAssertTrue(source.contains("encoder.outputFormatting = [.sortedKeys]"))
        XCTAssertFalse(source.contains("JSONEncoder().encode(payload)"))
    }

    func testToolbarClickPostsOneStableNoteCommand() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reader = root.appendingPathComponent("Sources/EvolutionHub/Resources/ObsidianReader/reader.js")
        let script = #"""
        const fs = require('fs');
        const vm = require('vm');

        const toolbarHandlers = {};
        const posted = [];
        let createAnnotation;

        const toolbar = {
          hidden: true,
          style: {},
          addEventListener(type, handler) {
            (toolbarHandlers[type] ||= []).push(handler);
          }
        };
        const rendered = {
          isConnected: true,
          textContent: 'hello world',
          innerHTML: '',
          style: {},
          querySelectorAll() { return []; },
          contains() { return true; }
        };
        const documentRoot = {
          replaceChildren() {},
          appendChild() {},
          setAttribute() {}
        };
        const document = {
          getElementById(id) {
            return id === 'reader-document' ? documentRoot : toolbar;
          },
          createElement(tag) {
            if (tag === 'div') return rendered;
            return {
              className: '',
              dataset: {},
              style: {},
              appendChild() {}
            };
          },
          querySelector() { return rendered; },
          querySelectorAll() { return []; },
          addEventListener() {}
        };
        const annotator = {
          destroy() {},
          removeAnnotation() {},
          setAnnotations() {},
          addAnnotation() {},
          on(type, handler) {
            if (type === 'createAnnotation') createAnnotation = handler;
          }
        };
        const sandbox = {
          atob,
          console,
          crypto: require('crypto').webcrypto,
          CSS: { escape: value => value },
          document,
          NodeFilter: { SHOW_TEXT: 4 },
          TextDecoder,
          TextEncoder,
          Uint8Array,
          window: {
            getSelection() {
              return { removeAllRanges() {} };
            },
            markdownit() {
              return {
                use() { return this; },
                render() { return '<p>hello world</p>'; }
              };
            },
            markdownitFootnote() {},
            RecogitoJS: {
              createTextAnnotator() { return annotator; }
            },
            webkit: {
              messageHandlers: {
                obsidianReader: {
                  postMessage(message) { posted.push(message); }
                }
              }
            }
          }
        };
        sandbox.window.window = sandbox.window;

        vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), sandbox);

        (async () => {
          const encoded = Buffer.from(JSON.stringify({
            sections: [{ id: 'section-1', markdown: 'hello world', sourceHash: 'hash-1' }],
            notes: [],
            allowsAnnotations: true,
            bodyFontSize: 16
          })).toString('base64');
          await sandbox.window.obsidianReader.load(encoded);
          if (typeof createAnnotation !== 'function') throw new Error('createAnnotation listener missing');

          createAnnotation({
            id: 'temporary-selection',
            target: {
              selector: [{
                start: 0,
                end: 5,
                quote: 'hello',
                range: { getBoundingClientRect() { return { x: 20, y: 80 }; } }
              }]
            }
          });

          const button = {
            dataset: { action: 'note' }
          };
          const event = {
            target: {
              closest(selector) {
                return selector === 'button[data-action]' ? button : null;
              }
            },
            preventDefault() {},
            stopPropagation() {}
          };
          for (const handler of toolbarHandlers.pointerdown || []) handler(event);
          if (posted.length !== 0) throw new Error(`pointerdown must not post, got ${posted.length}`);
          for (const handler of toolbarHandlers.click || []) handler(event);

          if (posted.length !== 1) throw new Error(`expected one command, got ${posted.length}`);
          const command = posted[0];
          if (command.type !== 'note' ||
              command.sectionID !== 'section-1' ||
              command.locationUTF16 !== 0 ||
              command.lengthUTF16 !== 5 ||
              command.quote !== 'hello' ||
              command.visibleText !== 'hello world') {
            throw new Error(`unexpected command: ${JSON.stringify(command)}`);
          }
        })().catch(error => {
          console.error(error);
          process.exitCode = 1;
        });
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", script, reader.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
