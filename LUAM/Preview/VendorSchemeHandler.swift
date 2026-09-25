import Foundation
import WebKit

/// Serves the bundled KaTeX and Mermaid files (LUAM/Preview/Vendor) to the
/// preview as `luam-vendor:///<file>`.
///
/// Preview pages are loaded with the document's folder as their base URL,
/// which is what lets relative images work — and also means they can't read
/// the app bundle. A scheme handler sidesteps that. Xcode copies resources
/// flat, so only the last path component matters: KaTeX's stylesheet asks
/// for `fonts/KaTeX_Main-Regular.woff2` and gets the bundled font.
final class VendorSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "luam-vendor"

    private static let types = [
        "js": "text/javascript", "css": "text/css", "woff2": "font/woff2",
    ]

    /// Versions pinned when the files were bundled; exported HTML loads the
    /// same builds from the CDN, checked against these SHA-256 hashes.
    static let cdn = """
        window.LUAM_VENDOR = {
          katexJS: { src: "https://cdn.jsdelivr.net/npm/katex@0.18.9/dist/katex.min.js",
                     integrity: "sha256-FV9sLWc8WRLjtI9F2IMOqtGK4ZU5FZOc62SOqLnD5+I=" },
          katexCSS: { src: "https://cdn.jsdelivr.net/npm/katex@0.18.9/dist/katex.min.css",
                      integrity: "sha256-uc4OjOk/DBjEmG/h8cPCadkhtWpp5sl/g6UHkWs4qrU=" },
          mermaid: { src: "https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js",
                     integrity: "sha256-WB7X10vZBI0OOpE2OSfXLvIpQtdyJUayf3zCnjU5Drg=" },
        };
        """

    /// A web view configuration with the handler installed.
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(VendorSchemeHandler(), forURLScheme: scheme)
        return configuration
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let type = Self.types[url.pathExtension.lowercased()],
              let file = Bundle.main.url(
                  forResource: url.deletingPathExtension().lastPathComponent, withExtension: url.pathExtension
              ),
              let data = try? Data(contentsOf: file),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                  "Content-Type": type,
                  "Content-Length": "\(data.count)",
                  // The page's origin is file://; fonts need CORS to load.
                  "Access-Control-Allow-Origin": "*",
              ])
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
