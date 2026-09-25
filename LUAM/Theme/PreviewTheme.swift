import Foundation

/// How the preview (and exported HTML, PDF and print-outs) look.
///
/// `preview.css` is the base; a theme only overrides its custom properties and
/// a few typographic choices, so every theme keeps light and dark variants.
enum PreviewTheme: String, CaseIterable, Identifiable {
    case standard, github, reader, sepia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "LUAM"
        case .github: "GitHub"
        case .reader: "Reader"
        case .sepia: "Sepia"
        }
    }

    fileprivate var css: String {
        switch self {
        case .standard:
            return ""
        case .github:
            return """
                :root { --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --rule: #d1d9e0;
                        --code-bg: #f6f8fa; --link: #0969da; --quote: #59636e; }
                @media (prefers-color-scheme: dark) {
                  :root { --bg: #0d1117; --fg: #f0f6fc; --muted: #9198a1; --rule: #3d444d;
                          --code-bg: #151b23; --link: #4493f8; --quote: #9198a1; }
                }
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
                       line-height: 1.5; max-width: 980px; }
                h1, h2, h3, h4, h5, h6 { font-weight: 600; }
                pre { border-radius: 6px; }
                """
        case .reader:
            return Self.serif + """
                body { max-width: 36em; }
                h1, h2 { border-bottom: none; }
                """
        case .sepia:
            return Self.serif + """
                :root { --bg: #f7f0e1; --fg: #3d3326; --muted: #7a6a55; --rule: #dccdb0;
                        --code-bg: #efe4cc; --link: #8f4f06; --quote: #7a6a55; }
                @media (prefers-color-scheme: dark) {
                  :root { --bg: #2a251e; --fg: #e9dcc3; --muted: #b3a283; --rule: #4a4032;
                          --code-bg: #352e25; --link: #e3a557; --quote: #b3a283; }
                }
                body { max-width: 36em; }
                h1, h2 { border-bottom: none; }
                """
        }
    }

    private static let serif = """
        body { font-family: "New York", ui-serif, "Iowan Old Style", Georgia, serif;
               font-size: calc(var(--luam-font-size, 16px) * 1.125); line-height: 1.7; }
        h1, h2, h3, h4, h5, h6 { font-weight: 700; letter-spacing: -0.01em; }

        """
}

/// Everything the preview page's `<style id="luam-style">` holds: the theme
/// plus the reader's chosen text size.
struct PreviewStyle: Equatable {
    var theme: PreviewTheme = .standard
    var fontSize: Double = AppSettings.defaultPreviewFontSize

    var css: String {
        ":root { --luam-font-size: \(Int(fontSize.rounded()))px; }\n" + theme.css
    }
}
