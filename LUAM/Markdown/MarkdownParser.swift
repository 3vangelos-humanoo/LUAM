import Foundation

/// The seam between LUAM and whatever turns Markdown into a tree. The app only
/// ever talks to this protocol, so the hand-written parser could be swapped for
/// swift-markdown later without touching the styler or the renderer.
nonisolated protocol MarkdownParsing: Sendable {
    func parse(_ text: String) -> MarkdownTree
}

/// CommonMark + GFM (tables, task lists, strikethrough, autolinks), parsed in
/// two passes: blocks first — which also collects link reference definitions —
/// then inlines, once every definition is known.
nonisolated struct MarkdownParser: MarkdownParsing {
    func parse(_ text: String) -> MarkdownTree {
        let source = SourceText(text)
        let blockParser = BlockParser(units: source.units)
        let pending = blockParser.parse(source.lines)
        let inlineParser = InlineParser(units: source.units, definitions: blockParser.definitions)
        return MarkdownTree(
            blocks: pending.map { $0.finalize(inlineParser) },
            sourceLength: source.units.count,
            lineCount: source.lines.count
        )
    }
}
