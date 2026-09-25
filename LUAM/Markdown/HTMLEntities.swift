import Foundation

/// HTML character references: `&amp;`, `&#169;`, `&#x1F600;`.
///
/// The named table covers what people type by hand rather than all 2,125 HTML5
/// names; anything unknown stays literal text, which is what a reader expects.
nonisolated enum HTMLEntities {
    /// Decodes the reference starting at `units[start]` (an `&`). Returns the
    /// decoded text and the index just past the `;`.
    static func decode(_ units: [UInt16], at start: Int, limit: Int) -> (String, Int)? {
        var k = start + 1
        guard k < limit else { return nil }
        if units[k] == C.hash {
            k += 1
            var hex = false
            if k < limit, units[k] == 0x78 || units[k] == 0x58 {
                hex = true
                k += 1
            }
            let digitsStart = k
            var value: UInt32 = 0
            while k < limit, hex ? C.isHexDigit(units[k]) : C.isDigit(units[k]) {
                let digit = UInt32(String(UnicodeScalar(UInt8(units[k]))), radix: 16)!
                value = value &* (hex ? 16 : 10) &+ digit
                k += 1
                if k - digitsStart > (hex ? 6 : 7) { return nil }
            }
            guard k > digitsStart, k < limit, units[k] == C.semicolon else { return nil }
            let scalar = value == 0 ? nil : Unicode.Scalar(value)
            return (String(Character(scalar ?? "\u{FFFD}")), k + 1)
        }
        let nameStart = k
        while k < limit, C.isASCIIAlphanumeric(units[k]), k - nameStart < 32 { k += 1 }
        guard k > nameStart, k < limit, units[k] == C.semicolon else { return nil }
        let name = String(decoding: units[nameStart..<k], as: UTF16.self)
        guard let decoded = named[name] else { return nil }
        return (decoded, k + 1)
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "sbquo": "‚", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›", "bull": "•", "middot": "·",
        "times": "×", "divide": "÷", "plusmn": "±", "deg": "°", "micro": "µ", "para": "¶",
        "sect": "§", "dagger": "†", "Dagger": "‡", "permil": "‰", "prime": "′", "Prime": "″",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "lArr": "⇐", "rArr": "⇒",
        "hArr": "⇔", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "curren": "¤",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "sup1": "¹", "sup2": "²", "sup3": "³",
        "ne": "≠", "le": "≤", "ge": "≥", "asymp": "≈", "equiv": "≡", "infin": "∞", "minus": "−",
        "sum": "∑", "prod": "∏", "radic": "√", "part": "∂", "nabla": "∇", "isin": "∈", "notin": "∉",
        "forall": "∀", "exist": "∃", "empty": "∅", "and": "∧", "or": "∨", "cap": "∩", "cup": "∪",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "omicron": "ο", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω", "Alpha": "Α", "Beta": "Β", "Gamma": "Γ",
        "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ",
        "Omega": "Ω", "iexcl": "¡", "iquest": "¿", "shy": "\u{00AD}", "ensp": "\u{2002}",
        "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "check": "✓", "cross": "✗", "hearts": "♥", "spades": "♠", "clubs": "♣", "diams": "♦",
        "star": "☆", "starf": "★", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "auml": "ä", "ouml": "ö",
        "uuml": "ü", "szlig": "ß", "eacute": "é", "egrave": "è", "ecirc": "ê", "aacute": "á",
        "agrave": "à", "acirc": "â", "iacute": "í", "oacute": "ó", "uacute": "ú", "ntilde": "ñ",
        "ccedil": "ç", "Eacute": "É", "oslash": "ø", "Oslash": "Ø", "aring": "å", "Aring": "Å",
        "aelig": "æ", "AElig": "Æ",
    ]
}
