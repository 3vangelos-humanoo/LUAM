import Testing
@testable import LUAM

@Suite("Inlines")
struct InlineParserTests {
    @Test func emphasis() {
        #expect(html("*a* _b_") == "<p><em>a</em> <em>b</em></p>\n")
        #expect(html("**a** __b__") == "<p><strong>a</strong> <strong>b</strong></p>\n")
        #expect(html("***a***") == "<p><em><strong>a</strong></em></p>\n")
        #expect(html("*a **b** c*") == "<p><em>a <strong>b</strong> c</em></p>\n")
        #expect(html("snake_case_name") == "<p>snake_case_name</p>\n")
        #expect(html("* not em *") == "<ul>\n<li>not em *</li>\n</ul>\n")
        #expect(html("a * b * c") == "<p>a * b * c</p>\n")
        #expect(html("**unclosed") == "<p>**unclosed</p>\n")
    }

    @Test func strikethrough() {
        #expect(html("~~gone~~") == "<p><del>gone</del></p>\n")
        #expect(html("~one~") == "<p><del>one</del></p>\n")
    }

    @Test func codeSpans() {
        #expect(html("`code`") == "<p><code>code</code></p>\n")
        #expect(html("`` a`b ``") == "<p><code>a`b</code></p>\n")
        #expect(html("`<*>`") == "<p><code>&lt;*&gt;</code></p>\n")
        #expect(html("`unclosed") == "<p>`unclosed</p>\n")
    }

    @Test func links() {
        #expect(html("[a](/b)") == "<p><a href=\"/b\">a</a></p>\n")
        #expect(html("[a](/b \"t\")") == "<p><a href=\"/b\" title=\"t\">a</a></p>\n")
        #expect(html("[a](<with space>)") == "<p><a href=\"with%20space\">a</a></p>\n")
        #expect(html("[*em*](u)") == "<p><a href=\"u\"><em>em</em></a></p>\n")
        #expect(html("[not a link]") == "<p>[not a link]</p>\n")
        #expect(html("[a](b(c))") == "<p><a href=\"b(c)\">a</a></p>\n")
    }

    @Test func images() {
        #expect(html("![alt *x*](i.png)") == "<p><img src=\"i.png\" alt=\"alt x\" /></p>\n")
    }

    @Test func autolinks() {
        #expect(html("<https://x.org>") == "<p><a href=\"https://x.org\">https://x.org</a></p>\n")
        #expect(html("<me@x.org>") == "<p><a href=\"mailto:me@x.org\">me@x.org</a></p>\n")
        #expect(html("see https://x.org/a.") == "<p>see <a href=\"https://x.org/a\">https://x.org/a</a>.</p>\n")
        #expect(html("www.x.org") == "<p><a href=\"http://www.x.org\">www.x.org</a></p>\n")
    }

    @Test func escapesAndEntities() {
        #expect(html("\\*not\\*") == "<p>*not*</p>\n")
        #expect(html("&copy; &amp; &#65;") == "<p>© &amp; A</p>\n")
        #expect(html("a < b & c") == "<p>a &lt; b &amp; c</p>\n")
    }

    @Test func breaks() {
        #expect(html("a  \nb") == "<p>a<br />\nb</p>\n")
        #expect(html("a\\\nb") == "<p>a<br />\nb</p>\n")
        #expect(html("a\nb") == "<p>a\nb</p>\n")
    }

    @Test func inlineHTML() {
        #expect(html("a <b>c</b>") == "<p>a <b>c</b></p>\n")
    }

    @Test(.timeLimit(.minutes(1)))
    func pathologicalInputFinishesQuickly() {
        let clock = ContinuousClock()
        for input in [String(repeating: "*", count: 2000), String(repeating: "[", count: 2000),
                      String(repeating: "*a ", count: 2000), String(repeating: "[a](", count: 1000),
                      String(repeating: "> ", count: 500) + "x", String(repeating: "`", count: 2000) + "x"] {
            let elapsed = clock.measure { _ = html(input) }
            #expect(elapsed < .seconds(1), "slow on \(input.prefix(8))…")
        }
    }
}
