import Foundation

/// A stretch of source that holds inline content — one line of a paragraph,
/// a heading's text, a table cell. Offsets are UTF-16 indexes into the buffer.
nonisolated struct Segment: Sendable, Equatable {
    var start: Int
    var end: Int
}

/// `[label]: destination "title"`, collected before inline parsing so that
/// reference links can be resolved regardless of where the definition sits.
nonisolated struct LinkDefinition: Sendable, Equatable {
    var destination: String
    var title: String?
}

/// Link destinations, titles and labels — shared by inline links and link
/// reference definitions.
nonisolated enum LinkSyntax {
    /// A destination starting at `start`: `<…>` or a run of non-space characters
    /// with balanced parentheses. Returns the unescaped value and the index
    /// just past it.
    static func destination(_ t: [UInt16], _ start: Int, _ limit: Int) -> (String, Int)? {
        guard start < limit else { return nil }
        if t[start] == C.lt {
            var k = start + 1
            while k < limit {
                let c = t[k]
                if c == C.gt { return (Unescape.string(t, start + 1, k), k + 1) }
                if c == C.lf || c == C.lt { return nil }
                if c == C.backslash, k + 1 < limit, C.isASCIIPunctuation(t[k + 1]) {
                    k += 2
                    continue
                }
                k += 1
            }
            return nil
        }
        var k = start
        var depth = 0
        while k < limit {
            let c = t[k]
            if c == C.backslash, k + 1 < limit, C.isASCIIPunctuation(t[k + 1]) {
                k += 2
                continue
            }
            if c <= 0x20 || c == 0x7F { break }
            if c == C.lparen {
                depth += 1
                if depth > 32 { return nil }
            } else if c == C.rparen {
                if depth == 0 { break }
                depth -= 1
            }
            k += 1
        }
        guard k > start, depth == 0 else { return nil }
        return (Unescape.string(t, start, k), k)
    }

    /// A title in `"…"`, `'…'` or `(…)`. Returns the unescaped value and the
    /// index just past the closing delimiter.
    static func title(_ t: [UInt16], _ start: Int, _ limit: Int) -> (String, Int)? {
        guard start < limit else { return nil }
        let open = t[start]
        let close: UInt16
        switch open {
        case C.quote: close = C.quote
        case C.apos: close = C.apos
        case C.lparen: close = C.rparen
        default: return nil
        }
        var k = start + 1
        while k < limit {
            let c = t[k]
            if c == C.backslash, k + 1 < limit, C.isASCIIPunctuation(t[k + 1]) {
                k += 2
                continue
            }
            if c == close { return (Unescape.string(t, start + 1, k), k + 1) }
            if open == C.lparen, c == C.lparen { return nil }
            k += 1
        }
        return nil
    }

    /// A link label starting at the `[` at `start`. Returns the end of the
    /// label's content and the index just past the `]`.
    static func label(_ t: [UInt16], _ start: Int, _ limit: Int) -> (Int, Int)? {
        var k = start + 1
        var blank = true
        while k < limit, k - start <= 1000 {
            let c = t[k]
            if c == C.backslash, k + 1 < limit, C.isASCIIPunctuation(t[k + 1]) {
                blank = false
                k += 2
                continue
            }
            if c == C.lbracket { return nil }
            if c == C.rbracket { return blank ? nil : (k, k + 1) }
            if !C.isWhitespace(c) { blank = false }
            k += 1
        }
        return nil
    }

    /// Whether `t[start..<end]` could be a label: not blank, not too long, no
    /// unescaped brackets.
    static func isValidLabel(_ t: [UInt16], _ start: Int, _ end: Int) -> Bool {
        guard end > start, end - start <= 999 else { return false }
        var blank = true
        var k = start
        while k < end {
            let c = t[k]
            if c == C.backslash, k + 1 < end {
                blank = false
                k += 2
                continue
            }
            if c == C.lbracket || c == C.rbracket { return false }
            if !C.isWhitespace(c) { blank = false }
            k += 1
        }
        return !blank
    }

    /// Case-folded, whitespace-collapsed label, used as the definitions key.
    static func normalize(_ label: String) -> String {
        label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func skipWhitespace(_ t: [UInt16], _ start: Int, _ limit: Int) -> Int {
        var k = start
        while k < limit, C.isWhitespace(t[k]) { k += 1 }
        return k
    }
}

/// Raw HTML recognition for inline HTML and HTML blocks.
nonisolated enum HTMLSyntax {
    /// Any inline HTML construct starting at the `<` at `start` — open tag,
    /// closing tag, comment, processing instruction, declaration or CDATA.
    /// Returns the index just past it.
    static func tag(_ t: [UInt16], _ start: Int, _ limit: Int) -> Int? {
        guard start + 1 < limit else { return nil }
        let c = t[start + 1]
        if C.isASCIILetter(c) { return openTag(t, start, limit) }
        if c == C.slash { return closingTag(t, start, limit) }
        if c == C.question { return find(t, "?>", start + 2, limit) }
        if c == C.bang {
            if hasPrefix(t, "<!--", start, limit) {
                if hasPrefix(t, "<!-->", start, limit) { return start + 5 }
                if hasPrefix(t, "<!--->", start, limit) { return start + 6 }
                return find(t, "-->", start + 4, limit)
            }
            if hasPrefix(t, "<![CDATA[", start, limit) { return find(t, "]]>", start + 9, limit) }
            if start + 2 < limit, C.isASCIILetter(t[start + 2]) { return find(t, ">", start + 2, limit) }
        }
        return nil
    }

    static func openTag(_ t: [UInt16], _ start: Int, _ limit: Int) -> Int? {
        var k = start + 1
        guard k < limit, C.isASCIILetter(t[k]) else { return nil }
        while k < limit, C.isASCIIAlphanumeric(t[k]) || t[k] == C.minus { k += 1 }
        while true {
            let beforeSpace = k
            k = LinkSyntax.skipWhitespace(t, k, limit)
            guard k < limit else { return nil }
            if t[k] == C.gt { return k + 1 }
            if t[k] == C.slash { return k + 1 < limit && t[k + 1] == C.gt ? k + 2 : nil }
            // Every attribute must be preceded by whitespace.
            guard k > beforeSpace, isAttributeNameStart(t[k]) else { return nil }
            while k < limit, isAttributeNameStart(t[k]) || C.isDigit(t[k]) || t[k] == C.dot || t[k] == C.minus {
                k += 1
            }
            var j = LinkSyntax.skipWhitespace(t, k, limit)
            if j < limit, t[j] == C.equals {
                j = LinkSyntax.skipWhitespace(t, j + 1, limit)
                guard j < limit else { return nil }
                if t[j] == C.quote || t[j] == C.apos {
                    let q = t[j]
                    j += 1
                    while j < limit, t[j] != q { j += 1 }
                    guard j < limit else { return nil }
                    j += 1
                } else {
                    let valueStart = j
                    while j < limit, !C.isWhitespace(t[j]),
                          ![C.quote, C.apos, C.equals, C.lt, C.gt, C.backtick].contains(t[j]) {
                        j += 1
                    }
                    guard j > valueStart else { return nil }
                }
                k = j
            }
        }
    }

    static func closingTag(_ t: [UInt16], _ start: Int, _ limit: Int) -> Int? {
        var k = start + 2
        guard k < limit, C.isASCIILetter(t[k]) else { return nil }
        while k < limit, C.isASCIIAlphanumeric(t[k]) || t[k] == C.minus { k += 1 }
        k = LinkSyntax.skipWhitespace(t, k, limit)
        return k < limit && t[k] == C.gt ? k + 1 : nil
    }

    private static func isAttributeNameStart(_ u: UInt16) -> Bool {
        C.isASCIILetter(u) || u == C.underscore || u == C.colon
    }

    static func hasPrefix(_ t: [UInt16], _ prefix: String, _ start: Int, _ limit: Int) -> Bool {
        var k = start
        for u in prefix.utf16 {
            guard k < limit, t[k] == u else { return false }
            k += 1
        }
        return true
    }

    /// Index just past the first occurrence of `pattern` at or after `start`.
    static func find(_ t: [UInt16], _ pattern: String, _ start: Int, _ limit: Int) -> Int? {
        let p = Array(pattern.utf16)
        guard !p.isEmpty, limit - start >= p.count, start >= 0 else { return nil }
        var k = start
        while k + p.count <= limit {
            if t[k] == p[0] {
                var m = 1
                while m < p.count, t[k + m] == p[m] { m += 1 }
                if m == p.count { return k + p.count }
            }
            k += 1
        }
        return nil
    }
}
