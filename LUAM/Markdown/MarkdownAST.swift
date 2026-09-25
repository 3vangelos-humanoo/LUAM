import Foundation

// The tree every consumer reads: `SyntaxStyler` walks it for `NSRange`s to
// attribute the source pane, `HTMLRenderer` walks it for `line`s to stamp
// `data-line` onto the preview. One parse, two consumers.
//
// All ranges are UTF-16 based — the same units `NSString`, `NSTextView` and
// `NSTextStorage` use — so they can be applied to the editor without conversion.
// Lines are 1-based, matching what the user sees.

/// The result of parsing one Markdown document.
nonisolated struct MarkdownTree: Sendable, Equatable {
    /// Top-level blocks, in source order.
    var blocks: [Block]
    /// Length of the parsed source, in UTF-16 code units.
    var sourceLength: Int
    /// Number of source lines.
    var lineCount: Int
}

/// A block-level element: heading, paragraph, list, code block, …
nonisolated struct Block: Sendable, Equatable {
    var kind: Kind
    /// Full source extent, including markers like `#`, `>` or code fences.
    var range: NSRange
    /// First source line (1-based).
    var line: Int
    /// Last source line (1-based, inclusive).
    var endLine: Int
    /// Syntax characters that aren't content — `#`s, `>`s, list bullets, fence
    /// lines, table pipes. The styler dims these.
    var markers: [NSRange] = []
    /// Child blocks, for containers (block quotes, lists, list items).
    var children: [Block] = []
    /// Inline content, for leaf blocks that have it (headings, paragraphs).
    var inlines: [Inline] = []

    nonisolated enum Kind: Sendable, Equatable {
        case heading(level: Int)
        case paragraph
        case blockQuote
        case list(ListStyle)
        /// `task` is `nil` for a plain item, else whether the box is checked.
        case listItem(task: Bool?)
        case codeBlock(CodeBlock)
        case htmlBlock(String)
        case thematicBreak
        case table(Table)
    }
}

nonisolated struct ListStyle: Sendable, Equatable {
    var ordered: Bool
    /// Start number for ordered lists; ignored otherwise.
    var start: Int
    /// A tight list renders its items' paragraphs without `<p>` wrappers.
    var tight: Bool
}

nonisolated struct CodeBlock: Sendable, Equatable {
    /// The first word of the fence's info string (`swift` in ```` ```swift ````).
    var language: String?
    /// The code, with container prefixes and indentation stripped, ending in `\n`
    /// unless empty.
    var code: String
    /// Source range of the code content alone (no fences), for highlighting in
    /// the editor. Only meaningful for top-level blocks; nested blocks may span
    /// stripped container markers.
    var contentRange: NSRange
    var fenced: Bool
}

nonisolated struct Table: Sendable, Equatable {
    nonisolated enum Alignment: Sendable, Equatable {
        case none, left, center, right
    }

    var alignments: [Alignment]
    var header: TableRow
    var rows: [TableRow]
}

nonisolated struct TableRow: Sendable, Equatable {
    var cells: [TableCell]
    var range: NSRange
    var line: Int
}

nonisolated struct TableCell: Sendable, Equatable {
    var inlines: [Inline]
    var range: NSRange
}

/// An inline element inside a heading, paragraph or table cell.
nonisolated struct Inline: Sendable, Equatable {
    var kind: Kind
    /// Full source extent, including delimiters.
    var range: NSRange
    /// Delimiters that aren't content — `**`, backticks, `[`, `](url)`.
    var markers: [NSRange] = []
    /// Child inlines, for emphasis, links and image alt text.
    var children: [Inline] = []

    nonisolated enum Kind: Sendable, Equatable {
        /// Literal text, with escapes and entities already decoded.
        case text(String)
        case softBreak
        case hardBreak
        case code(String)
        /// TeX between `$…$`, or `$$…$$` when `display`, taken verbatim.
        case math(String, display: Bool)
        case emphasis
        case strong
        case strikethrough
        case link(destination: String, title: String?)
        case image(source: String, title: String?)
        case html(String)
    }
}

extension Inline {
    /// The children's text with all markup removed — used for image alt text,
    /// heading slugs and the outline.
    nonisolated var plainText: String {
        switch kind {
        case .text(let s), .code(let s), .math(let s, _): return s
        case .softBreak, .hardBreak: return " "
        case .html: return ""
        default: return children.plainText
        }
    }
}

extension Array where Element == Inline {
    nonisolated var plainText: String {
        map(\.plainText).joined()
    }
}

extension MarkdownTree {
    /// Depth-first walk over every block, containers before their children.
    nonisolated func forEachBlock(_ body: (Block) -> Void) {
        func visit(_ blocks: [Block]) {
            for block in blocks {
                body(block)
                visit(block.children)
            }
        }
        visit(blocks)
    }
}
