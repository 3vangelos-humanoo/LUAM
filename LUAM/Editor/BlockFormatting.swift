import Foundation

/// Line-level formatting for the Format menu: headings, block quotes and
/// lists. Like the rest of `MarkdownEditing`, pure functions of
/// (text, selection) that return one `TextEdit`.
nonisolated extension MarkdownEditing {
    enum LineStyle: Sendable {
        case quote, bullet, numbered, task
    }

    /// Blocks the Insert menu adds.
    enum BlockTemplate: Sendable {
        case table, codeBlock, rule
    }

    /// Inserts a block template on its own lines, adding blank lines around
    /// it as needed. A table selects its first header for typing over; a code
    /// block wraps the selection and leaves the cursor where the language goes.
    static func insertBlock(_ template: BlockTemplate, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let before = ns.substring(to: selection.location)
        let after = ns.substring(from: NSMaxRange(selection))
        let lead = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let trail = after.isEmpty ? "\n" : after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"

        let block: String
        let focus: NSRange
        switch template {
        case .table:
            block = "| Column | Column |\n| ------ | ------ |\n|        |        |"
            focus = NSRange(location: 2, length: 6)
        case .codeBlock:
            let body = ns.substring(with: selection)
            block = "```\n" + body + (body.hasSuffix("\n") || body.isEmpty ? "" : "\n") + "```"
            focus = NSRange(location: 3, length: 0)
        case .rule:
            block = "---"
            focus = NSRange(location: block.utf16.count + trail.utf16.count, length: 0)
        }
        let start = selection.location + lead.utf16.count
        return TextEdit(
            range: selection, replacement: lead + block + trail,
            selection: NSRange(location: start + focus.location, length: focus.length)
        )
    }

    private static let headingPattern = try! NSRegularExpression(pattern: #"^[ ]{0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let singleQuotePattern = try! NSRegularExpression(pattern: #"^[ ]{0,3}> ?"#)

    /// ⌃⌘1…6 makes every line the selection touches a heading of that level;
    /// ⌃⌘0 (`level` 0) turns them back into body text. Asking for the level
    /// the lines already have removes it, so the shortcut toggles.
    static func setHeading(level: Int, in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let lines = formattableLines(in: ns, selection: selection)
        let bodies = lines.map { line -> (start: Int, prefix: Int, level: Int) in
            let lineText = ns.substring(with: line)
            let quote = quotePrefixLength(of: lineText)
            let body = (lineText as NSString).substring(from: quote)
            let match = headingPattern.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))
            return (line.location + quote, match?.range.length ?? 0, match?.range(at: 1).length ?? 0)
        }
        let target = level > 0 && bodies.allSatisfy { $0.level == level } ? 0 : min(max(level, 0), 6)
        let marker = target > 0 ? String(repeating: "#", count: target) + " " : ""

        let edits = bodies.compactMap { body -> (range: NSRange, text: String)? in
            let range = NSRange(location: body.start, length: body.prefix)
            return ns.substring(with: range) == marker ? nil : (range, marker)
        }
        return combine(edits, in: ns, selection: selection).map { selectingWholeLines($0, from: selection, in: ns) }
    }

    /// Adds a block quote or list marker to every line the selection touches,
    /// or — when they all have it already — takes it away. Switching between
    /// list kinds replaces the marker; numbered lines count up from 1.
    static func toggleLineStyle(_ style: LineStyle, in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let lines = formattableLines(in: ns, selection: selection)

        if style == .quote {
            let quoted = lines.allSatisfy { quotePrefixLength(of: ns.substring(with: $0)) > 0 }
            let edits = lines.map { line -> (range: NSRange, text: String) in
                let lineText = ns.substring(with: line)
                if quoted {
                    let length = singleQuotePattern.firstMatch(
                        in: lineText, range: NSRange(location: 0, length: line.length)
                    )?.range.length ?? 0
                    return (NSRange(location: line.location, length: length), "")
                }
                return (NSRange(location: line.location, length: 0), line.length == 0 ? ">" : "> ")
            }
            return combine(edits, in: ns, selection: selection).map { selectingWholeLines($0, from: selection, in: ns) }
        }

        let prefixes = lines.map { listPrefix(of: ns.substring(with: $0)) }
        func matches(_ prefix: LinePrefix?) -> Bool {
            guard let prefix, prefix.isListItem else { return false }
            switch style {
            case .bullet: return prefix.number == nil && prefix.task == nil
            case .numbered: return prefix.number != nil && prefix.task == nil
            case .task: return prefix.task != nil
            case .quote: return false
            }
        }
        let removing = prefixes.allSatisfy(matches)

        var number = 1
        var edits: [(range: NSRange, text: String)] = []
        for (line, prefix) in zip(lines, prefixes) {
            let lineText = ns.substring(with: line)
            let lead: Int
            let existing: Int
            if let prefix {
                lead = (prefix.quote + prefix.indent).utf16.count
                existing = prefix.isListItem ? (prefix.marker + prefix.spacing + (prefix.task ?? "")).utf16.count : 0
            } else {
                lead = lineText.prefix { $0 == " " || $0 == "\t" }.utf16.count
                existing = 0
            }
            var marker = ""
            if !removing {
                switch style {
                case .bullet: marker = "- "
                case .numbered: marker = "\(number). "; number += 1
                case .task: marker = "- [ ] "
                case .quote: break
                }
            }
            edits.append((NSRange(location: line.location + lead, length: existing), marker))
        }
        return combine(edits, in: ns, selection: selection).map { selectingWholeLines($0, from: selection, in: ns) }
    }

    /// A selection that started at the beginning of a line keeps starting
    /// there, so the markers just added are selected along with the text.
    private static func selectingWholeLines(_ edit: TextEdit, from selection: NSRange, in ns: NSString) -> TextEdit {
        guard selection.length > 0,
              contentRange(ofLineAt: selection.location, in: ns).location == selection.location
        else { return edit }
        var edit = edit
        let end = NSMaxRange(edit.selection)
        edit.selection = NSRange(location: selection.location, length: max(0, end - selection.location))
        return edit
    }

    /// The touched lines, minus blank ones when there's more than one — a
    /// multi-paragraph selection shouldn't sprout empty list items.
    private static func formattableLines(in ns: NSString, selection: NSRange) -> [NSRange] {
        let lines = touchedLines(in: ns, selection: selection)
        guard lines.count > 1 else { return lines }
        let filled = lines.filter { !ns.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty }
        return filled.isEmpty ? [lines[0]] : filled
    }
}
