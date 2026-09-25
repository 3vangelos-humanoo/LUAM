import AppKit
import SwiftUI
import WebKit

/// Owns the preview's `WKWebView` for the lifetime of a window, so switching
/// between ⌘1 / ⌘2 / ⌘3 keeps the page, its scroll position and its images.
///
/// The page is a fixed shell (`PreviewPage`: `preview.css` + `preview.js`)
/// loaded once; after that only `#luam-content` and the theme stylesheet are
/// swapped, which is what keeps typing smooth.
final class PreviewController: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    /// Called with the fractional source line at the top of the page as the
    /// user scrolls the preview.
    var onScroll: ((Double) -> Void)?

    /// Called with the source line of a task checkbox the user clicked.
    var onToggleTask: ((Int) -> Void)?

    private var baseURL: URL?
    private var shellRequested = false
    private var isLoaded = false
    private var html = ""
    private var style = PreviewStyle().css
    private var pendingLine: Double?

    override init() {
        let configuration = VendorSchemeHandler.configuration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        contentController.add(ScriptMessageProxy(target: self), name: "luam")
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
    }

    /// The directory relative links and images resolve against. Changing it
    /// (e.g. after Save As) reloads the shell.
    func setBaseURL(_ url: URL?) {
        guard url != baseURL || !shellRequested else { return }
        baseURL = url
        loadShell()
    }

    func setContent(_ html: String) {
        self.html = html
        if !shellRequested { loadShell() }
        guard isLoaded else { return }
        webView.callAsyncJavaScript(
            "LUAM.setContent(html)", arguments: ["html": html], in: nil, in: .page, completionHandler: nil
        )
    }

    /// Swaps the theme stylesheet in place; the shell picks it up on reload.
    func setStyle(_ css: String) {
        guard css != style else { return }
        style = css
        guard isLoaded else { return }
        webView.callAsyncJavaScript(
            "LUAM.setStyle(css)", arguments: ["css": css], in: nil, in: .page, completionHandler: nil
        )
    }

    func scrollToLine(_ line: Double) {
        guard isLoaded else { pendingLine = line; return }
        webView.evaluateJavaScript("LUAM.scrollToLine(\(line))", completionHandler: nil)
    }

    // MARK: Shell

    private func loadShell() {
        shellRequested = true
        isLoaded = false
        webView.loadHTMLString(shell, baseURL: baseURL)
    }

    private var shell: String {
        PreviewPage.document(title: "Preview", style: style, body: "", script: PreviewPage.script)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        // The style may have changed while the shell was loading.
        webView.callAsyncJavaScript(
            "LUAM.setStyle(css)", arguments: ["css": style], in: nil, in: .page, completionHandler: nil
        )
        setContent(html)
        if let line = pendingLine {
            pendingLine = nil
            scrollToLine(line)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else { return .allow }

        // In-page anchors resolve against the base URL; loading that would
        // replace the shell with a directory listing, so scroll instead.
        if let fragment = url.fragment, Self.strippingFragment(url) == Self.strippingFragment(webView.url) {
            let id = fragment.removingPercentEncoding ?? fragment
            _ = try? await webView.callAsyncJavaScript(
                "document.getElementById(id)?.scrollIntoView()", arguments: ["id": id], contentWorld: .page
            )
            return .cancel
        }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    private static func strippingFragment(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.fragment = nil
        return components.string
    }
}

/// `WKUserContentController` retains its handlers; this breaks the cycle.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: PreviewController?

    init(target: PreviewController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let line = (body["topLine"] as? NSNumber)?.doubleValue {
            target?.onScroll?(line)
        } else if let line = (body["toggleTask"] as? NSNumber)?.intValue {
            target?.onToggleTask?(line)
        }
    }
}

/// The preview pane. The web view itself lives in the `PreviewController`.
struct PreviewWebView: NSViewRepresentable {
    let controller: PreviewController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
