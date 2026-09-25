import Foundation
import Testing

@testable import LUAM

/// Same notation as MarkdownEditingTests: `|` marks the caret, `|…|` a selection.
private func apply(_ marked: String, _ edit: (String, NSRange) -> TextEdit?) -> String? {
    let parts = marked.components(separatedBy: "|")
    let text = parts.joined()
    let start = (parts[0] as NSString).length
    let selection = NSRange(location: start, length: parts.count == 3 ? (parts[1] as NSString).length : 0)
    guard let result = edit(text, selection) else { return nil }
    let out = result.applied(to: text) as NSString
    let head = out.substring(to: result.selection.location)
    let body = out.substring(with: result.selection)
    let tail = out.substring(from: NSMaxRange(result.selection))
    return result.selection.length == 0 ? head + "|" + tail : head + "|" + body + "|" + tail
}

@Suite struct HeadingFormatTests {
    private func heading(_ level: Int, _ marked: String) -> String? {
        apply(marked) { MarkdownEditing.setHeading(level: level, in: $0, selection: $1) }
    }

    @Test func addsAHeading() {
        #expect(heading(2, "Ti|tle") == "## Ti|tle")
        #expect(heading(1, "|") == "# |")
    }

    @Test func changesTheLevel() {
        #expect(heading(3, "# Ti|tle") == "### Ti|tle")
        #expect(heading(1, "###   Title|") == "# Title|")
    }

    @Test func sameLevelToggles() {
        #expect(heading(2, "## Ti|tle") == "Ti|tle")
        #expect(heading(0, "#### Ti|tle") == "Ti|tle")
        #expect(heading(0, "Plain|") == nil)
    }

    @Test func keepsQuoteMarkers() {
        #expect(heading(2, "> Ti|tle") == "> ## Ti|tle")
    }

    @Test func coversEveryTouchedLine() {
        #expect(heading(2, "|a\n\nb|") == "|## a\n\n## b|")
    }
}

@Suite struct LineStyleTests {
    private func toggle(_ style: MarkdownEditing.LineStyle, _ marked: String) -> String? {
        apply(marked) { MarkdownEditing.toggleLineStyle(style, in: $0, selection: $1) }
    }

    @Test func quotesAndUnquotes() {
        #expect(toggle(.quote, "|a\nb|") == "|> a\n> b|")
        #expect(toggle(.quote, "> a|") == "a|")
        #expect(toggle(.quote, "|") == ">|")
    }

    @Test func makesBullets() {
        #expect(toggle(.bullet, "|a\nb|") == "|- a\n- b|")
        #expect(toggle(.bullet, "- a|") == "a|")
    }

    @Test func numbersFromOne() {
        #expect(toggle(.numbered, "|a\n\nb\nc|") == "|1. a\n\n2. b\n3. c|")
    }

    @Test func switchesListKinds() {
        #expect(toggle(.numbered, "- a|") == "1. a|")
        #expect(toggle(.task, "1. a|") == "- [ ] a|")
        #expect(toggle(.bullet, "- [x] a|") == "- a|")
        #expect(toggle(.task, "- [x] a|") == "a|")
    }

    @Test func keepsIndentAndQuote() {
        #expect(toggle(.bullet, "    a|") == "    - a|")
        #expect(toggle(.bullet, "> a|") == "> - a|")
    }

    @Test func mixedSelectionAddsToAll() {
        #expect(toggle(.bullet, "|- a\nb|") == "|- a\n- b|")
    }
}

@Suite struct OutlineTests {
    @Test func listsHeadingsWithAnchors() {
        let tree = parse("# Intro\ntext\n## Intro\n> ### Quoted *heading*\n\nSetext\n---")
        let items = DocumentOutline.items(in: tree)
        #expect(items.map(\.title) == ["Intro", "Intro", "Quoted heading", "Setext"])
        #expect(items.map(\.level) == [1, 2, 3, 2])
        #expect(items.map(\.line) == [1, 3, 4, 6])
        #expect(items.map(\.anchor) == ["intro", "intro-1", "quoted-heading", "setext"])
    }

    @Test func anchorsMatchTheRenderer() {
        let source = "# A b\n# A b\n# Ünïcode!"
        let html = HTMLRenderer().render(parse(source))
        for item in DocumentOutline.items(in: parse(source)) {
            #expect(html.contains("id=\"\(item.anchor)\""))
        }
    }

    @Test func findsTheCurrentSection() {
        let items = DocumentOutline.items(in: parse("intro\n\n# One\n\n# Two\n"))
        #expect(DocumentOutline.item(containing: 1, in: items)?.title == "One")
        #expect(DocumentOutline.item(containing: 4.5, in: items)?.title == "One")
        #expect(DocumentOutline.item(containing: 5, in: items)?.title == "Two")
    }
}
