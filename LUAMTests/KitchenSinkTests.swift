import Foundation
import Testing
@testable import LUAM

@Suite("Kitchen sink")
struct KitchenSinkTests {
    private static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Samples/Kitchen-Sink.md")

    @Test func rendersEveryConstruct() throws {
        let markdown = try String(contentsOf: Self.url, encoding: .utf8)
        let out = HTMLRenderer().render(parse(markdown))
        for fragment in ["<h1 id=\"kitchen-sink\"", "<h6", "<em>emphasis</em>", "<strong>strong</strong>",
                         "<del>struck</del>", "<br />", "©", "href=\"https://example.com/reference\"",
                         "<img src=\"image.png\"", "<ol start=\"7\"", "contains-task-list", "checked",
                         "<blockquote", "tok-keyword", "tok-comment", "language-json", "<table",
                         "text-align: center", "<details>", "<kbd>", "<hr", "👩‍💻"] {
            #expect(out.contains(fragment), "missing \(fragment)")
        }
    }

    @Test func rangesStayInsideTheSource() throws {
        let markdown = try String(contentsOf: Self.url, encoding: .utf8)
        let tree = parse(markdown)
        let length = (markdown as NSString).length
        func check(_ range: NSRange) { #expect(range.location >= 0 && NSMaxRange(range) <= length) }
        func visit(_ inline: Inline) { check(inline.range); inline.markers.forEach(check); inline.children.forEach(visit) }
        func visit(_ block: Block) {
            check(block.range); block.markers.forEach(check)
            #expect(block.line >= 1 && block.line <= block.endLine && block.endLine <= tree.lineCount)
            block.inlines.forEach(visit); block.children.forEach(visit)
        }
        tree.blocks.forEach(visit)
    }
}
