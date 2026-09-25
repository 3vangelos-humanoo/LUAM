import Foundation

/// Assembles complete HTML pages around a rendered fragment. The live preview
/// and every export share it, so what you see is what you export.
enum PreviewPage {
    static let css = resource("preview", "css") ?? "body { font: 16px -apple-system, sans-serif; margin: 32px; }"

    static let script = resource("preview", "js") ?? """
        window.LUAM = {
          setContent(h) { document.getElementById("luam-content").innerHTML = h; },
          scrollToLine() {},
          setStyle(css) { document.getElementById("luam-style").textContent = css; }
        };
        """

    /// - Parameters:
    ///   - style: The theme's CSS, applied after `preview.css`.
    ///   - script: Included for the live preview and for pages with math or
    ///     diagrams, which need it to typeset them.
    ///   - bodyClass: `luam-export` trims the preview's scroll-past-end padding.
    static func document(
        title: String, style: String, body: String, script: String? = nil, bodyClass: String? = nil
    ) -> String {
        let cls = bodyClass.map { " class=\"\($0)\"" } ?? ""
        // `</script` inside the script would end the element early.
        let script = script?.replacingOccurrences(of: "</script", with: "<\\/script")
        return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(HTMLRenderer.escape(title))</title>
            <style>\(css)</style>
            <style id="luam-style">\(style)</style>
            </head>
            <body\(cls)>
            <div id="luam-content">
            \(body)</div>
            \(script.map { "<script>\($0)</script>" } ?? "")
            </body>
            </html>
            """
    }

    /// Whether a rendered fragment has anything for KaTeX or Mermaid.
    static func needsRichRendering(_ fragment: String) -> Bool {
        fragment.contains("class=\"luam-math") || fragment.contains("class=\"mermaid\"")
    }

    private static func resource(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
