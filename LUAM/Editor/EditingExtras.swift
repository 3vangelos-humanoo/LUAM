import Foundation

/// Smaller editing rules: task toggles from the preview, the paragraph focus
/// mode highlights, and renumbering after lines change nesting level.
nonisolated extension MarkdownEditing {
    /// Flips the task box on 1-based `line`: `[ ]` ↔ `[x]`. `nil` if that line
    /// isn't a task item. The edit is length-preserving, so the selection
    /// stays where it was.
    static func toggleTask(in text: String, line: Int, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let lines = lineRanges(in: ns)
        guard line >= 1, line <= lines.count else { return nil }
        let range = lines[line - 1]
        guard let prefix = listPrefix(of: ns.substring(with: range)), let task = prefix.task else { return nil }
        let box = NSRange(
            location: range.location + (prefix.quote + prefix.indent + prefix.marker + prefix.spacing).utf16.count + 1,
            length: 1
        )
        let checked = task.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
        return TextEdit(range: box, replacement: checked ? " " : "x", selection: selection)
    }

    /// The run of non-blank lines around `location` — what focus mode keeps
    /// bright. On a blank line, just that line.
    static func paragraphRange(in text: String, at location: Int) -> NSRange {
        let ns = text as NSString
        let lines = lineRanges(in: ns)
        func isBlank(_ index: Int) -> Bool {
            ns.substring(with: lines[index]).trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard let current = lines.firstIndex(where: { location >= $0.location && location <= NSMaxRange($0) })
        else { return NSRange(location: min(location, ns.length), length: 0) }
        guard !isBlank(current) else { return lines[current] }
        var first = current
        while first > 0, !isBlank(first - 1) { first -= 1 }
        var last = current
        while last + 1 < lines.count, !isBlank(last + 1) { last += 1 }
        return NSRange(location: lines[first].location, length: NSMaxRange(lines[last]) - lines[first].location)
    }

    /// After Tab / ⇧Tab moved lines to another nesting level: renumbers the
    /// ordered list they joined *and* the ones on either side they left, so
    /// neither is left with a gap.
    static func renumberAfterMove(in text: String, selection: NSRange) -> TextEdit? {
        let original = text as NSString
        let touched = touchedLines(in: original, selection: selection)
        let all = lineRanges(in: original)
        guard let first = all.firstIndex(where: { $0.location == touched[0].location }) else { return nil }
        let last = first + touched.count - 1

        var current = text
        var currentSelection = selection
        // Line indices survive renumbering, which never adds or removes lines.
        for index in [last + 1, first, first - 1] where index >= 0 && index < all.count {
            let location = lineRanges(in: current as NSString)[index].location
            guard let edit = renumberList(in: current, around: location, selection: currentSelection) else { continue }
            current = edit.applied(to: current)
            currentSelection = edit.selection
        }
        return difference(from: text, to: current, selection: currentSelection)
    }

    /// One edit turning `old` into `new`: the span between their common
    /// prefix and suffix.
    static func difference(from old: String, to new: String, selection: NSRange) -> TextEdit? {
        guard old != new else { return nil }
        let a = Array(old.utf16), b = Array(new.utf16)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let replacement = String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
        return TextEdit(
            range: NSRange(location: prefix, length: a.count - suffix - prefix),
            replacement: replacement,
            selection: selection
        )
    }
}

/// Names for images pasted into a document: `assets/<document>-<time>.png`
/// next to the file, so the Markdown stays portable with its folder.
nonisolated enum PastedImage {
    static let folder = "assets"

    static func fileName(documentName: String?, date: Date, index: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = documentName.map(HTMLRenderer.slug).flatMap { $0.isEmpty ? nil : $0 } ?? "image"
        let suffix = index > 0 ? "-\(index + 1)" : ""
        return "\(base)-\(formatter.string(from: date))\(suffix).png"
    }
}
