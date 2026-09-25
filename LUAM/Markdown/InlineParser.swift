import Foundation

/// Parses the inline content of a heading, paragraph or table cell —
/// CommonMark's second phase, plus GFM strikethrough, bare autolinks and
/// `$` math.
///
/// The segments of one block are joined into a virtual text with `\n` between
/// them; `map` translates every virtual index back to a buffer offset, so the
/// resulting ranges point into the document even when the lines were
/// interleaved with container prefixes.
nonisolated struct InlineParser: Sendable {
    let units: [UInt16]
    let definitions: [String: LinkDefinition]

    func parse(_ segments: [Segment]) -> [Inline] {
        guard !segments.isEmpty else { return [] }
        var text: [UInt16] = []
        var map: [Int] = []
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                text.append(C.lf)
                map.append(segments[index - 1].end)
            }
            if segment.end > segment.start {
                text.append(contentsOf: units[segment.start..<segment.end])
                map.append(contentsOf: segment.start..<segment.end)
            }
        }
        map.append(segments[segments.count - 1].end)
        return InlineRun(text, map, definitions).run()
    }
}

nonisolated private final class Node {
    var kind: Inline.Kind
    var start: Int
    var end: Int
    var markers: [Range<Int>] = []
    var children: [Node] = []

    init(_ kind: Inline.Kind, _ start: Int, _ end: Int) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

/// A run of `*`, `_` or `~` that may open or close emphasis.
nonisolated private final class Delimiter {
    let node: Node
    let char: UInt16
    var count: Int
    let originalCount: Int
    let canOpen: Bool
    let canClose: Bool
    /// Virtual index where the run started; never changes, so it orders
    /// delimiters even after others have been removed.
    let position: Int

    init(node: Node, char: UInt16, count: Int, canOpen: Bool, canClose: Bool, position: Int) {
        self.node = node
        self.char = char
        self.count = count
        originalCount = count
        self.canOpen = canOpen
        self.canClose = canClose
        self.position = position
    }
}

/// An unmatched `[` or `![`.
nonisolated private final class Bracket {
    let node: Node
    let image: Bool
    var active = true
    /// Delimiter stack height when the bracket was seen; emphasis inside the
    /// link text is resolved down to here.
    let delimiterBottom: Int
    let position: Int

    init(node: Node, image: Bool, delimiterBottom: Int, position: Int) {
        self.node = node
        self.image = image
        self.delimiterBottom = delimiterBottom
        self.position = position
    }
}

nonisolated private final class InlineRun {
    private let t: [UInt16]
    private let n: Int
    private let map: [Int]
    private let definitions: [String: LinkDefinition]

    private var nodes: [Node] = []
    private var delimiters: [Delimiter] = []
    private var brackets: [Bracket] = []
    private var buffer: [UInt16] = []
    private var bufferStart = 0
    /// Backtick run lengths known to have no closing run further on.
    private var unclosedCodeRuns: Set<Int> = []
    /// Math openers (1 = `$`, 2 = `$$`) known to have no closer further on.
    private var unclosedMath: Set<Int> = []

    init(_ text: [UInt16], _ map: [Int], _ definitions: [String: LinkDefinition]) {
        t = text
        n = text.count
        self.map = map
        self.definitions = definitions
    }

    func run() -> [Inline] {
        var i = 0
        while i < n {
            switch t[i] {
            case C.lf:
                i = lineBreak(i)
            case C.backslash:
                i = backslash(i)
            case C.backtick:
                i = codeSpan(i)
            case C.dollar:
                i = mathSpan(i)
            case C.star, C.underscore, C.tilde:
                i = delimiterRun(i)
            case C.lbracket:
                openBracket(i, image: false)
                i += 1
            case C.bang where i + 1 < n && t[i + 1] == C.lbracket:
                openBracket(i, image: true)
                i += 2
            case C.rbracket:
                i = closeBracket(i)
            case C.lt:
                i = angleBracket(i)
            case C.amp:
                if let (decoded, next) = HTMLEntities.decode(t, at: i, limit: n) {
                    append(Array(decoded.utf16), at: i)
                    i = next
                } else {
                    append(t[i], at: i)
                    i += 1
                }
            case 0x68, 0x77: // h, w
                if let end = bareAutolink(i) {
                    i = end
                } else {
                    append(t[i], at: i)
                    i += 1
                }
            default:
                append(t[i], at: i)
                i += 1
            }
        }
        flush(n)
        processEmphasis(0)
        return convert(nodes)
    }

    // MARK: - Text

    private func append(_ unit: UInt16, at i: Int) {
        if buffer.isEmpty { bufferStart = i }
        buffer.append(unit)
    }

    private func append(_ units: [UInt16], at i: Int) {
        if buffer.isEmpty { bufferStart = i }
        buffer.append(contentsOf: units)
    }

    /// Emits pending text as a node ending at `end`.
    private func flush(_ end: Int) {
        guard !buffer.isEmpty else { return }
        nodes.append(Node(.text(String(decoding: buffer, as: UTF16.self)), bufferStart, end))
        buffer.removeAll(keepingCapacity: true)
    }

    private func lineBreak(_ i: Int) -> Int {
        var spaces = 0
        while spaces < buffer.count, buffer[buffer.count - 1 - spaces] == C.space { spaces += 1 }
        buffer.removeLast(spaces)
        flush(i - spaces)
        if spaces >= 2 {
            nodes.append(Node(.hardBreak, i - spaces, i + 1))
        } else {
            nodes.append(Node(.softBreak, i, i + 1))
        }
        return skipSpaces(i + 1)
    }

    private func backslash(_ i: Int) -> Int {
        if i + 1 < n, t[i + 1] == C.lf {
            flush(i)
            nodes.append(Node(.hardBreak, i, i + 2))
            return skipSpaces(i + 2)
        }
        if i + 1 < n, C.isASCIIPunctuation(t[i + 1]) {
            append(t[i + 1], at: i)
            return i + 2
        }
        append(t[i], at: i)
        return i + 1
    }

    private func skipSpaces(_ start: Int) -> Int {
        var k = start
        while k < n, C.isSpaceOrTab(t[k]) { k += 1 }
        return k
    }

    // MARK: - Code spans

    private func codeSpan(_ i: Int) -> Int {
        var k = i
        while k < n, t[k] == C.backtick { k += 1 }
        let length = k - i
        if !unclosedCodeRuns.contains(length) {
            var j = k
            while j < n {
                guard t[j] == C.backtick else {
                    j += 1
                    continue
                }
                var e = j
                while e < n, t[e] == C.backtick { e += 1 }
                if e - j == length {
                    var content = t[k..<j].map { $0 == C.lf ? C.space : $0 }
                    if content.count >= 2, content.first == C.space, content.last == C.space,
                       content.contains(where: { $0 != C.space }) {
                        content.removeFirst()
                        content.removeLast()
                    }
                    flush(i)
                    let node = Node(.code(String(decoding: content, as: UTF16.self)), i, e)
                    node.markers = [i..<k, j..<e]
                    nodes.append(node)
                    return e
                }
                j = e
            }
            unclosedCodeRuns.insert(length)
        }
        append(Array(t[i..<k]), at: i)
        return k
    }

    // MARK: - Math

    /// `$…$` inline and `$$…$$` display math, taken verbatim like a code span
    /// so TeX's `_`, `*` and `\` survive. A single `$` opens only before a
    /// non-space and closes only after one, and not before a digit — so
    /// "costs $5 and $10" stays text. `\$` inside math doesn't close it.
    private func mathSpan(_ i: Int) -> Int {
        let width = i + 1 < n && t[i + 1] == C.dollar ? 2 : 1
        let start = i + width
        func literal() -> Int {
            append(Array(t[i..<start]), at: i)
            return start
        }
        guard start < n, !unclosedMath.contains(width) else { return literal() }
        if width == 1, Self.isSpace(t[start]) { return literal() }

        var j = start
        while j < n {
            if t[j] == C.backslash {
                j += 2
                continue
            }
            guard t[j] == C.dollar, j > start else {
                j += 1
                continue
            }
            let closes = width == 2
                ? j + 1 < n && t[j + 1] == C.dollar
                : !Self.isSpace(t[j - 1]) && !(j + 1 < n && Self.isDigit(t[j + 1]))
            if closes {
                flush(i)
                let tex = String(decoding: t[start..<j], as: UTF16.self)
                let node = Node(.math(tex, display: width == 2), i, j + width)
                node.markers = [i..<start, j..<(j + width)]
                nodes.append(node)
                return j + width
            }
            j += 1
        }
        // Nothing later can close either: every later opener would scan a
        // suffix of what was just scanned.
        unclosedMath.insert(width)
        return literal()
    }

    private static func isSpace(_ u: UInt16) -> Bool { u == C.space || u == C.lf || u == C.tab }
    private static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }

    // MARK: - Emphasis

    private func delimiterRun(_ i: Int) -> Int {
        let char = t[i]
        var k = i
        while k < n, t[k] == char { k += 1 }
        let count = k - i
        if char == C.tilde, count > 2 {
            append(Array(t[i..<k]), at: i)
            return k
        }
        let before = i == 0 ? Unicode.Scalar(UInt8(0x0A)) : scalar(before: i)
        let after = k == n ? Unicode.Scalar(UInt8(0x0A)) : scalar(at: k)
        let beforeSpace = Self.isWhitespace(before)
        let afterSpace = Self.isWhitespace(after)
        let beforePunct = Self.isPunctuation(before)
        let afterPunct = Self.isPunctuation(after)
        let left = !afterSpace && (!afterPunct || beforeSpace || beforePunct)
        let right = !beforeSpace && (!beforePunct || afterSpace || afterPunct)
        let canOpen: Bool
        let canClose: Bool
        if char == C.underscore {
            canOpen = left && (!right || beforePunct)
            canClose = right && (!left || afterPunct)
        } else {
            canOpen = left
            canClose = right
        }
        flush(i)
        let node = Node(.text(String(repeating: Character(Unicode.Scalar(char)!), count: count)), i, k)
        nodes.append(node)
        if canOpen || canClose {
            delimiters.append(Delimiter(
                node: node, char: char, count: count, canOpen: canOpen, canClose: canClose, position: i))
        }
        return k
    }

    /// Resolves emphasis among the delimiters from `bottom` up, following the
    /// CommonMark "process emphasis" procedure, then drops them from the stack.
    private func processEmphasis(_ bottom: Int) {
        var openersBottom: [Int: Int] = [:]
        var ci = bottom
        while ci < delimiters.count {
            let closer = delimiters[ci]
            guard closer.canClose else {
                ci += 1
                continue
            }
            let key = closer.char == C.tilde
                ? Int(closer.char) * 1000 + closer.count
                : Int(closer.char) * 1000 + (closer.canOpen ? 10 : 0) + closer.originalCount % 3
            let floor = openersBottom[key] ?? Int.min
            var found: Int?
            var oi = ci - 1
            while oi >= bottom, delimiters[oi].position >= floor {
                let opener = delimiters[oi]
                if opener.char == closer.char, opener.canOpen {
                    if closer.char == C.tilde {
                        if opener.count == closer.count {
                            found = oi
                            break
                        }
                    } else {
                        let oddMatch = (closer.canOpen || opener.canClose)
                            && (opener.originalCount + closer.originalCount) % 3 == 0
                            && !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                        if !oddMatch {
                            found = oi
                            break
                        }
                    }
                }
                oi -= 1
            }

            guard let oi = found else {
                openersBottom[key] = closer.position
                if closer.canOpen {
                    ci += 1
                } else {
                    delimiters.remove(at: ci)
                }
                continue
            }

            let opener = delimiters[oi]
            let use = closer.char == C.tilde ? closer.count : (closer.count >= 2 && opener.count >= 2 ? 2 : 1)
            let openNode = opener.node
            let closeNode = closer.node
            let openMarker = (openNode.end - use)..<openNode.end
            let closeMarker = closeNode.start..<(closeNode.start + use)
            opener.count -= use
            closer.count -= use
            openNode.end -= use
            closeNode.start += use
            let symbol = Character(Unicode.Scalar(closer.char)!)
            openNode.kind = .text(String(repeating: symbol, count: opener.count))
            closeNode.kind = .text(String(repeating: symbol, count: closer.count))

            let kind: Inline.Kind = closer.char == C.tilde ? .strikethrough : (use == 2 ? .strong : .emphasis)
            let wrapper = Node(kind, openMarker.lowerBound, closeMarker.upperBound)
            wrapper.markers = [openMarker, closeMarker]
            let openIndex = index(of: openNode)
            let closeIndex = index(of: closeNode)
            wrapper.children = Array(nodes[(openIndex + 1)..<closeIndex])
            nodes.replaceSubrange((openIndex + 1)..<closeIndex, with: [wrapper])

            delimiters.removeSubrange((oi + 1)..<ci)
            ci = oi + 1
            if opener.count == 0 {
                nodes.remove(at: index(of: openNode))
                delimiters.remove(at: oi)
                ci -= 1
            }
            if closer.count == 0 {
                nodes.remove(at: index(of: closeNode))
                delimiters.remove(at: ci)
            }
        }
        if bottom < delimiters.count {
            delimiters.removeSubrange(bottom...)
        }
    }

    private func index(of node: Node) -> Int {
        nodes.lastIndex { $0 === node }!
    }

    // MARK: - Links

    private func openBracket(_ i: Int, image: Bool) {
        flush(i)
        let end = i + (image ? 2 : 1)
        let node = Node(.text(image ? "![" : "["), i, end)
        nodes.append(node)
        brackets.append(Bracket(node: node, image: image, delimiterBottom: delimiters.count, position: i))
    }

    private func closeBracket(_ i: Int) -> Int {
        flush(i)
        guard let opener = brackets.last else {
            append(t[i], at: i)
            return i + 1
        }
        guard opener.active else {
            brackets.removeLast()
            append(t[i], at: i)
            return i + 1
        }

        var target: (destination: String, title: String?, end: Int)?
        let after = i + 1
        if after < n, t[after] == C.lparen {
            target = inlineLinkTail(after)
        }
        if target == nil {
            let textStart = opener.position + (opener.image ? 2 : 1)
            var label: String?
            var end = after
            if after + 1 < n, t[after] == C.lbracket, t[after + 1] == C.rbracket {
                if LinkSyntax.isValidLabel(t, textStart, i) { label = string(textStart, i) }
                end = after + 2
            } else if after < n, t[after] == C.lbracket, let (contentEnd, afterLabel) = LinkSyntax.label(t, after, n) {
                label = string(after + 1, contentEnd)
                end = afterLabel
            } else if LinkSyntax.isValidLabel(t, textStart, i) {
                label = string(textStart, i)
            }
            if let label, let definition = definitions[LinkSyntax.normalize(label)] {
                target = (definition.destination, definition.title, end)
            }
        }

        brackets.removeLast()
        guard let target else {
            append(t[i], at: i)
            return i + 1
        }

        processEmphasis(opener.delimiterBottom)
        let openIndex = index(of: opener.node)
        let children = Array(nodes[(openIndex + 1)...])
        nodes.removeSubrange(openIndex...)
        let kind: Inline.Kind = opener.image
            ? .image(source: target.destination, title: target.title)
            : .link(destination: target.destination, title: target.title)
        let link = Node(kind, opener.position, target.end)
        link.children = children
        link.markers = [opener.position..<opener.node.end, i..<target.end]
        nodes.append(link)
        if !opener.image {
            // Links can't contain links.
            for bracket in brackets where !bracket.image { bracket.active = false }
        }
        return target.end
    }

    /// `(destination "title")` starting at the `(` at `p`.
    private func inlineLinkTail(_ p: Int) -> (String, String?, Int)? {
        var k = LinkSyntax.skipWhitespace(t, p + 1, n)
        var destination = ""
        var title: String?
        if k < n, t[k] != C.rparen {
            guard let (parsed, destinationEnd) = LinkSyntax.destination(t, k, n) else { return nil }
            destination = parsed
            k = LinkSyntax.skipWhitespace(t, destinationEnd, n)
            if k < n, k > destinationEnd, t[k] != C.rparen {
                guard let (parsedTitle, titleEnd) = LinkSyntax.title(t, k, n) else { return nil }
                title = parsedTitle
                k = LinkSyntax.skipWhitespace(t, titleEnd, n)
            }
        }
        guard k < n, t[k] == C.rparen else { return nil }
        return (destination, title, k + 1)
    }

    // MARK: - Autolinks and raw HTML

    private func angleBracket(_ i: Int) -> Int {
        if let end = angleAutolink(i) { return end }
        if let end = HTMLSyntax.tag(t, i, n) {
            flush(i)
            nodes.append(Node(.html(string(i, end)), i, end))
            return end
        }
        append(t[i], at: i)
        return i + 1
    }

    /// `<scheme:…>` or `<user@example.com>`.
    private func angleAutolink(_ i: Int) -> Int? {
        let k = i + 1
        guard k < n, C.isASCIIAlphanumeric(t[k]) || t[k] == C.dot else { return nil }

        var j = k
        while j < n, C.isASCIIAlphanumeric(t[j]) || t[j] == C.plus || t[j] == C.dot || t[j] == C.minus { j += 1 }
        if C.isASCIILetter(t[k]), (2...32).contains(j - k), j < n, t[j] == C.colon {
            var e = j + 1
            while e < n, t[e] > 0x20, t[e] != C.lt, t[e] != C.gt { e += 1 }
            if e < n, t[e] == C.gt {
                emitAutolink(i, k, e, destination: string(k, e), closing: 1)
                return e + 1
            }
        }

        if let e = emailEnd(k), e < n, t[e] == C.gt {
            emitAutolink(i, k, e, destination: "mailto:" + string(k, e), closing: 1)
            return e + 1
        }
        return nil
    }

    private func emailEnd(_ start: Int) -> Int? {
        let localSpecials = Array(".!#$%&'*+/=?^_`{|}~-".utf16)
        var k = start
        while k < n, C.isASCIIAlphanumeric(t[k]) || localSpecials.contains(t[k]) { k += 1 }
        guard k > start, k < n, t[k] == C.at else { return nil }
        k += 1
        while true {
            let labelStart = k
            while k < n, C.isASCIIAlphanumeric(t[k]) || t[k] == C.minus, k - labelStart < 63 { k += 1 }
            guard k > labelStart, t[labelStart] != C.minus, t[k - 1] != C.minus else { return nil }
            if k + 1 < n, t[k] == C.dot, C.isASCIIAlphanumeric(t[k + 1]) {
                k += 1
                continue
            }
            return k
        }
    }

    /// GFM's extended autolinks: `https://…` and `www.…` in running text.
    private func bareAutolink(_ i: Int) -> Int? {
        if i > 0 {
            let p = t[i - 1]
            guard C.isWhitespace(p) || p == C.star || p == C.underscore || p == C.tilde || p == C.lparen else {
                return nil
            }
        }
        let prefix: Int
        if HTMLSyntax.hasPrefix(t, "https://", i, n) {
            prefix = 8
        } else if HTMLSyntax.hasPrefix(t, "http://", i, n) {
            prefix = 7
        } else if HTMLSyntax.hasPrefix(t, "www.", i, n) {
            prefix = 4
        } else {
            return nil
        }
        var e = i + prefix
        while e < n, !C.isWhitespace(t[e]), t[e] != C.lt { e += 1 }
        let trailing = Array("?!.,:*_~'\"".utf16)
        while e > i + prefix {
            let last = t[e - 1]
            if trailing.contains(last) {
                e -= 1
            } else if last == C.rparen {
                let opens = t[i..<e].filter { $0 == C.lparen }.count
                let closes = t[i..<e].filter { $0 == C.rparen }.count
                guard closes > opens else { break }
                e -= 1
            } else {
                break
            }
        }
        guard e > i + prefix, C.isASCIIAlphanumeric(t[i + prefix]) else { return nil }
        let text = string(i, e)
        emitAutolink(i, i, e, destination: prefix == 4 ? "http://" + text : text, closing: 0)
        return e
    }

    private func emitAutolink(_ start: Int, _ textStart: Int, _ textEnd: Int, destination: String, closing: Int) {
        flush(start)
        let link = Node(.link(destination: destination, title: nil), start, textEnd + closing)
        link.children = [Node(.text(string(textStart, textEnd)), textStart, textEnd)]
        if closing > 0 {
            link.markers = [start..<textStart, textEnd..<(textEnd + closing)]
        }
        nodes.append(link)
    }

    // MARK: - Output

    private func convert(_ nodes: [Node]) -> [Inline] {
        var out: [Inline] = []
        for node in nodes {
            let range = range(node.start, node.end)
            if case .text(let s) = node.kind {
                if s.isEmpty { continue }
                if let last = out.last, case .text(let previous) = last.kind, last.markers.isEmpty {
                    out[out.count - 1].kind = .text(previous + s)
                    out[out.count - 1].range = NSUnionRange(last.range, range)
                    continue
                }
            }
            out.append(Inline(
                kind: node.kind, range: range,
                markers: node.markers.map { self.range($0.lowerBound, $0.upperBound) },
                children: convert(node.children)))
        }
        return out
    }

    private func range(_ start: Int, _ end: Int) -> NSRange {
        guard end > start else { return NSRange(location: map[min(start, n)], length: 0) }
        return NSRange(map[start]..<(map[end - 1] + 1))
    }

    private func string(_ start: Int, _ end: Int) -> String {
        end > start ? String(decoding: t[start..<end], as: UTF16.self) : ""
    }

    // MARK: - Character classes

    private func scalar(before i: Int) -> Unicode.Scalar {
        let u = t[i - 1]
        if UTF16.isTrailSurrogate(u), i >= 2, UTF16.isLeadSurrogate(t[i - 2]) {
            return Self.combine(t[i - 2], u)
        }
        return Unicode.Scalar(u) ?? " "
    }

    private func scalar(at i: Int) -> Unicode.Scalar {
        let u = t[i]
        if UTF16.isLeadSurrogate(u), i + 1 < n, UTF16.isTrailSurrogate(t[i + 1]) {
            return Self.combine(u, t[i + 1])
        }
        return Unicode.Scalar(u) ?? " "
    }

    private static func combine(_ lead: UInt16, _ trail: UInt16) -> Unicode.Scalar {
        let value = 0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(trail) - 0xDC00)
        return Unicode.Scalar(value) ?? " "
    }

    private static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        if s.value < 0x80 { return C.isWhitespace(UInt16(s.value)) }
        return s.properties.generalCategory == .spaceSeparator
    }

    private static func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        if s.value < 0x80 { return C.isASCIIPunctuation(UInt16(s.value)) }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }
}
