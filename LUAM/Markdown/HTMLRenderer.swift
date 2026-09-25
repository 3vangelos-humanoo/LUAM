import Foundation

/// Turns a `MarkdownTree` into an HTML fragment for the preview (and, later,
/// export). The output follows CommonMark's reference renderer closely, so the
/// spec's expected HTML can be used in tests with every option switched off.
nonisolated struct HTMLRenderer: Sendable {
    nonisolated struct Options: Sendable {
        /// Stamp `data-line="N"` on block elements for scroll sync.
        var sourceLines = true
        /// Give headings GitHub-style `id` slugs, for anchors and the outline.
        var headingIDs = true
        /// Wrap tokens in fenced code in `<span class="tok-*">`.
        var highlightCode = true
        /// Emit `$` math and ` ```math ` blocks as `.luam-math` elements, and
        /// ` ```mermaid ` blocks as `.mermaid`, for KaTeX and Mermaid to pick
        /// up. Off, math renders as the literal source text.
        var mathAndDiagrams = true
        /// Task checkboxes the preview can toggle (they carry their source
        /// line); off, they're `disabled` like GitHub's.
        var interactiveTasks = true

        static let standard = Options()
        static let plain = Options(
            sourceLines: false, headingIDs: false, highlightCode: false,
            mathAndDiagrams: false, interactiveTasks: false
        )
        /// Standalone pages: anchors, colors and math, no editor hooks.
        static let export = Options(sourceLines: false, interactiveTasks: false)
    }

    var options: Options

    init(options: Options = .standard) {
        self.options = options
    }

    func render(_ tree: MarkdownTree) -> String {
        var state = State(options: options)
        for block in tree.blocks {
            state.block(block)
        }
        return state.out
    }

    /// GitHub's anchor algorithm: lowercase, drop punctuation, spaces to dashes.
    /// Duplicates are disambiguated by `HeadingSlugs`.
    static func slug(_ text: String) -> String {
        var slug = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                slug.append(ch)
            } else if ch == " " {
                slug.append("-")
            }
        }
        return slug
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// Percent-encodes what isn't allowed in a URL (keeping existing `%XX`
    /// escapes), then HTML-escapes the result for use in an attribute.
    static func url(_ s: String) -> String {
        let safe = Set("-._~:/?#[]@!$&'()*+,;=%".utf8)
        var out = ""
        for byte in s.utf8 {
            if (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || safe.contains(byte) {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return escape(out)
    }
}

/// Hands out heading anchors in document order, suffixing repeats the way
/// GitHub does: `intro`, `intro-1`, `intro-2`. The renderer and the outline
/// both use it, so an outline entry always names its heading's `id`.
nonisolated struct HeadingSlugs: Sendable {
    private var used: [String: Int] = [:]

    mutating func next(for text: String) -> String {
        let base = HTMLRenderer.slug(text)
        guard let count = used[base] else {
            used[base] = 1
            return base
        }
        used[base] = count + 1
        return "\(base)-\(count)"
    }
}

nonisolated private struct State {
    let options: HTMLRenderer.Options
    var out = ""
    var slugs = HeadingSlugs()

    init(options: HTMLRenderer.Options) {
        self.options = options
    }

    private func line(_ n: Int) -> String {
        options.sourceLines ? " data-line=\"\(n)\"" : ""
    }

    private mutating func newlineIfNeeded() {
        if let last = out.utf8.last, last != 0x0A { out += "\n" }
    }

    mutating func block(_ b: Block, tight: Bool = false) {
        switch b.kind {
        case .heading(let level):
            var id = ""
            if options.headingIDs {
                let slug = slugs.next(for: b.inlines.plainText)
                id = " id=\"\(HTMLRenderer.escape(slug))\""
            }
            out += "<h\(level)\(id)\(line(b.line))>"
            inlines(b.inlines)
            out += "</h\(level)>\n"

        case .paragraph:
            if tight {
                inlines(b.inlines)
            } else {
                out += "<p\(line(b.line))>"
                inlines(b.inlines)
                out += "</p>\n"
            }

        case .blockQuote:
            out += "<blockquote\(line(b.line))>\n"
            for child in b.children { block(child) }
            out += "</blockquote>\n"

        case .list(let style):
            let tag = style.ordered ? "ol" : "ul"
            let start = style.ordered && style.start != 1 ? " start=\"\(style.start)\"" : ""
            let hasTasks = b.children.contains { if case .listItem(task: .some) = $0.kind { true } else { false } }
            let cls = hasTasks ? " class=\"contains-task-list\"" : ""
            out += "<\(tag)\(start)\(cls)\(line(b.line))>\n"
            for item in b.children { listItem(item, tight: style.tight) }
            out += "</\(tag)>\n"

        case .listItem:
            listItem(b, tight: tight)

        case .codeBlock(let code) where options.mathAndDiagrams && code.language?.lowercased() == "math":
            out += "<div class=\"luam-math luam-math-display\"\(line(b.line))>\(HTMLRenderer.escape(code.code))</div>\n"

        case .codeBlock(let code) where options.mathAndDiagrams && code.language?.lowercased() == "mermaid":
            out += "<pre class=\"mermaid\"\(line(b.line))>\(HTMLRenderer.escape(code.code))</pre>\n"

        case .codeBlock(let code):
            let lang = code.language.map { " class=\"language-\(HTMLRenderer.escape($0))\"" } ?? ""
            out += "<pre\(line(b.line))><code\(lang)>"
            if options.highlightCode, let language = CodeHighlighter.language(named: code.language) {
                highlighted(code.code, language)
            } else {
                out += HTMLRenderer.escape(code.code)
            }
            out += "</code></pre>\n"

        case .htmlBlock(let html):
            out += html
            newlineIfNeeded()

        case .thematicBreak:
            out += "<hr\(line(b.line)) />\n"

        case .table(let table):
            out += "<table\(line(b.line))>\n<thead>\n"
            row(table.header, cellTag: "th", alignments: table.alignments)
            out += "</thead>\n"
            if !table.rows.isEmpty {
                out += "<tbody>\n"
                for r in table.rows { row(r, cellTag: "td", alignments: table.alignments) }
                out += "</tbody>\n"
            }
            out += "</table>\n"
        }
    }

    private mutating func listItem(_ item: Block, tight: Bool) {
        var task: Bool?
        if case .listItem(let t) = item.kind { task = t }
        if let checked = task {
            out += "<li class=\"task-list-item\"\(line(item.line))>"
            let state = options.interactiveTasks ? " data-task-line=\"\(item.line)\"" : " disabled"
            out += "<input type=\"checkbox\"\(state)\(checked ? " checked" : "")> "
        } else {
            out += "<li\(line(item.line))>"
        }
        for child in item.children {
            if tight, case .paragraph = child.kind {
                block(child, tight: true)
            } else {
                newlineIfNeeded()
                block(child)
            }
        }
        out += "</li>\n"
    }

    private mutating func row(_ r: TableRow, cellTag: String, alignments: [Table.Alignment]) {
        out += "<tr\(line(r.line))>\n"
        for (index, cell) in r.cells.enumerated() {
            let alignment = index < alignments.count ? alignments[index] : .none
            let style = switch alignment {
            case .none: ""
            case .left: " style=\"text-align: left\""
            case .center: " style=\"text-align: center\""
            case .right: " style=\"text-align: right\""
            }
            out += "<\(cellTag)\(style)>"
            inlines(cell.inlines)
            out += "</\(cellTag)>\n"
        }
        out += "</tr>\n"
    }

    private mutating func highlighted(_ code: String, _ language: CodeHighlighter.Language) {
        let units = Array(code.utf16)
        var cursor = 0
        func text(_ start: Int, _ end: Int) -> String {
            HTMLRenderer.escape(String(utf16CodeUnits: Array(units[start..<end]), count: end - start))
        }
        for token in CodeHighlighter.tokens(units, language: language) {
            let start = token.range.location, end = NSMaxRange(token.range)
            if start > cursor { out += text(cursor, start) }
            out += "<span class=\"tok-\(token.kind.rawValue)\">\(text(start, end))</span>"
            cursor = end
        }
        if cursor < units.count { out += text(cursor, units.count) }
    }

    mutating func inlines(_ list: [Inline]) {
        for inline in list { self.inline(inline) }
    }

    private mutating func inline(_ i: Inline) {
        switch i.kind {
        case .text(let s):
            out += HTMLRenderer.escape(s)
        case .softBreak:
            out += "\n"
        case .hardBreak:
            out += "<br />\n"
        case .code(let s):
            out += "<code>\(HTMLRenderer.escape(s))</code>"
        case .math(let tex, let display):
            let delimiter = display ? "$$" : "$"
            if options.mathAndDiagrams {
                let cls = display ? "luam-math luam-math-display" : "luam-math"
                out += "<span class=\"\(cls)\">\(HTMLRenderer.escape(tex))</span>"
            } else {
                out += HTMLRenderer.escape(delimiter + tex + delimiter)
            }
        case .emphasis:
            out += "<em>"; inlines(i.children); out += "</em>"
        case .strong:
            out += "<strong>"; inlines(i.children); out += "</strong>"
        case .strikethrough:
            out += "<del>"; inlines(i.children); out += "</del>"
        case .link(let destination, let title):
            out += "<a href=\"\(HTMLRenderer.url(destination))\""
            if let title { out += " title=\"\(HTMLRenderer.escape(title))\"" }
            out += ">"
            inlines(i.children)
            out += "</a>"
        case .image(let source, let title):
            out += "<img src=\"\(HTMLRenderer.url(source))\" alt=\"\(HTMLRenderer.escape(i.children.plainText))\""
            if let title { out += " title=\"\(HTMLRenderer.escape(title))\"" }
            out += " />"
        case .html(let s):
            out += s
        }
    }
}
