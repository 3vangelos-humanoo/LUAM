import Foundation

/// One heading in the outline sidebar.
nonisolated struct OutlineItem: Identifiable, Equatable, Sendable {
    /// Position among the document's headings; stable while typing elsewhere.
    var id: Int
    var level: Int
    var title: String
    /// Source line of the heading (1-based), for scrolling both panes.
    var line: Int
    /// The heading's `id` in the preview and in exported HTML.
    var anchor: String
}

nonisolated enum DocumentOutline {
    /// Every heading in document order, including those nested in quotes and
    /// lists — the same walk, and the same anchors, as `HTMLRenderer`.
    static func items(in tree: MarkdownTree) -> [OutlineItem] {
        var slugs = HeadingSlugs()
        var items: [OutlineItem] = []
        tree.forEachBlock { block in
            guard case .heading(let level) = block.kind else { return }
            let text = block.inlines.plainText
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(OutlineItem(
                id: items.count,
                level: level,
                title: title.isEmpty ? "Untitled" : title,
                line: block.line,
                anchor: slugs.next(for: text)
            ))
        }
        return items
    }

    /// The heading whose section contains `line`: the last one at or above it.
    static func item(containing line: Double, in items: [OutlineItem]) -> OutlineItem? {
        items.last { Double($0.line) <= line + 0.01 } ?? items.first
    }
}
