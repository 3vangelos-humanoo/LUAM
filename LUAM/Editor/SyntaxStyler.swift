import AppKit

/// Typesets the source pane from a parsed `MarkdownTree`: headings grow, strong
/// text turns bold, syntax markers dim, code blocks get token colors.
///
/// Only attributes change — never characters — and they're set directly on the
/// text storage, so styling registers no undo and fires no `textDidChange`.
struct SyntaxStyler {
    var baseSize: CGFloat = 14

    private var baseFont: NSFont { .monospacedSystemFont(ofSize: baseSize, weight: .regular) }

    /// The attributes plain text (and newly typed text) gets.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: Self.paragraph]
    }

    private static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.15
        return p
    }()

    /// Restyles all of `storage`. The tree must have been parsed from exactly
    /// the storage's current string — callers check before applying.
    func apply(_ tree: MarkdownTree, to storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard tree.sourceLength == full.length else { return }
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        for block in tree.blocks { style(block, in: storage, nested: false) }
        storage.endEditing()
    }

    // MARK: Blocks

    private func style(_ block: Block, in s: NSTextStorage, nested: Bool) {
        switch block.kind {
        case .heading(let level):
            let scale: [CGFloat] = [1.6, 1.4, 1.25, 1.1, 1.0, 1.0]
            let font = NSFont.monospacedSystemFont(ofSize: baseSize * scale[min(max(level, 1), 6) - 1], weight: .bold)
            s.addAttribute(.font, value: font, range: block.range)
            for inline in block.inlines { style(inline, in: s, font: font) }
        case .paragraph:
            for inline in block.inlines { style(inline, in: s, font: baseFont) }
        case .blockQuote:
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: block.range)
        case .list, .listItem:
            break
        case .codeBlock(let code):
            s.addAttribute(.backgroundColor, value: Self.codeBackground, range: block.range)
            if !nested, let language = CodeHighlighter.language(named: code.language) {
                let base = code.contentRange.location
                var units = Array(code.code.utf16)
                if units.last == 10 { units.removeLast() }
                // Indented fences strip leading spaces, so offsets would drift.
                guard units.count == code.contentRange.length else { break }
                for token in CodeHighlighter.tokens(units, language: language) {
                    let r = NSRange(location: base + token.range.location, length: token.range.length)
                    guard NSMaxRange(r) <= NSMaxRange(code.contentRange) else { continue }
                    s.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: r)
                }
            }
        case .htmlBlock:
            s.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: block.range)
        case .thematicBreak:
            s.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: block.range)
        case .table(let table):
            for row in [table.header] + table.rows {
                for cell in row.cells {
                    for inline in cell.inlines { style(inline, in: s, font: baseFont) }
                }
            }
            s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseSize, weight: .semibold),
                           range: table.header.range)
        }
        for child in block.children {
            style(child, in: s, nested: nested || block.kindIsContainer)
        }
        dim(block.markers, in: s)
    }

    // MARK: Inlines

    private func style(_ inline: Inline, in s: NSTextStorage, font: NSFont) {
        var childFont = font
        switch inline.kind {
        case .strong:
            childFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            s.addAttribute(.font, value: childFont, range: inline.range)
        case .emphasis:
            childFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            s.addAttribute(.font, value: childFont, range: inline.range)
        case .strikethrough:
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inline.range)
        case .code:
            s.addAttributes([.foregroundColor: NSColor.systemPink, .backgroundColor: Self.codeBackground],
                            range: inline.range)
        case .math:
            s.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: inline.range)
        case .link, .image:
            s.addAttribute(.foregroundColor, value: NSColor.linkColor, range: inline.range)
        case .html:
            s.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: inline.range)
        case .text, .softBreak, .hardBreak:
            break
        }
        for child in inline.children { style(child, in: s, font: childFont) }
        dim(inline.markers, in: s)
    }

    private func dim(_ ranges: [NSRange], in s: NSTextStorage) {
        for r in ranges where r.length > 0 && NSMaxRange(r) <= s.length {
            s.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r)
        }
    }

    // MARK: Palette

    private static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.08)

    static func color(for kind: CodeHighlighter.TokenKind) -> NSColor {
        switch kind {
        case .keyword: .systemPink
        case .comment: .secondaryLabelColor
        case .string: .systemRed
        case .number: .systemBlue
        case .type: .systemTeal
        case .attribute: .systemOrange
        case .variable: .systemIndigo
        }
    }
}

private extension Block {
    var kindIsContainer: Bool {
        switch kind {
        case .blockQuote, .list, .listItem: true
        default: false
        }
    }
}
