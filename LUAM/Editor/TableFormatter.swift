import Foundation

/// Pipe tables in the source: aligning their columns and moving between
/// cells with Tab. Pure functions of (text, selection), like `MarkdownEditing`.
nonisolated enum TableFormatter {
    enum Alignment: Equatable { case none, left, center, right }

    /// A table as found in the source: its line ranges and parsed cells.
    struct Table {
        /// Content ranges of the table's lines, header first.
        var lines: [NSRange]
        var indent: String
        var rows: [[String]]
        var alignments: [Alignment]
        var columnCount: Int { alignments.count }
    }

    // MARK: Finding tables

    /// The table the cursor is in, if any: a block of consecutive
    /// pipe-bearing lines whose second line is a delimiter row.
    static func table(in text: String, at location: Int) -> Table? {
        let ns = text as NSString
        let lines = MarkdownEditing.lineRanges(in: ns)
        guard let current = lines.firstIndex(where: { location >= $0.location && location <= NSMaxRange($0) })
        else { return nil }

        func isRow(_ index: Int) -> Bool {
            let line = ns.substring(with: lines[index])
            return line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard isRow(current) else { return nil }
        var first = current
        while first > 0, isRow(first - 1) { first -= 1 }
        var last = current
        while last + 1 < lines.count, isRow(last + 1) { last += 1 }

        // A block may hold an unrelated pipe line before the header; find the
        // delimiter row and start just above it.
        var header: Int?
        for index in first..<last where parseDelimiter(splitCells(ns.substring(with: lines[index + 1]))) != nil {
            header = index
            break
        }
        guard let header, current >= header else { return nil }

        let tableLines = Array(lines[header...last])
        let headerText = ns.substring(with: tableLines[0])
        let indent = String(headerText.prefix { $0 == " " })
        var rows = tableLines.map { splitCells(ns.substring(with: $0)) }
        guard let alignments = parseDelimiter(rows[1]) else { return nil }
        let columns = max(alignments.count, rows.map(\.count).max() ?? 0)
        rows = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        let padded = alignments + Array(repeating: .none, count: columns - alignments.count)
        return Table(lines: tableLines, indent: indent, rows: rows, alignments: padded)
    }

    /// Splits a row on unescaped pipes (outside code spans), trimming the
    /// optional leading and trailing pipe and each cell's whitespace.
    static func splitCells(_ line: String) -> [String] {
        var trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
        if trimmed.hasPrefix("|") { trimmed = trimmed.dropFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") { trimmed = trimmed.dropLast() }

        var cells: [String] = []
        var cell = ""
        var escaped = false
        var codeRun = 0   // backtick run length that opened the current code span
        var pendingTicks = 0
        func flushTicks() {
            guard pendingTicks > 0 else { return }
            if codeRun == 0 { codeRun = pendingTicks } else if codeRun == pendingTicks { codeRun = 0 }
            pendingTicks = 0
        }
        for char in trimmed {
            if char == "`" && !escaped { pendingTicks += 1; cell.append(char); continue }
            flushTicks()
            if escaped { escaped = false; cell.append(char); continue }
            if char == "\\" { escaped = true; cell.append(char); continue }
            if char == "|" && codeRun == 0 {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                continue
            }
            cell.append(char)
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseDelimiter(_ cells: [String]) -> [Alignment]? {
        guard !cells.isEmpty else { return nil }
        var result: [Alignment] = []
        for cell in cells {
            let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
            let dashes = cell.drop { $0 == ":" }.reversed().drop { $0 == ":" }
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            result.append(left && right ? .center : left ? .left : right ? .right : .none)
        }
        return result
    }

    // MARK: Formatting

    /// The table rewritten with aligned columns, one string per line.
    static func formattedLines(_ table: Table) -> [String] {
        var widths = Array(repeating: 3, count: table.columnCount)
        for (index, row) in table.rows.enumerated() where index != 1 {
            for (column, cell) in row.enumerated() { widths[column] = max(widths[column], displayWidth(cell)) }
        }

        return table.rows.enumerated().map { index, row in
            let cells = (0..<table.columnCount).map { column -> String in
                let width = widths[column]
                if index == 1 {
                    switch table.alignments[column] {
                    case .none: return String(repeating: "-", count: width)
                    case .left: return ":" + String(repeating: "-", count: width - 1)
                    case .right: return String(repeating: "-", count: width - 1) + ":"
                    case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
                    }
                }
                let cell = row[column]
                let padding = width - displayWidth(cell)
                switch table.alignments[column] {
                case .right: return String(repeating: " ", count: padding) + cell
                case .center:
                    let leading = padding / 2
                    return String(repeating: " ", count: leading) + cell + String(repeating: " ", count: padding - leading)
                default: return cell + String(repeating: " ", count: padding)
                }
            }
            return table.indent + "| " + cells.joined(separator: " | ") + " |"
        }
    }

    /// Columns as a monospaced font lays them out: one per character, two for
    /// East Asian wide characters and emoji.
    static func displayWidth(_ string: String) -> Int {
        string.reduce(0) { total, char in
            guard let scalar = char.unicodeScalars.first else { return total }
            let wide = scalar.properties.isEmojiPresentation
                || (0x1100...0x115F).contains(scalar.value)
                || (0x2E80...0xA4CF).contains(scalar.value)
                || (0xAC00...0xD7A3).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0xFE30...0xFE4F).contains(scalar.value)
                || (0xFF00...0xFF60).contains(scalar.value)
                || (0xFFE0...0xFFE6).contains(scalar.value)
            return total + (wide ? 2 : 1)
        }
    }

    /// ⌥⌘T: aligns the table under the cursor, keeping the cursor in the same
    /// cell. `nil` if there's no table or it's already formatted.
    static func formatTable(in text: String, selection: NSRange) -> TextEdit? {
        guard let table = table(in: text, at: selection.location) else { return nil }
        let ns = text as NSString
        let (row, column) = cellPosition(of: selection.location, in: table, text: ns)
        let lines = formattedLines(table)
        let range = NSRange(location: table.lines[0].location, length: NSMaxRange(table.lines.last!) - table.lines[0].location)
        let replacement = lines.joined(separator: "\n")
        guard replacement != ns.substring(with: range) else { return nil }

        let cursor = range.location + cellStart(row: row, column: column, in: lines)
        return TextEdit(range: range, replacement: replacement, selection: NSRange(location: cursor, length: 0))
    }

    /// Tab / ⇧Tab inside a table: formats it and selects the next (or
    /// previous) cell. Tab from the last cell appends a row.
    static func moveCell(in text: String, selection: NSRange, forward: Bool) -> TextEdit? {
        guard var table = table(in: text, at: selection.location) else { return nil }
        let ns = text as NSString
        var (row, column) = cellPosition(of: selection.location, in: table, text: ns)

        if forward {
            column += 1
            if column >= table.columnCount { column = 0; row += 1 }
            if row == 1 { row = 2 }
            if row >= table.rows.count {
                table.rows.append(Array(repeating: "", count: table.columnCount))
            }
        } else {
            column -= 1
            if column < 0 { column = table.columnCount - 1; row -= 1 }
            if row == 1 { row = 0 }
            if row < 0 { row = 0; column = 0 }
        }

        let lines = formattedLines(table)
        let range = NSRange(location: table.lines[0].location, length: NSMaxRange(table.lines.last!) - table.lines[0].location)
        let start = cellStart(row: row, column: column, in: lines)
        let length = table.rows[row][column].utf16.count
        let lineStart = lines[..<row].reduce(0) { $0 + $1.utf16.count + 1 }
        // Select the cell's content, wherever alignment padding put it.
        let rowText = lines[row] as NSString
        var contentStart = start - lineStart
        while contentStart < rowText.length, rowText.character(at: contentStart) == 0x20, length > 0 { contentStart += 1 }
        return TextEdit(
            range: range, replacement: lines.joined(separator: "\n"),
            selection: NSRange(location: range.location + lineStart + contentStart, length: length)
        )
    }

    /// Which (row, column) of the table `location` falls in.
    private static func cellPosition(of location: Int, in table: Table, text: NSString) -> (Int, Int) {
        let row = table.lines.firstIndex { location <= NSMaxRange($0) } ?? table.lines.count - 1
        let line = table.lines[row]
        let before = text.substring(with: NSRange(location: line.location, length: max(0, location - line.location)))
        var pipes = 0
        var escaped = false
        for char in before {
            if escaped { escaped = false; continue }
            if char == "\\" { escaped = true } else if char == "|" { pipes += 1 }
        }
        let hasLeadingPipe = text.substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("|")
        let column = hasLeadingPipe ? pipes - 1 : pipes
        return (row, min(max(0, column), table.columnCount - 1))
    }

    /// Offset, from the start of the formatted table, of the cell's first
    /// character (just past `| `).
    private static func cellStart(row: Int, column: Int, in lines: [String]) -> Int {
        let lineStart = lines[..<row].reduce(0) { $0 + $1.utf16.count + 1 }
        let line = lines[row] as NSString
        var pipes = 0
        for index in 0..<line.length where line.character(at: index) == 0x7C {
            if pipes == column { return lineStart + min(index + 2, line.length) }
            pipes += 1
        }
        return lineStart + line.length
    }
}
