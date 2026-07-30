import AppKit
import WebKit

final class Probe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let application = NSApplication.shared
    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 800), configuration: configuration)
        super.init()
        controller.add(self, name: "recogitoSpike")
    }

    func run() {
        webView.navigationDelegate = self
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        webView.loadFileURL(fixture, allowingReadAccessTo: fixture.deletingLastPathComponent())
        application.run()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("""
        (() => {
        window.runRecogitoSpike()
          .then(result => window.webkit.messageHandlers.recogitoSpike.postMessage({ ok: true, result }))
          .catch(error => window.webkit.messageHandlers.recogitoSpike.postMessage({ ok: false, error: String(error) }));
        return null;
        })()
        """) { _, error in
            if let error {
                fputs("Recogito Spike FAILED: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let ok = body["ok"] as? Bool else {
            fputs("Recogito Spike FAILED: malformed browser result\n", stderr)
            exit(1)
        }
        if ok, let result = body["result"] as? String {
            let output = URL(fileURLWithPath: "/private/tmp/recogito-spike-pass.png")
            webView.takeSnapshot(with: nil) { image, error in
                guard error == nil,
                      let tiff = image?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    fputs("Recogito Spike FAILED: could not create screenshot\n", stderr)
                    exit(1)
                }
                do {
                    try png.write(to: output)
                    print("\(result)\nscreenshot=\(output.path)")
                    exit(0)
                } catch {
                    fputs("Recogito Spike FAILED: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        fputs("Recogito Spike FAILED: \(body["error"] as? String ?? "unknown JavaScript error")\n", stderr)
        exit(1)
    }
}

let probe = Probe()
probe.run()
