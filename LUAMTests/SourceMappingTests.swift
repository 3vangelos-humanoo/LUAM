import Foundation
import Testing
@testable import LUAM

/// The editor styles text straight from parser ranges, so they must be exact
/// UTF-16 offsets — including after emoji and inside nested containers.
@Suite("Source ranges")
struct SourceMappingTests {
    @Test func headingRangeAndMarkers() throws {
        let md = "intro\n\n## Title ##\n"
        let heading = try #require(parse(md).blocks.last)
        #expect(heading.line == 3)
        #expect(slice(md, heading.range) == "## Title ##")
        #expect(heading.markers.map { slice(md, $0) }.contains("##"))
        #expect(slice(md, try #require(heading.inlines.first).range) == "Title")
    }

    @Test func emphasisAfterEmoji() throws {
        let md = "👩‍💻 **bold** end"
        let strong = try #require(parse(md).blocks.first?.inlines.first { $0.kind == .strong })
        #expect(slice(md, strong.range) == "**bold**")
        #expect(strong.markers.map { slice(md, $0) } == ["**", "**"])
        #expect(slice(md, try #require(strong.children.first).range) == "bold")
    }

    @Test func linkInsideQuotedList() throws {
        let md = "> - item [link](http://x)\n"
        let quote = try #require(parse(md).blocks.first)
        let item = try #require(quote.children.first?.children.first)
        #expect(item.line == 1)
        let link = try #require(item.children.first?.inlines.first { if case .link = $0.kind { true } else { false } })
        #expect(slice(md, link.range) == "[link](http://x)")
    }

    @Test func codeBlockContentRange() throws {
        let md = "text\n\n```js\nlet a\n```\n"
        let block = try #require(parse(md).blocks.last)
        guard case .codeBlock(let code) = block.kind else { Issue.record("not code"); return }
        #expect(block.line == 3)
        #expect(block.endLine == 5)
        #expect(slice(md, code.contentRange) == "let a")
    }

    @Test func crlfLines() throws {
        let md = "# A\r\n\r\npara\r\n"
        let tree = parse(md)
        #expect(tree.blocks.count == 2)
        #expect(tree.blocks[1].line == 3)
        #expect(slice(md, tree.blocks[1].range) == "para")
    }

    @Test func dataLineAttributes() {
        let out = HTMLRenderer().render(parse("# H\n\npara\n\n- a\n- b\n"))
        #expect(out.contains("<h1 id=\"h\" data-line=\"1\">"))
        #expect(out.contains("<p data-line=\"3\">"))
        #expect(out.contains("<ul data-line=\"5\">"))
        #expect(out.contains("<li data-line=\"6\">"))
    }

    @Test func headingSlugsAreUnique() {
        let out = HTMLRenderer().render(parse("# Hello, World!\n# Hello, World!\n# Hello, World!"))
        #expect(out.contains("id=\"hello-world\""))
        #expect(out.contains("id=\"hello-world-1\""))
        #expect(out.contains("id=\"hello-world-2\""))
    }
}
