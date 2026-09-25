import Foundation
@testable import LUAM

/// Parses and renders with every decoration off, so expectations can be copied
/// from the CommonMark / GFM specs verbatim.
func html(_ markdown: String) -> String {
    HTMLRenderer(options: .plain).render(MarkdownParser().parse(markdown))
}

func parse(_ markdown: String) -> MarkdownTree {
    MarkdownParser().parse(markdown)
}

/// The source text an `NSRange` from the parser covers.
func slice(_ markdown: String, _ range: NSRange) -> String {
    (markdown as NSString).substring(with: range)
}
