import AppKit
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
}

/// A single local WebKit document is the only surface for rendering and selection.
struct ObsidianMarkdownReader: NSViewRepresentable {
    let sections: [ObsidianReaderSection]
    var notes: [ObsidianReaderNote] = []
    var allowsAnnotations = false
    var scrollTargetID: String? = nil
    var onSelectionAction: ((String, NSRange, String, ReaderAction) -> Void)?
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
            guard let html = Bundle.module.url(
                forResource: "index",
                withExtension: "html"
            ), let root = html.deletingLastPathComponent() as URL? else {
                return
            }
            webView.loadFileURL(html, allowingReadAccessTo: root)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            sendDocumentIfReady(force: true)
        }

        func sendDocumentIfReady(force: Bool = false) {
            guard isLoaded, let webView else { return }
            let payload = ReaderPayload(reader: reader)
            guard let data = try? JSONEncoder().encode(payload) else { return }
            let encoded = data.base64EncodedString()
            guard force || encoded != lastPayload else {
                scrollIfNeeded()
                return
            }
            lastPayload = encoded
            webView.evaluateJavaScript("window.obsidianReader.load('\(encoded)')")
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
                if let noteID = body["noteID"] as? String { reader.onEditNote?(noteID) }
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
                  let document = try? ObsidianMarkdownDocument(sections: reader.sections.map {
                      .init(id: $0.id, markdown: $0.markdown)
                  }),
                  let selection = try? document.validatedSelection(
                      sectionID: sectionID,
                      sourceRange: NSRange(location: location, length: length),
                      quote: quote
                  ) else { return }

            let action: ReaderAction
            switch type {
            case "note": action = .note
            case "highlight": action = .highlight
            default:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selection.quote, forType: .string)
                action = .copy
            }
            reader.onSelectionAction?(selection.sectionID, selection.sourceRange, selection.quote, action)
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
    }

    struct Note: Encodable {
        let id: String
        let sectionID: String
        let locationUTF16: Int
        let lengthUTF16: Int
    }

    let sections: [Section]
    let notes: [Note]
    let allowsAnnotations: Bool

    init(reader: ObsidianMarkdownReader) {
        sections = reader.sections.map {
            .init(
                id: $0.id,
                markdown: $0.markdown,
                label: $0.label,
                conversationId: $0.metadata.conversationId,
                messageId: $0.metadata.messageId,
                assetId: $0.metadata.assetId,
                versionId: $0.metadata.versionId
            )
        }
        notes = reader.notes.map {
            .init(id: $0.id, sectionID: $0.sectionID, locationUTF16: $0.sourceRange.location, lengthUTF16: $0.sourceRange.length)
        }
        allowsAnnotations = reader.allowsAnnotations
    }
}
