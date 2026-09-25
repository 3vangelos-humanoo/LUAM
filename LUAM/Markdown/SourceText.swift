import Foundation

/// The document as UTF-16 code units, split into lines.
///
/// The parser works on UTF-16 rather than `Character`s so that every offset it
/// produces is directly an `NSRange` location in the editor's `NSTextStorage`.
nonisolated struct SourceText: Sendable {
    let units: [UInt16]
    let lines: [SourceLine]

    init(_ string: String) {
        let units = Array(string.utf16)
        var lines: [SourceLine] = []
        var start = 0
        var index = 0
        while index < units.count {
            if units[index] == C.lf {
                let end = index > start && units[index - 1] == C.cr ? index - 1 : index
                lines.append(SourceLine(number: lines.count + 1, start: start, end: end, column: 0))
                start = index + 1
            }
            index += 1
        }
        if start < units.count {
            lines.append(SourceLine(number: lines.count + 1, start: start, end: units.count, column: 0))
        }
        self.units = units
        self.lines = lines
    }

    func string(_ start: Int, _ end: Int) -> String {
        guard end > start else { return "" }
        return String(decoding: units[start..<end], as: UTF16.self)
    }
}

/// One line — or what's left of it once container prefixes (`>`, list indents)
/// have been stripped.
nonisolated struct SourceLine: Sendable, Equatable {
    /// 1-based line number in the document.
    var number: Int
    /// First unconsumed code unit.
    var start: Int
    /// End of the line's content, excluding the line terminator.
    var end: Int
    /// Visual column at `start`; tabs advance to the next multiple of 4.
    var column: Int
}

/// UTF-16 code units the parsers switch over.
nonisolated enum C {
    static let tab: UInt16 = 0x09
    static let lf: UInt16 = 0x0A
    static let cr: UInt16 = 0x0D
    static let space: UInt16 = 0x20
    static let bang: UInt16 = 0x21
    static let quote: UInt16 = 0x22
    static let hash: UInt16 = 0x23
    static let dollar: UInt16 = 0x24
    static let amp: UInt16 = 0x26
    static let apos: UInt16 = 0x27
    static let lparen: UInt16 = 0x28
    static let rparen: UInt16 = 0x29
    static let star: UInt16 = 0x2A
    static let plus: UInt16 = 0x2B
    static let minus: UInt16 = 0x2D
    static let dot: UInt16 = 0x2E
    static let slash: UInt16 = 0x2F
    static let colon: UInt16 = 0x3A
    static let semicolon: UInt16 = 0x3B
    static let lt: UInt16 = 0x3C
    static let equals: UInt16 = 0x3D
    static let gt: UInt16 = 0x3E
    static let question: UInt16 = 0x3F
    static let at: UInt16 = 0x40
    static let lbracket: UInt16 = 0x5B
    static let backslash: UInt16 = 0x5C
    static let rbracket: UInt16 = 0x5D
    static let underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60
    static let lbrace: UInt16 = 0x7B
    static let pipe: UInt16 = 0x7C
    static let rbrace: UInt16 = 0x7D
    static let tilde: UInt16 = 0x7E

    static func isSpaceOrTab(_ u: UInt16) -> Bool { u == space || u == tab }
    static func isWhitespace(_ u: UInt16) -> Bool { u == space || u == tab || u == lf || u == cr || u == 0x0C }
    static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
    static func isHexDigit(_ u: UInt16) -> Bool {
        isDigit(u) || (u >= 0x41 && u <= 0x46) || (u >= 0x61 && u <= 0x66)
    }
    static func isASCIILetter(_ u: UInt16) -> Bool { (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) }
    static func isASCIIAlphanumeric(_ u: UInt16) -> Bool { isASCIILetter(u) || isDigit(u) }
    static func isASCIIPunctuation(_ u: UInt16) -> Bool {
        (u >= 0x21 && u <= 0x2F) || (u >= 0x3A && u <= 0x40) || (u >= 0x5B && u <= 0x60) || (u >= 0x7B && u <= 0x7E)
    }
    static func lower(_ u: UInt16) -> UInt16 { u >= 0x41 && u <= 0x5A ? u + 0x20 : u }
}

/// Backslash-escape and entity decoding, shared by inline text, link
/// destinations, titles and fence info strings.
nonisolated enum Unescape {
    static func string(_ units: [UInt16], _ start: Int, _ end: Int) -> String {
        var out: [UInt16] = []
        out.reserveCapacity(end - start)
        var k = start
        while k < end {
            let u = units[k]
            if u == C.backslash, k + 1 < end, C.isASCIIPunctuation(units[k + 1]) {
                out.append(units[k + 1])
                k += 2
            } else if u == C.amp, let (decoded, next) = HTMLEntities.decode(units, at: k, limit: end) {
                out.append(contentsOf: decoded.utf16)
                k = next
            } else {
                out.append(u)
                k += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }
}
