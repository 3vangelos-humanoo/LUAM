import Foundation

/// One replacement in the editor's text plus where the selection lands after it.
/// Ranges are UTF-16, like everything `NSTextView` touches.
nonisolated struct TextEdit: Equatable, Sendable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// The editor's smart-editing rules as pure functions of (text, selection):
/// list continuation and renumbering, indenting, bracket pairing, emphasis
/// toggles, links and dropped files. `MarkdownEditingTextView` only decides
/// *when* to call these; a `nil` result means "let AppKit do the default".
nonisolated enum MarkdownEditing {
    // MARK: Line prefixes

    /// The structural prefix of a line: block quote markers, indentation and a
    /// list marker with its optional task box, e.g. `> ␣␣- [ ] `.
    struct LinePrefix: Equatable {
        var quote = ""
        var indent = ""
        /// The marker as written: `-`, `*`, `+`, `3.` or `12)`; empty for a
        /// quote-only prefix.
        var marker = ""
        var number: Int?
        var delimiter: Character?
        var spacing = ""
        /// The task box including its trailing space, if any: `[ ] `, `[x] `.
        var task: String?

        var isListItem: Bool { !marker.isEmpty }
        var length: Int { (quote + indent + marker + spacing + (task ?? "")).utf16.count }

        /// The marker the next sibling item gets.
        var nextMarker: String {
            if let number, let delimiter { "\(number + 1)\(delimiter)" } else { marker }
        }
    }

    private static let listPattern = try! NSRegularExpression(
        pattern: #"^((?:[ ]{0,3}>[ ]?)*)([ \t]*)(?:([-*+])|([0-9]{1,9})([.)]))([ \t]+)(\[[ xX]\](?:[ \t]+|$))?"#
    )
    private static let quotePattern = try! NSRegularExpression(
        pattern: #"^((?:[ ]{0,3}>[ ]?)+)([ \t]*)"#
    )
    private static let quoteOnlyPattern = try! NSRegularExpression(
        pattern: #"^(?:[ ]{0,3}>[ ]?)*"#
    )
    private static let thematicBreakPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#
    )

    /// Parses a single line (without its newline). `nil` if the line has
    /// neither a list marker nor a block quote.
    static func listPrefix(of line: String) -> LinePrefix? {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }

        if let match = listPattern.firstMatch(in: line, range: whole) {
            let quote = group(match, 1) ?? ""
            let body = ns.substring(from: quote.utf16.count)
            let isBreak = thematicBreakPattern.firstMatch(
                in: body, range: NSRange(location: 0, length: (body as NSString).length)
            ) != nil
            if !isBreak {
                var prefix = LinePrefix(quote: quote, indent: group(match, 2) ?? "", spacing: group(match, 6) ?? "")
                if let bullet = group(match, 3) {
                    prefix.marker = bullet
                } else if let digits = group(match, 4), let delimiter = group(match, 5) {
                    prefix.marker = digits + delimiter
                    prefix.number = Int(digits)
                    prefix.delimiter = delimiter.first
                }
                prefix.task = group(match, 7)
                return prefix
            }
        }
        if let match = quotePattern.firstMatch(in: line, range: whole) {
            return LinePrefix(quote: group(match, 1) ?? "", indent: group(match, 2) ?? "")
        }
        return nil
    }

    /// Whether the line at `location` is a list item.
    static func isListItem(in text: String, at location: Int) -> Bool {
        let ns = text as NSString
        return listPrefix(of: ns.substring(with: contentRange(ofLineAt: location, in: ns)))?.isListItem ?? false
    }

    // MARK: Return

    /// Return inside a list or quote: continue it with the next marker, or end
    /// it when the current item is empty. Elsewhere, keep the line's indent.
    /// Pass `listsEnabled: false` inside code blocks.
    static func insertNewline(in text: String, selection: NSRange, listsEnabled: Bool = true) -> TextEdit? {
        let ns = text as NSString
        let line = contentRange(ofLineAt: selection.location, in: ns)
        let lineText = ns.substring(with: line)
        let column = selection.location - line.location

        if listsEnabled, let prefix = listPrefix(of: lineText), column >= prefix.length {
            let rest = (lineText as NSString).substring(from: prefix.length)
            let isEmpty = rest.trimmingCharacters(in: .whitespaces).isEmpty

            if isEmpty && selection.length == 0 && NSMaxRange(selection) <= NSMaxRange(line) {
                let afterQuote = NSRange(
                    location: line.location + prefix.quote.utf16.count,
                    length: line.length - prefix.quote.utf16.count
                )
                if prefix.isListItem, !prefix.indent.isEmpty {
                    // An empty nested item steps out one level.
                    let item = outdented(prefix.indent) + prefix.marker + prefix.spacing
                        + (prefix.task == nil ? "" : "[ ] ")
                    return TextEdit(
                        range: afterQuote, replacement: item,
                        selection: NSRange(location: afterQuote.location + item.utf16.count, length: 0)
                    )
                }
                // An empty top-level item drops its marker; an empty quote line
                // ends the quote.
                let range = prefix.isListItem ? afterQuote : line
                return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
            }

            var insertion = "\n" + prefix.quote + prefix.indent
            if prefix.isListItem {
                insertion += prefix.nextMarker + prefix.spacing + (prefix.task == nil ? "" : "[ ] ")
            }
            return TextEdit(
                range: selection, replacement: insertion,
                selection: NSRange(location: selection.location + insertion.utf16.count, length: 0)
            )
        }

        let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
        guard !indent.isEmpty, column >= indent.utf16.count else { return nil }
        let insertion = "\n" + indent
        return TextEdit(
            range: selection, replacement: insertion,
            selection: NSRange(location: selection.location + insertion.utf16.count, length: 0)
        )
    }

    /// Renumbers the ordered list containing `location` so its items count up
    /// from the first item's number. `nil` if nothing needs to change.
    static func renumberList(in text: String, around location: Int, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let lines = lineRanges(in: ns)
        guard let current = lines.firstIndex(where: { location >= $0.location && location <= NSMaxRange($0) }),
              let key = listPrefix(of: ns.substring(with: lines[current])), key.number != nil
        else { return nil }

        enum Kind { case sibling(LinePrefix), passThrough, stop }
        func classify(_ index: Int) -> Kind {
            let lineText = ns.substring(with: lines[index])
            if let prefix = listPrefix(of: lineText), prefix.number != nil,
               prefix.quote == key.quote, prefix.indent == key.indent, prefix.delimiter == key.delimiter {
                return .sibling(prefix)
            }
            guard lineText.hasPrefix(key.quote) else { return .stop }
            let body = String(lineText.dropFirst(key.quote.count))
            if body.trimmingCharacters(in: .whitespaces).isEmpty { return .passThrough }
            let leading = body.prefix { $0 == " " || $0 == "\t" }.count
            return leading > key.indent.count ? .passThrough : .stop
        }

        var siblings: [(line: Int, prefix: LinePrefix)] = [(current, key)]
        var index = current - 1
        scanUp: while index >= 0 {
            switch classify(index) {
            case .sibling(let prefix): siblings.insert((index, prefix), at: 0)
            case .passThrough: break
            case .stop: break scanUp
            }
            index -= 1
        }
        index = current + 1
        scanDown: while index < lines.count {
            switch classify(index) {
            case .sibling(let prefix): siblings.append((index, prefix))
            case .passThrough: break
            case .stop: break scanDown
            }
            index += 1
        }

        guard let start = siblings.first?.prefix.number else { return nil }
        var edits: [(range: NSRange, text: String)] = []
        for (offset, sibling) in siblings.enumerated() {
            let expected = start + offset
            guard sibling.prefix.number != expected else { continue }
            let digits = sibling.prefix.marker.utf16.count - 1
            let at = lines[sibling.line].location + (sibling.prefix.quote + sibling.prefix.indent).utf16.count
            edits.append((NSRange(location: at, length: digits), "\(expected)"))
        }
        return combine(edits, in: ns, selection: selection)
    }

    // MARK: Indent

    static let indentUnit = "    "

    /// Tab: indents every line the selection touches, after any quote markers.
    static func indent(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let lines = touchedLines(in: ns, selection: selection)
        let first = ns.substring(with: lines[0])
        let quote = quotePrefixLength(of: first)
        let unit = (first as NSString).substring(from: quote).hasPrefix("\t") ? "\t" : indentUnit

        let edits = lines.compactMap { line -> (range: NSRange, text: String)? in
            let lineText = ns.substring(with: line)
            if lines.count > 1 && lineText.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            return (NSRange(location: line.location + quotePrefixLength(of: lineText), length: 0), unit)
        }
        return combine(edits, in: ns, selection: selection)
    }

    /// ⇧Tab: removes one level (a tab or up to four spaces) from every line
    /// the selection touches.
    static func outdent(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let edits = touchedLines(in: ns, selection: selection).compactMap { line -> (range: NSRange, text: String)? in
            let lineText = ns.substring(with: line)
            let quote = quotePrefixLength(of: lineText)
            let body = (lineText as NSString).substring(from: quote)
            let removed = body.utf16.count - outdented(body).utf16.count
            guard removed > 0 else { return nil }
            return (NSRange(location: line.location + quote, length: removed), "")
        }
        return combine(edits, in: ns, selection: selection)
    }

    private static func outdented(_ string: String) -> String {
        if string.hasPrefix("\t") { return String(string.dropFirst()) }
        let spaces = min(4, string.prefix { $0 == " " }.count)
        return String(string.dropFirst(spaces))
    }

    // MARK: Pairing

    private static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`", "*": "*", "_": "_",
    ]
    private static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`"]
    private static let deletablePairs: Set<Character> = ["(", "[", "{", "\"", "'", "`"]

    /// Typing a single character: wraps a selection in a pair, steps over a
    /// closer that's already there, or inserts both halves of a pair.
    /// `*` and `_` only ever wrap — they start list items and rules too often.
    static func insert(_ string: String, in text: String, selection: NSRange) -> TextEdit? {
        guard string.count == 1, let typed = string.first, let closer = pairs[typed] ?? (closers.contains(typed) ? typed : nil)
        else { return nil }
        let ns = text as NSString

        if selection.length > 0 {
            guard pairs[typed] != nil else { return nil }
            let selected = ns.substring(with: selection)
            return TextEdit(
                range: selection, replacement: "\(typed)\(selected)\(closer)",
                selection: NSRange(location: selection.location + 1, length: selection.length)
            )
        }

        let previous = character(in: ns, at: selection.location - 1)
        let next = character(in: ns, at: selection.location)

        if closers.contains(typed), next == typed {
            return TextEdit(
                range: NSRange(location: selection.location, length: 0), replacement: "",
                selection: NSRange(location: selection.location + 1, length: 0)
            )
        }

        let nextIsOpen = next.map { $0.isWhitespace || ")]}.,;:!?".contains($0) } ?? true
        let previousIsOpen = previous.map { $0.isWhitespace || "([{".contains($0) } ?? true
        let shouldPair = switch typed {
        case "(", "[", "{": nextIsOpen
        case "\"", "'", "`": nextIsOpen && previousIsOpen
        default: false
        }
        guard shouldPair else { return nil }
        return TextEdit(
            range: selection, replacement: "\(typed)\(closer)",
            selection: NSRange(location: selection.location + 1, length: 0)
        )
    }

    /// Backspace between an empty pair removes both halves.
    static func deleteBackward(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        guard let previous = character(in: ns, at: selection.location - 1),
              let next = character(in: ns, at: selection.location),
              deletablePairs.contains(previous), pairs[previous] == next
        else { return nil }
        return TextEdit(
            range: NSRange(location: selection.location - 1, length: 2), replacement: "",
            selection: NSRange(location: selection.location - 1, length: 0)
        )
    }

    // MARK: Emphasis and links

    /// ⌘B (`**`) / ⌘I (`*`): wraps or unwraps the selection, or the word under
    /// the cursor. With nothing to wrap, inserts an empty pair.
    static func toggleWrap(marker: String, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let width = marker.utf16.count
        var range = selection

        if range.length == 0 {
            if range.location >= width, range.location + width <= ns.length,
               ns.substring(with: NSRange(location: range.location - width, length: 2 * width)) == marker + marker,
               character(in: ns, at: range.location - width - 1) != marker.first,
               character(in: ns, at: range.location + width) != marker.first {
                return TextEdit(
                    range: NSRange(location: range.location - width, length: 2 * width), replacement: "",
                    selection: NSRange(location: range.location - width, length: 0)
                )
            }
            range = wordRange(in: ns, at: range.location)
            if range.length == 0 {
                return TextEdit(
                    range: selection, replacement: marker + marker,
                    selection: NSRange(location: selection.location + width, length: 0)
                )
            }
        }
        range = trimmingWhitespace(range, in: ns)
        let selected = ns.substring(with: range)
        let char = marker.first!

        func isPresent(_ run: Int) -> Bool {
            width >= 2 ? run >= width : (run == 1 || run >= 3)
        }

        let lead = selected.prefix { $0 == char }.count
        let trail = selected.reversed().prefix { $0 == char }.count
        if selected.count >= 2 * width, lead < selected.count, isPresent(min(lead, trail)) {
            let inner = (selected as NSString).substring(with: NSRange(location: width, length: range.length - 2 * width))
            return TextEdit(range: range, replacement: inner, selection: NSRange(location: range.location, length: inner.utf16.count))
        }

        var before = 0
        while character(in: ns, at: range.location - before - 1) == char { before += 1 }
        var after = 0
        while character(in: ns, at: NSMaxRange(range) + after) == char { after += 1 }
        if isPresent(min(before, after)) {
            return TextEdit(
                range: NSRange(location: range.location - width, length: range.length + 2 * width),
                replacement: selected,
                selection: NSRange(location: range.location - width, length: range.length)
            )
        }

        return TextEdit(
            range: range, replacement: marker + selected + marker,
            selection: NSRange(location: range.location + width, length: range.length)
        )
    }

    /// ⌘K: `[selection](clipboard URL)`. A selected URL becomes the target;
    /// the cursor lands wherever there's still something to type.
    static func link(in text: String, selection: NSRange, clipboard: String?) -> TextEdit {
        let ns = text as NSString
        let selected = ns.substring(with: selection)
        let url = clipboard.flatMap(validURL)
        let at = selection.location

        if let selectedURL = validURL(selected) {
            return TextEdit(range: selection, replacement: "[](\(selectedURL))", selection: NSRange(location: at + 1, length: 0))
        }
        if selected.isEmpty {
            let replacement = "[](\(url ?? ""))"
            return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: at + 1, length: 0))
        }
        if let url {
            let replacement = "[\(selected)](\(url))"
            return TextEdit(
                range: selection, replacement: replacement,
                selection: NSRange(location: at + replacement.utf16.count, length: 0)
            )
        }
        return TextEdit(
            range: selection, replacement: "[\(selected)]()",
            selection: NSRange(location: at + selected.utf16.count + 3, length: 0)
        )
    }

    static func validURL(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "ftp", "file"].contains(scheme)
        else { return nil }
        if scheme.hasPrefix("http") && (url.host ?? "").isEmpty { return nil }
        return trimmed
    }

    // MARK: Dropped files

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp", "avif",
    ]

    /// Markdown for files dropped on the editor: images embed, anything else
    /// links. Paths are relative to `base` (the document's folder) when they
    /// share more than the root, otherwise absolute `file://` URLs.
    static func fileLinks(for urls: [URL], relativeTo base: URL?) -> String {
        urls.map { url in
            let path = linkPath(for: url, relativeTo: base)
            if imageExtensions.contains(url.pathExtension.lowercased()) {
                return "![\(escapeBrackets(url.deletingPathExtension().lastPathComponent))](\(path))"
            }
            return "[\(escapeBrackets(url.lastPathComponent))](\(path))"
        }
        .joined(separator: "\n")
    }

    static func linkPath(for url: URL, relativeTo base: URL?) -> String {
        guard let base else { return url.standardizedFileURL.absoluteString }
        let target = url.standardizedFileURL.pathComponents
        let from = base.standardizedFileURL.pathComponents
        var common = 0
        while common < min(target.count, from.count), target[common] == from[common] { common += 1 }
        guard common > 1 else { return url.standardizedFileURL.absoluteString }
        let parts = Array(repeating: "..", count: from.count - common) + target[common...].map(encodePathComponent)
        return parts.joined(separator: "/")
    }

    private static let pathComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "()/")
        return set
    }()

    private static func encodePathComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed) ?? component
    }

    private static func escapeBrackets(_ string: String) -> String {
        string.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    // MARK: Helpers

    /// The range of the line containing `location`, without its line break.
    static func contentRange(ofLineAt location: Int, in ns: NSString) -> NSRange {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(location, ns.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// Content ranges of every line, including an empty last line after a
    /// trailing newline.
    static func lineRanges(in ns: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var index = 0
        while true {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            lines.append(NSRange(location: start, length: contentsEnd - start))
            if end >= ns.length {
                if end > contentsEnd { lines.append(NSRange(location: end, length: 0)) }
                break
            }
            index = end
        }
        return lines
    }

    /// The lines a selection touches. A selection ending right at the start of
    /// a line doesn't count that line.
    static func touchedLines(in ns: NSString, selection: NSRange) -> [NSRange] {
        var lines = [contentRange(ofLineAt: selection.location, in: ns)]
        let end = NSMaxRange(selection)
        while true {
            var start = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lines.last!.location, length: 0))
            guard lineEnd < end else { break }
            lines.append(contentRange(ofLineAt: lineEnd, in: ns))
        }
        return lines
    }

    static func quotePrefixLength(of line: String) -> Int {
        quoteOnlyPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range.length ?? 0
    }

    private static func character(in ns: NSString, at index: Int) -> Character? {
        guard index >= 0, index < ns.length else { return nil }
        return UnicodeScalar(ns.character(at: index)).map(Character.init) ?? "\u{FFFD}"
    }

    private static func wordRange(in ns: NSString, at location: Int) -> NSRange {
        func isWord(_ index: Int) -> Bool {
            guard let c = character(in: ns, at: index) else { return false }
            return c.isLetter || c.isNumber || c == "\u{FFFD}"
        }
        var start = location
        while isWord(start - 1) { start -= 1 }
        var end = location
        while isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func trimmingWhitespace(_ range: NSRange, in ns: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        while start < end, character(in: ns, at: start)?.isWhitespace == true { start += 1 }
        while end > start, character(in: ns, at: end - 1)?.isWhitespace == true { end -= 1 }
        return start == end ? range : NSRange(location: start, length: end - start)
    }

    /// Folds several non-overlapping edits into one `TextEdit` spanning all of
    /// them, carrying the selection along.
    static func combine(_ edits: [(range: NSRange, text: String)], in ns: NSString, selection: NSRange) -> TextEdit? {
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        guard let first = sorted.first else { return nil }
        let start = first.range.location
        let end = sorted.map { NSMaxRange($0.range) }.max()!

        var replacement = ""
        var cursor = start
        for edit in sorted {
            replacement += ns.substring(with: NSRange(location: cursor, length: edit.range.location - cursor))
            replacement += edit.text
            cursor = NSMaxRange(edit.range)
        }

        func map(_ position: Int) -> Int {
            var shift = 0
            for edit in sorted {
                if position >= NSMaxRange(edit.range) {
                    shift += edit.text.utf16.count - edit.range.length
                } else if position > edit.range.location {
                    return edit.range.location + shift + min(position - edit.range.location, edit.text.utf16.count)
                } else {
                    break
                }
            }
            return position + shift
        }
        let newStart = map(selection.location)
        let newEnd = map(NSMaxRange(selection))
        return TextEdit(
            range: NSRange(location: start, length: end - start),
            replacement: replacement,
            selection: NSRange(location: newStart, length: max(0, newEnd - newStart))
        )
    }
}
