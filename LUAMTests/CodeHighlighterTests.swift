import Foundation
import Testing
@testable import LUAM

@Suite("Code highlighting")
struct CodeHighlighterTests {
    private func kinds(_ code: String, _ language: String) -> [String: CodeHighlighter.TokenKind] {
        var result: [String: CodeHighlighter.TokenKind] = [:]
        for token in CodeHighlighter.tokens(code, language: language) {
            result[slice(code, token.range)] = token.kind
        }
        return result
    }

    @Test func swift() {
        let k = kinds("@MainActor let x: Int = 42 // hi\n\"s\"", "swift")
        #expect(k["@MainActor"] == .attribute)
        #expect(k["let"] == .keyword)
        #expect(k["Int"] == .type)
        #expect(k["42"] == .number)
        #expect(k["// hi"] == .comment)
        #expect(k["\"s\""] == .string)
        #expect(k["x"] == nil)
    }

    @Test func shellComments() {
        let k = kinds("echo $HOME # note\nurl#frag", "bash")
        #expect(k["echo"] == .keyword)
        #expect(k["$HOME"] == .variable)
        #expect(k["# note"] == .comment)
        #expect(k["#frag"] == nil)
    }

    @Test func unknownLanguage() {
        #expect(CodeHighlighter.tokens("let x", language: "cobol").isEmpty)
        #expect(CodeHighlighter.tokens("let x", language: nil).isEmpty)
    }

    @Test func unterminatedConstructsDoNotCrash() {
        for code in ["\"open", "/* open", "\"\"\"", "@", "$", "${"] {
            _ = CodeHighlighter.tokens(code, language: "swift")
            _ = CodeHighlighter.tokens(code, language: "bash")
        }
    }

    @Test func rendererWrapsTokens() {
        let out = HTMLRenderer().render(parse("```swift\nlet a = \"<b>\"\n```"))
        #expect(out.contains("<span class=\"tok-keyword\">let</span> a = <span class=\"tok-string\">&quot;&lt;b&gt;&quot;</span>"))
    }
}
