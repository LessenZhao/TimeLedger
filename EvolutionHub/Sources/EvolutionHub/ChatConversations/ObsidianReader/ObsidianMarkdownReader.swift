import AppKit
import EvolutionCore
import EvolutionHubCore
import Foundation
import SwiftUI
import WebKit

struct ObsidianReaderSection: Identifiable, Equatable {
    let id: String
    let markdown: String
    var label: String? = nil
    var metadata: ObsidianReaderSectionMetadata = .init()
}

/// Read-only identity carried with a rendered section. It lets the web surface
/// remain an adapter: persisted note anchors are still validated in Swift.
struct ObsidianReaderSectionMetadata: Equatable {
    var conversationId: String? = nil
    var messageId: String? = nil
    var assetId: String? = nil
    var versionId: String? = nil
}

struct ObsidianReaderNote: Identifiable, Equatable {
    let id: String
    let sectionID: String
    let sourceRange: NSRange
    let quote: String
    let sourceHash: String
    let visibleTextHash: String
    let rendererVersion: String
    let selectorVersion: String
    let offsetUnit: String
    let positionStart: Int
    let positionEnd: Int
    let exact: String
    let prefix: String
    let suffix: String

    init(
        id: String,
        sectionID: String,
        sourceRange: NSRange,
        quote: String,
        sourceHash: String = "",
        visibleTextHash: String = "",
        rendererVersion: String = "",
        selectorVersion: String = "",
        offsetUnit: String = "utf16",
        positionStart: Int? = nil,
        positionEnd: Int? = nil,
        exact: String = "",
        prefix: String = "",
        suffix: String = ""
    ) {
        self.id = id
        self.sectionID = sectionID
        self.sourceRange = sourceRange
        self.quote = quote
        self.sourceHash = sourceHash
        self.visibleTextHash = visibleTextHash
        self.rendererVersion = rendererVersion
        self.selectorVersion = selectorVersion
        self.offsetUnit = offsetUnit
        self.positionStart = positionStart ?? sourceRange.location
        self.positionEnd = positionEnd ?? (sourceRange.location + sourceRange.length)
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
    }
}

struct ObsidianReaderSelection: Equatable {
    let range: NSRange
    let quote: String
    let visibleText: String
    let prefix: String
    let suffix: String
}

/// A single local WebKit document is the only surface for rendering and selection.
struct ObsidianMarkdownReader: NSViewRepresentable {
    let sections: [ObsidianReaderSection]
    var notes: [ObsidianReaderNote] = []
    var allowsAnnotations = false
    var bodyFontSize: CGFloat = 16
    var scrollTargetID: String? = nil
    var onSelectionAction: ((String, ObsidianReaderSelection, ReaderAction) -> Void)?
    var onEditNote: ((String) -> Void)?

