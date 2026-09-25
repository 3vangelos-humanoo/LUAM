import Foundation

/// A small, forgiving tokenizer for fenced code. It knows just enough about a
/// handful of languages to color keywords, strings, comments and numbers; the
/// same tokens feed the preview (`tok-*` spans) and the editor's styler.
nonisolated enum CodeHighlighter {
    nonisolated enum TokenKind: String, Sendable, Equatable {
        case keyword, comment, string, number, type, attribute, variable
    }

    nonisolated struct Token: Sendable, Equatable {
        var kind: TokenKind
        /// UTF-16 range within the highlighted code.
        var range: NSRange
    }

    nonisolated struct Language: Sendable {
        var keywords: Set<String>
        var lineComments: [String]
        var blockComment: (open: String, close: String)?
        var tripleQuotes: Bool
        var singleQuoteStrings: Bool
        var backtickStrings: Bool
        /// `@name` is an attribute / decorator.
        var attributes: Bool
        /// `$name` is a variable.
        var variables: Bool
        /// Capitalized identifiers are types.
        var capitalizedTypes: Bool
    }

    static func language(named name: String?) -> Language? {
        guard let name = name?.lowercased() else { return nil }
        switch name {
        case "swift": return swift
        case "js", "javascript", "ts", "typescript", "jsx", "tsx", "mjs", "cjs": return javaScript
        case "json", "jsonc": return json
        case "sh", "bash", "zsh", "shell", "console": return shell
        case "python", "py": return python
        default: return nil
        }
    }

    static func tokens(_ code: String, language name: String?) -> [Token] {
        guard let language = language(named: name) else { return [] }
        return tokens(Array(code.utf16), language: language)
    }

    static func tokens(_ u: [UInt16], language l: Language) -> [Token] {
        var result: [Token] = []
        let n = u.count
        var i = 0

        func has(_ s: String, at i: Int) -> Bool {
            var k = i
            for c in s.utf16 {
                guard k < n, u[k] == c else { return false }
                k += 1
            }
            return true
        }
        func add(_ kind: TokenKind, _ start: Int, _ end: Int) {
            result.append(Token(kind: kind, range: NSRange(location: start, length: end - start)))
        }
        func isIdentStart(_ c: UInt16) -> Bool {
            C.isASCIILetter(c) || c == C.underscore || c >= 0x80
        }
        func isIdent(_ c: UInt16) -> Bool {
            isIdentStart(c) || C.isDigit(c)
        }
        func lineEnd(from i: Int) -> Int {
            var k = i
            while k < n, u[k] != C.lf { k += 1 }
            return k
        }

        outer: while i < n {
            let c = u[i]

            for marker in l.lineComments where has(marker, at: i) {
                // In shells `#` only starts a comment at a word boundary.
                if marker == "#", i > 0, !C.isWhitespace(u[i - 1]) { break }
                let end = lineEnd(from: i)
                add(.comment, i, end)
                i = end
                continue outer
            }
            if let block = l.blockComment, has(block.open, at: i) {
                var k = i + block.open.utf16.count
                while k < n, !has(block.close, at: k) { k += 1 }
                k = min(n, k + block.close.utf16.count)
                add(.comment, i, k)
                i = k
                continue
            }
            if l.tripleQuotes, has("\"\"\"", at: i) || has("'''", at: i) {
                let q = u[i]
                var k = i + 3
                while k < n, !(u[k] == q && k + 2 < n && u[k + 1] == q && u[k + 2] == q) {
                    k += u[k] == C.backslash ? 2 : 1
                }
                k = min(n, k + 3)
                add(.string, i, k)
                i = k
                continue
            }
            if c == C.quote || (c == C.apos && l.singleQuoteStrings) || (c == C.backtick && l.backtickStrings) {
                var k = i + 1
                while k < n, u[k] != c {
                    if u[k] == C.backslash { k += 1 } else if u[k] == C.lf && c != C.backtick { break }
                    k += 1
                }
                k = min(n, k + 1)
                add(.string, i, k)
                i = k
                continue
            }
            if C.isDigit(c), i == 0 || !isIdent(u[i - 1]) {
                var k = i + 1
                while k < n, isIdent(u[k]) || (u[k] == C.dot && k + 1 < n && C.isDigit(u[k + 1])) { k += 1 }
                add(.number, i, k)
                i = k
                continue
            }
            if (c == C.at && l.attributes) || (c == C.dollar && l.variables),
               i + 1 < n, isIdentStart(u[i + 1]) || (c == C.dollar && (u[i + 1] == C.lbrace || C.isDigit(u[i + 1]))) {
                var k = i + 1
                if u[k] == C.lbrace {
                    while k < n, u[k] != C.rbrace, u[k] != C.lf { k += 1 }
                    k = min(n, k + 1)
                } else {
                    while k < n, isIdent(u[k]) || u[k] == C.dot && c == C.at { k += 1 }
                }
                add(c == C.at ? .attribute : .variable, i, k)
                i = k
                continue
            }
            if isIdentStart(c) {
                var k = i + 1
                while k < n, isIdent(u[k]) { k += 1 }
                let word = String(utf16CodeUnits: Array(u[i..<k]), count: k - i)
                let precededByDot = i > 0 && u[i - 1] == C.dot
                if l.keywords.contains(word), !precededByDot {
                    add(.keyword, i, k)
                } else if l.capitalizedTypes, C.isASCIILetter(c), c < 0x5B {
                    add(.type, i, k)
                }
                i = k
                continue
            }
            i += 1
        }
        return result
    }

    // MARK: - Languages

    static let swift = Language(
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class",
            "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough",
            "false", "fileprivate", "final", "for", "func", "guard", "if", "import", "in", "indirect",
            "init", "inout", "internal", "is", "isolated", "lazy", "let", "mutating", "nil", "nonisolated",
            "open", "operator", "override", "private", "protocol", "public", "repeat", "rethrows", "return",
            "self", "Self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
            "true", "try", "typealias", "var", "where", "while", "weak", "unowned", "consuming", "borrowing",
        ],
        lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: true,
        singleQuoteStrings: false, backtickStrings: false, attributes: true, variables: false,
        capitalizedTypes: true
    )

    static let javaScript = Language(
        keywords: [
            "abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally",
            "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let",
            "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super",
            "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while",
            "with", "yield",
        ],
        lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: false,
        singleQuoteStrings: true, backtickStrings: true, attributes: true, variables: false,
        capitalizedTypes: true
    )

    static let json = Language(
        keywords: ["true", "false", "null"],
        lineComments: [], blockComment: nil, tripleQuotes: false,
        singleQuoteStrings: false, backtickStrings: false, attributes: false, variables: false,
        capitalizedTypes: false
    )

    static let shell = Language(
        keywords: [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
            "in", "function", "return", "export", "local", "readonly", "set", "unset", "source", "echo",
            "exit", "cd", "alias",
        ],
        lineComments: ["#"], blockComment: nil, tripleQuotes: false,
        singleQuoteStrings: true, backtickStrings: true, attributes: false, variables: true,
        capitalizedTypes: false
    )

    static let python = Language(
        keywords: [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
            "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while",
            "with", "yield", "match", "case", "self",
        ],
        lineComments: ["#"], blockComment: nil, tripleQuotes: true,
        singleQuoteStrings: true, backtickStrings: false, attributes: true, variables: false,
        capitalizedTypes: true
    )
}
