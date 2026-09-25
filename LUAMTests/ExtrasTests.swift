import Foundation
import Testing

@testable import LUAM

@Suite struct TaskToggleTests {
    private func toggled(_ text: String, line: Int) -> String? {
        MarkdownEditing.toggleTask(in: text, line: line, selection: NSRange(location: 0, length: 0))?.applied(to: text)
    }

    @Test func flipsTheBox() {
        #expect(toggled("- [ ] a\n- [x] b", line: 1) == "- [x] a\n- [x] b")
        #expect(toggled("- [ ] a\n- [X] b", line: 2) == "- [ ] a\n- [ ] b")
    }

    @Test func handlesNestingAndQuotes() {
        #expect(toggled("> 1. [ ] a", line: 1) == "> 1. [x] a")
        #expect(toggled("- a\n    - [ ] b", line: 2) == "- a\n    - [x] b")
    }

    @Test func ignoresOtherLines() {
        #expect(toggled("- a", line: 1) == nil)
        #expect(toggled("- [ ] a", line: 5) == nil)
    }

    @Test func matchesTheRenderedLine() {
        let source = "intro\n\n- [ ] one\n- [x] two\n"
        let html = HTMLRenderer().render(parse(source))
        #expect(html.contains("<input type=\"checkbox\" data-task-line=\"3\"> "))
        #expect(html.contains("<input type=\"checkbox\" data-task-line=\"4\" checked> "))
        #expect(toggled(source, line: 4) == "intro\n\n- [ ] one\n- [ ] two\n")
    }
}

@Suite struct ParagraphRangeTests {
    @Test func spansNonBlankLines() {
        let text = "a\n\nb\nc\n\nd"
        let range = MarkdownEditing.paragraphRange(in: text, at: 3)
        #expect((text as NSString).substring(with: range) == "b\nc")
    }

    @Test func blankLineIsItsOwnRange() {
        #expect(MarkdownEditing.paragraphRange(in: "a\n\nb", at: 2) == NSRange(location: 2, length: 0))
        #expect(MarkdownEditing.paragraphRange(in: "", at: 0) == NSRange(location: 0, length: 0))
    }
}

@Suite struct RenumberAfterMoveTests {
    @Test func closesTheGapLeftBehind() {
        let text = "1. a\n2. b\n3. c\n4. d"
        let indented = MarkdownEditing.indent(in: text, selection: NSRange(location: 6, length: 0))!
        let moved = indented.applied(to: text)
        #expect(moved == "1. a\n    2. b\n3. c\n4. d")
        let fixed = MarkdownEditing.renumberAfterMove(in: moved, selection: indented.selection)
        #expect(fixed?.applied(to: moved) == "1. a\n    2. b\n2. c\n3. d")
    }

    @Test func leavesCorrectListsAlone() {
        let text = "1. a\n    1. b\n2. c"
        #expect(MarkdownEditing.renumberAfterMove(in: text, selection: NSRange(location: 9, length: 0)) == nil)
    }

    @Test func differenceIsMinimal() {
        let edit = MarkdownEditing.difference(from: "9. a\n10. b", to: "1. a\n2. b", selection: NSRange(location: 0, length: 0))
        #expect(edit?.range == NSRange(location: 0, length: 7))
        #expect(edit?.replacement == "1. a\n2")
    }
}

@Suite struct MathTests {
    @Test func inlineAndDisplay() {
        let out = HTMLRenderer().render(parse("Area $\\pi r^2$ and\n\n$$\na_1 * b_2\n$$"))
        #expect(out.contains("<span class=\"luam-math\">\\pi r^2</span>"))
        #expect(out.contains("<span class=\"luam-math luam-math-display\">\na_1 * b_2\n</span>"))
    }

    @Test func pricesStayText() {
        #expect(html("costs $5 and $10") == "<p>costs $5 and $10</p>\n")
        #expect(html("$ x $") == "<p>$ x $</p>\n")
        #expect(html("escaped \\$x$") == "<p>escaped $x$</p>\n")
    }

    @Test func mathIsVerbatim() {
        let tree = parse("$a*b*c_d$")
        guard case .math(let tex, let display) = tree.blocks[0].inlines.first?.kind else {
            Issue.record("expected math")
            return
        }
        #expect(tex == "a*b*c_d")
        #expect(!display)
        #expect(tree.blocks[0].inlines[0].markers.count == 2)
    }

    @Test func plainModeKeepsTheSource() {
        #expect(html("x $y$") == "<p>x $y$</p>\n")
    }

    @Test func fencedMathAndMermaid() {
        let out = HTMLRenderer().render(parse("```math\nx^2\n```\n\n```mermaid\ngraph TD; A-->B\n```"))
        #expect(out.contains("<div class=\"luam-math luam-math-display\" data-line=\"1\">x^2\n</div>"))
        #expect(out.contains("<pre class=\"mermaid\" data-line=\"5\">graph TD; A--&gt;B\n</pre>"))
    }

    @Test func manyDollarsStayFast() {
        let text = String(repeating: "$a ", count: 20_000)
        let start = Date()
        _ = parse(text)
        #expect(Date().timeIntervalSince(start) < 2)
    }
}

@Suite struct PastedImageTests {
    @Test func namesFromTheDocument() {
        let date = Date(timeIntervalSince1970: 0)
        let name = PastedImage.fileName(documentName: "My Notes", date: date)
        #expect(name.hasPrefix("my-notes-19700101-") || name.hasPrefix("my-notes-1969"))
        #expect(name.hasSuffix(".png"))
        #expect(PastedImage.fileName(documentName: nil, date: date, index: 2).hasSuffix("-3.png"))
        #expect(PastedImage.fileName(documentName: "!!!", date: date).hasPrefix("image-"))
    }
}