    enum ReaderAction {
        case note
        case highlight
        case copy
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reader: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "obsidianReader")
        configuration.userContentController = controller
        configuration.preferences.isElementFullscreenEnabled = false

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        context.coordinator.loadLocalReader(into: view)
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.reader = self
        context.coordinator.sendDocumentIfReady()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "obsidianReader")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var reader: ObsidianMarkdownReader
        weak var webView: WKWebView?
        private var isLoaded = false
        private var lastPayload = ""
        private var lastScrollTargetID: String?

        init(reader: ObsidianMarkdownReader) {
            self.reader = reader
        }

        func loadLocalReader(into webView: WKWebView) {
            let requiredResources: [(String, String)] = [
                ("index", "html"),
                ("reader", "css"),
                ("reader", "js"),
                ("markdown-it-14.1.0.min", "js"),
                ("markdown-it-footnote-4.0.0.min", "js"),
                ("recogito-env", "js"),
                ("recogito-text-annotator-4.2.5.umd", "js"),
                ("recogito-text-annotator-4.2.5", "css")
            ]
            let readerBundle = packagedReaderBundle
            let missing = requiredResources.compactMap { name, resourceExtension in
                readerBundle?.url(forResource: name, withExtension: resourceExtension) == nil
                    ? "\(name).\(resourceExtension)" : nil
            }
            guard missing.isEmpty,
                  let html = readerBundle?.url(
                forResource: "index",
                withExtension: "html"
            ), let root = html.deletingLastPathComponent() as URL? else {
                let bundlePath = readerBundle?.bundleURL.path ?? "(reader bundle unavailable)"
                NSLog("Obsidian reader resource missing: \(missing.joined(separator: ", ")); bundle=\(bundlePath)")
                webView.loadHTMLString(
                    "<main><h1>阅读器资源缺失</h1><p>\(missing.joined(separator: ", "))</p><p>\(bundlePath)</p></main>",
                    baseURL: nil
                )
                return
            }
            webView.loadFileURL(html, allowingReadAccessTo: root)
        }

        /// SwiftPM's generated `Bundle.module` uses a build-directory fallback
        /// when this executable is copied into an .app. Prefer the explicit
        /// app resource bundle so a TimeLedger Dev acceptance run can never
        /// silently load a stale working-tree reader.js.
        private var packagedReaderBundle: Bundle? {
            if let resources = Bundle.main.resourceURL,
               let bundle = Bundle(url: resources.appendingPathComponent("EvolutionHub_EvolutionHub.bundle")) {
                return bundle
            }
            return Bundle.module
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            sendDocumentIfReady(force: true)
        }

        func sendDocumentIfReady(force: Bool = false) {
            guard isLoaded, let webView else { return }
            let payload = ReaderPayload(reader: reader)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(payload) else { return }
            let encoded = data.base64EncodedString()
            guard force || encoded != lastPayload else {
                scrollIfNeeded()
                return
            }
            lastPayload = encoded
            webView.evaluateJavaScript("window.obsidianReader.load('\(encoded)')") { _, error in
                if let error {
                    NSLog("Obsidian reader failed to load document: \(error.localizedDescription)")
                }
            }
            scrollIfNeeded()
        }

        private func scrollIfNeeded() {
            guard let target = reader.scrollTargetID, target != lastScrollTargetID, let webView else { return }
            lastScrollTargetID = target
            let encoded = (try? JSONEncoder().encode(target))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            webView.evaluateJavaScript("window.obsidianReader.scrollToSection(\(encoded))")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "obsidianReader",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "note", "highlight", "copy": handleSelection(type: type, body: body)
            case "editHighlight":
                if let noteID = body["noteID"] as? String {
                    let callback = reader.onEditNote
                    DispatchQueue.main.async { callback?(noteID) }
                }
            case "openLink":
                if let href = body["href"] as? String, let url = URL(string: href) {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        }

        private func handleSelection(type: String, body: [String: Any]) {
            guard reader.allowsAnnotations,
                  let sectionID = body["sectionID"] as? String,
                  let location = body["locationUTF16"] as? Int,
                  let length = body["lengthUTF16"] as? Int,
                  let quote = body["quote"] as? String,
                  let visibleText = body["visibleText"] as? String,
                  let prefix = body["prefix"] as? String,
                  let suffix = body["suffix"] as? String,
                  reader.sections.contains(where: { $0.id == sectionID }),
                  location >= 0,
                  length > 0,
                  !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let selection = ObsidianReaderSelection(
                range: NSRange(location: location, length: length),
                quote: quote,
                visibleText: visibleText,
                prefix: prefix,
                suffix: suffix
            )

            let action: ReaderAction
            switch type {
            case "note": action = .note
            case "highlight": action = .highlight
            default:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selection.quote, forType: .string)
                action = .copy
            }
            // WKScriptMessageHandler delivery is not guaranteed to be on the
            // SwiftUI mutation path. Move state-changing callbacks explicitly
            // to main so the note composer is presented reliably.
            let callback = reader.onSelectionAction
            DispatchQueue.main.async { callback?(sectionID, selection, action) }
        }
    }
}

private struct ReaderPayload: Encodable {
    struct Section: Encodable {
        let id: String
        let markdown: String
        let label: String?
        let conversationId: String?
        let messageId: String?
        let assetId: String?
        let versionId: String?
        let sourceHash: String
    }

    struct Note: Encodable {
        let id: String
        let sectionID: String
        let locationUTF16: Int
        let lengthUTF16: Int
        let quote: String
        let sourceHash: String
        let visibleTextHash: String
        let rendererVersion: String
        let selectorVersion: String
        let offsetUnit: String
        let positionStart: Int
        let positionEnd: Int
        let exact: String
        let prefix: String
        let suffix: String
    }

    let sections: [Section]
    let notes: [Note]
    let allowsAnnotations: Bool
    let bodyFontSize: CGFloat

    init(reader: ObsidianMarkdownReader) {
        sections = reader.sections.map {
            .init(
                id: $0.id,
                markdown: $0.markdown,
                label: $0.label,
                conversationId: $0.metadata.conversationId,
                messageId: $0.metadata.messageId,
                assetId: $0.metadata.assetId,
                versionId: $0.metadata.versionId,
                sourceHash: ContentHasher.hash($0.markdown)
            )
        }
        notes = reader.notes.map {
            .init(
                id: $0.id,
                sectionID: $0.sectionID,
                locationUTF16: $0.sourceRange.location,
                lengthUTF16: $0.sourceRange.length,
                quote: $0.quote,
                sourceHash: $0.sourceHash,
                visibleTextHash: $0.visibleTextHash,
                rendererVersion: $0.rendererVersion,
                selectorVersion: $0.selectorVersion,
                offsetUnit: $0.offsetUnit,
                positionStart: $0.positionStart,
                positionEnd: $0.positionEnd,
                exact: $0.exact,
                prefix: $0.prefix,
                suffix: $0.suffix
            )
        }
        allowsAnnotations = reader.allowsAnnotations
        bodyFontSize = reader.bodyFontSize
    }
}
