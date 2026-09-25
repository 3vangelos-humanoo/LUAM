import Testing
@testable import LUAM

@Suite("Blocks")
struct BlockParserTests {
    @Test func atxHeadings() {
        #expect(html("# One\n## Two\n###### Six") == "<h1>One</h1>\n<h2>Two</h2>\n<h6>Six</h6>\n")
        #expect(html("####### Seven") == "<p>####### Seven</p>\n")
        #expect(html("#NoSpace") == "<p>#NoSpace</p>\n")
        #expect(html("## Closed ##") == "<h2>Closed</h2>\n")
        #expect(html("#") == "<h1></h1>\n")
    }

    @Test func setextHeadings() {
        #expect(html("Title\n=====") == "<h1>Title</h1>\n")
        #expect(html("Sub\n---") == "<h2>Sub</h2>\n")
        #expect(html("Two\nlines\n===") == "<h1>Two\nlines</h1>\n")
    }

    @Test func paragraphs() {
        #expect(html("aaa\nbbb\n\nccc") == "<p>aaa\nbbb</p>\n<p>ccc</p>\n")
        #expect(html("   indented") == "<p>indented</p>\n")
        #expect(html("") == "")
        #expect(html("\n\n\n") == "")
    }

    @Test func thematicBreaks() {
        #expect(html("***\n---\n___") == "<hr />\n<hr />\n<hr />\n")
        #expect(html(" - - -") == "<hr />\n")
        #expect(html("--") == "<p>--</p>\n")
    }

    @Test func fencedCode() {
        #expect(html("```\n<a>\n```") == "<pre><code>&lt;a&gt;\n</code></pre>\n")
        #expect(html("```swift\nlet x = 1\n```") == "<pre><code class=\"language-swift\">let x = 1\n</code></pre>\n")
        #expect(html("~~~\ncode\n~~~") == "<pre><code>code\n</code></pre>\n")
        #expect(html("````\n```\n````") == "<pre><code>```\n</code></pre>\n")
        // An unclosed fence runs to the end of the document.
        #expect(html("```\nopen") == "<pre><code>open\n</code></pre>\n")
        // Fence indentation is removed from content lines.
        #expect(html("  ```\n  aa\n   b\n  ```") == "<pre><code>aa\n b\n</code></pre>\n")
    }

    @Test func indentedCode() {
        #expect(html("    code\n    more") == "<pre><code>code\nmore\n</code></pre>\n")
        #expect(html("para\n    not code") == "<p>para\nnot code</p>\n")
    }

    @Test func blockQuotes() {
        #expect(html("> quote") == "<blockquote>\n<p>quote</p>\n</blockquote>\n")
        #expect(html("> a\nlazy") == "<blockquote>\n<p>a\nlazy</p>\n</blockquote>\n")
        #expect(html("> > nested") == "<blockquote>\n<blockquote>\n<p>nested</p>\n</blockquote>\n</blockquote>\n")
        #expect(html("> # H") == "<blockquote>\n<h1>H</h1>\n</blockquote>\n")
    }

    @Test func bulletLists() {
        #expect(html("- a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n")
        #expect(html("- a\n\n- b") == "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n")
        #expect(html("- a\n+ b") == "<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>\n")
        #expect(html("- a\n  - b") == "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n")
    }

    @Test func orderedLists() {
        #expect(html("1. a\n2. b") == "<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n")
        #expect(html("3) c") == "<ol start=\"3\">\n<li>c</li>\n</ol>\n")
        // Only a list starting at 1 may interrupt a paragraph.
        #expect(html("text\n2. no") == "<p>text\n2. no</p>\n")
    }

    @Test func taskLists() {
        let out = html("- [ ] todo\n- [x] done")
        #expect(out == "<ul class=\"contains-task-list\">\n<li class=\"task-list-item\"><input type=\"checkbox\" disabled> todo</li>\n<li class=\"task-list-item\"><input type=\"checkbox\" disabled checked> done</li>\n</ul>\n")
    }

    @Test func tables() {
        let md = "| a | b |\n|:--|--:|\n| 1 | 2 |"
        #expect(html(md) == """
        <table>
        <thead>
        <tr>
        <th style="text-align: left">a</th>
        <th style="text-align: right">b</th>
        </tr>
        </thead>
        <tbody>
        <tr>
        <td style="text-align: left">1</td>
        <td style="text-align: right">2</td>
        </tr>
        </tbody>
        </table>

        """)
        // Delimiter row with the wrong cell count: not a table.
        #expect(html("| a | b |\n|---|\n") == "<p>| a | b |\n|---|</p>\n")
        // Escaped pipes stay in the cell.
        #expect(html("| a \\| b |\n|---|").contains("<th>a | b</th>"))
    }

    @Test func htmlBlocks() {
        #expect(html("<div>\n*x*\n</div>") == "<div>\n*x*\n</div>\n")
        #expect(html("<!-- c -->\npara") == "<!-- c -->\n<p>para</p>\n")
    }

    @Test func linkReferenceDefinitions() {
        #expect(html("[foo]: /url \"title\"\n\n[foo]") == "<p><a href=\"/url\" title=\"title\">foo</a></p>\n")
        #expect(html("[Foo]\n\n[foo]: /u") == "<p><a href=\"/u\">Foo</a></p>\n")
    }
}
