import Foundation

/// A block whose inline content hasn't been parsed yet. Inline parsing waits
/// until the whole document has been read, so that reference links can use
/// definitions that appear further down.
nonisolated struct PendingBlock: Sendable {
    var block: Block
    var children: [PendingBlock] = []
    /// Inline content of headings and paragraphs, one segment per line.
    var segments: [Segment] = []

    func finalize(_ inline: InlineParser) -> Block {
        var result = block
        result.children = children.map { $0.finalize(inline) }
        if !segments.isEmpty {
            result.inlines = inline.parse(segments)
        }
        if case .table(var table) = result.kind {
            func parseCells(_ row: inout TableRow) {
                for c in row.cells.indices where row.cells[c].range.length > 0 {
                    let r = row.cells[c].range
                    row.cells[c].inlines = inline.parse([Segment(start: r.location, end: NSMaxRange(r))])
                }
            }
            parseCells(&table.header)
            for r in table.rows.indices { parseCells(&table.rows[r]) }
            result.kind = .table(table)
        }
        return result
    }
}

/// Splits the document into blocks — CommonMark's first phase, plus GFM tables
/// and task list items.
///
/// Containers (block quotes, list items) are handled recursively: their lines
/// are collected, stripped of the container's prefix by advancing each
/// `SourceLine`'s `start`, and parsed again. Offsets therefore always point
/// into the original buffer.
nonisolated final class BlockParser {
    private let u: [UInt16]
    private(set) var definitions: [String: LinkDefinition] = [:]

    /// Past this depth `>` and list markers are read as text, so hostile input
    /// can't exhaust the stack of a background parse.
    private static let maxDepth = 48

    init(units: [UInt16]) {
        u = units
    }

    func parse(_ lines: [SourceLine]) -> [PendingBlock] {
        parseBlocks(lines, depth: 0)
    }

    // MARK: - Dispatch

    private func parseBlocks(_ lines: [SourceLine], depth: Int) -> [PendingBlock] {
        var out: [PendingBlock] = []
        var i = 0
        while i < lines.count {
            let l = lines[i]
            let ind = indent(l)
            if ind.index == l.end {
                i += 1
                continue
            }
            if ind.columns >= 4 {
                out.append(indentedCode(lines, &i))
                continue
            }
            let p = ind.index
            let canNest = depth < Self.maxDepth
            if canNest, u[p] == C.gt {
                out.append(blockQuote(lines, &i, depth: depth))
            } else if let heading = atxHeading(l, p) {
                out.append(heading)
                i += 1
            } else if let fence = fenceOpen(l, p) {
                out.append(fencedCode(lines, &i, fence))
            } else if let html = htmlBlockStart(l, p) {
                out.append(htmlBlock(lines, &i, html))
            } else if isThematicBreak(l, p) {
                out.append(PendingBlock(block: block(
                    .thematicBreak, p, l.end, l.number, l.number,
                    markers: [NSRange(p..<trimEnd(p, l.end))])))
                i += 1
            } else if canNest, let marker = listMarker(l, p) {
                out.append(list(lines, &i, first: marker, depth: depth))
            } else if let table = table(lines, &i) {
                out.append(table)
            } else if let paragraph = paragraph(lines, &i) {
                out.append(paragraph)
            }
        }
        return out
    }

    // MARK: - Leaf blocks

    private func indentedCode(_ lines: [SourceLine], _ i: inout Int) -> PendingBlock {
        let first = i
        var last = i
        while i < lines.count {
            let ind = indent(lines[i])
            if ind.index == lines[i].end {
                i += 1
                continue
            }
            guard ind.columns >= 4 else { break }
            last = i
            i += 1
        }
        i = last + 1
        let content = lines[first...last].map { strip($0, columns: 4) }
        let code = content.map(string).joined(separator: "\n") + "\n"
        let codeBlock = CodeBlock(
            language: nil, code: code,
            contentRange: NSRange(content[0].start..<lines[last].end), fenced: false)
        return PendingBlock(block: block(
            .codeBlock(codeBlock), content[0].start, lines[last].end,
            lines[first].number, lines[last].number))
    }

    private func atxHeading(_ l: SourceLine, _ p: Int) -> PendingBlock? {
        var k = p
        while k < l.end, u[k] == C.hash, k - p <= 6 { k += 1 }
        let level = k - p
        guard level >= 1, level <= 6, k == l.end || C.isSpaceOrTab(u[k]) else { return nil }
        var markers = [NSRange(location: p, length: level)]
        let contentStart = skipSpaceTab(k, l.end)
        var contentEnd = trimEnd(contentStart, l.end)
        var h = contentEnd
        while h > contentStart, u[h - 1] == C.hash { h -= 1 }
        if h < contentEnd, h == contentStart || C.isSpaceOrTab(u[h - 1]) {
            markers.append(NSRange(h..<contentEnd))
            contentEnd = trimEnd(contentStart, h)
        }
        var pending = PendingBlock(block: block(.heading(level: level), p, l.end, l.number, l.number, markers: markers))
        if contentEnd > contentStart {
            pending.segments = [Segment(start: contentStart, end: contentEnd)]
        }
        return pending
    }

    private struct Fence {
        var char: UInt16
        var count: Int
        var indent: Int
        var infoStart: Int
        var infoEnd: Int
    }

    private func fenceOpen(_ l: SourceLine, _ p: Int) -> Fence? {
        let c = u[p]
        guard c == C.backtick || c == C.tilde else { return nil }
        var k = p
        while k < l.end, u[k] == c { k += 1 }
        guard k - p >= 3 else { return nil }
        let infoStart = skipSpaceTab(k, l.end)
        let infoEnd = trimEnd(infoStart, l.end)
        if c == C.backtick, u[infoStart..<infoEnd].contains(C.backtick) { return nil }
        return Fence(char: c, count: k - p, indent: indent(l).columns, infoStart: infoStart, infoEnd: infoEnd)
    }

    private func isFenceClose(_ l: SourceLine, _ fence: Fence) -> Bool {
        let ind = indent(l)
        guard ind.columns < 4 else { return false }
        var k = ind.index
        while k < l.end, u[k] == fence.char { k += 1 }
        guard k - ind.index >= fence.count else { return false }
        return skipSpaceTab(k, l.end) == l.end
    }

    private func fencedCode(_ lines: [SourceLine], _ i: inout Int, _ fence: Fence) -> PendingBlock {
        let open = lines[i]
        let p = indent(open).index
        var markers = [NSRange(p..<trimEnd(p, open.end))]
        var language: String?
        if fence.infoEnd > fence.infoStart {
            var w = fence.infoStart
            while w < fence.infoEnd, !C.isWhitespace(u[w]) { w += 1 }
            language = Unescape.string(u, fence.infoStart, w)
        }
        var content: [SourceLine] = []
        var last = i
        i += 1
        while i < lines.count {
            let l = lines[i]
            last = i
            i += 1
            if isFenceClose(l, fence) {
                let c = indent(l).index
                markers.append(NSRange(c..<trimEnd(c, l.end)))
                break
            }
            content.append(strip(l, columns: fence.indent))
        }
        let code = content.isEmpty ? "" : content.map(string).joined(separator: "\n") + "\n"
        let contentRange = content.isEmpty
            ? NSRange(location: open.end, length: 0)
            : NSRange(content[0].start..<max(content[0].start, content[content.count - 1].end))
        let codeBlock = CodeBlock(language: language, code: code, contentRange: contentRange, fenced: true)
        return PendingBlock(block: block(
            .codeBlock(codeBlock), p, lines[last].end, open.number, lines[last].number, markers: markers))
    }

    private enum HTMLBlockEnd {
        case pattern(String)
        case blankLine
    }

    private struct HTMLBlockStart {
        var end: HTMLBlockEnd
        var canInterruptParagraph: Bool
    }

    private static let rawTextTags = ["script", "pre", "style", "textarea"]

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
        "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
        "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav",
        "noframes", "ol", "optgroup", "option", "p", "param", "search", "section", "summary", "table",
        "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
    ]

    private func htmlBlockStart(_ l: SourceLine, _ p: Int) -> HTMLBlockStart? {
        guard u[p] == C.lt, p + 1 < l.end else { return nil }
        for tag in Self.rawTextTags where hasPrefixCI("<" + tag, p, l.end) {
            let k = p + 1 + tag.utf16.count
            if k == l.end || C.isSpaceOrTab(u[k]) || u[k] == C.gt {
                return HTMLBlockStart(end: .pattern("</" + tag + ">"), canInterruptParagraph: true)
            }
        }
        if hasPrefixCI("<!--", p, l.end) { return HTMLBlockStart(end: .pattern("-->"), canInterruptParagraph: true) }
        if hasPrefixCI("<?", p, l.end) { return HTMLBlockStart(end: .pattern("?>"), canInterruptParagraph: true) }
        if hasPrefixCI("<![CDATA[", p, l.end) { return HTMLBlockStart(end: .pattern("]]>"), canInterruptParagraph: true) }
        if p + 2 < l.end, u[p + 1] == C.bang, C.isASCIILetter(u[p + 2]) {
            return HTMLBlockStart(end: .pattern(">"), canInterruptParagraph: true)
        }
        var k = p + 1
        if u[k] == C.slash { k += 1 }
        let nameStart = k
        while k < l.end, C.isASCIIAlphanumeric(u[k]) { k += 1 }
        if k > nameStart, C.isASCIILetter(u[nameStart]) {
            let name = String(decoding: u[nameStart..<k], as: UTF16.self).lowercased()
            let terminated = k == l.end || C.isSpaceOrTab(u[k]) || u[k] == C.gt
                || (u[k] == C.slash && k + 1 < l.end && u[k + 1] == C.gt)
            if terminated, Self.blockTags.contains(name) {
                return HTMLBlockStart(end: .blankLine, canInterruptParagraph: true)
            }
        }
        let tagEnd = u[p + 1] == C.slash ? HTMLSyntax.closingTag(u, p, l.end) : HTMLSyntax.openTag(u, p, l.end)
        if let tagEnd, skipSpaceTab(tagEnd, l.end) == l.end {
            return HTMLBlockStart(end: .blankLine, canInterruptParagraph: false)
        }
        return nil
    }

    private func htmlBlock(_ lines: [SourceLine], _ i: inout Int, _ start: HTMLBlockStart) -> PendingBlock {
        let first = i
        var last = i
        switch start.end {
        case .pattern(let pattern):
            while last < lines.count - 1, !containsCI(lines[last], pattern) { last += 1 }
        case .blankLine:
            while last + 1 < lines.count, !isBlank(lines[last + 1]) { last += 1 }
        }
        i = last + 1
        let html = lines[first...last].map(string).joined(separator: "\n") + "\n"
        return PendingBlock(block: block(
            .htmlBlock(html), indent(lines[first]).index, lines[last].end,
            lines[first].number, lines[last].number))
    }

    private func isThematicBreak(_ l: SourceLine, _ p: Int) -> Bool {
        let c = u[p]
        guard c == C.star || c == C.minus || c == C.underscore else { return false }
        var count = 0
        for k in p..<l.end {
            if u[k] == c {
                count += 1
            } else if !C.isSpaceOrTab(u[k]) {
                return false
            }
        }
        return count >= 3
    }

    private func setextLevel(_ l: SourceLine, _ p: Int) -> Int? {
        let c = u[p]
        guard c == C.equals || c == C.minus else { return nil }
        var k = p
        while k < l.end, u[k] == c { k += 1 }
        return skipSpaceTab(k, l.end) == l.end ? (c == C.equals ? 1 : 2) : nil
    }

    private func paragraph(_ lines: [SourceLine], _ i: inout Int) -> PendingBlock? {
        var body = [lines[i]]
        i += 1
        var underline: (level: Int, line: SourceLine)?
        while i < lines.count {
            let l = lines[i]
            let ind = indent(l)
            if ind.index == l.end { break }
            if ind.columns < 4, let level = setextLevel(l, ind.index) {
                underline = (level, l)
                i += 1
                break
            }
            if interruptsParagraph(l) { break }
            body.append(l)
            i += 1
        }

        var firstContent = 0
        while firstContent < body.count, linkDefinition(body[firstContent]) { firstContent += 1 }
        var content = Array(body[firstContent...])
        if content.isEmpty {
            // Only definitions: a would-be underline is just text.
            guard let underline else { return nil }
            content = [underline.line]
            return paragraphBlock(content)
        }

        guard let underline else { return paragraphBlock(content) }
        let marker = indent(underline.line).index
        var pending = paragraphBlock(content)
        pending.block.kind = .heading(level: underline.level)
        pending.block.range = NSRange(pending.block.range.location..<underline.line.end)
        pending.block.endLine = underline.line.number
        pending.block.markers = [NSRange(marker..<trimEnd(marker, underline.line.end))]
        return pending
    }

    private func paragraphBlock(_ lines: [SourceLine]) -> PendingBlock {
        var segments = lines.map { Segment(start: indent($0).index, end: $0.end) }
        segments[segments.count - 1].end = trimEnd(segments[segments.count - 1].start, segments[segments.count - 1].end)
        var pending = PendingBlock(block: block(
            .paragraph, segments[0].start, lines[lines.count - 1].end,
            lines[0].number, lines[lines.count - 1].number))
        pending.segments = segments
        return pending
    }

    /// Registers a single-line `[label]: destination "title"` definition.
    private func linkDefinition(_ l: SourceLine) -> Bool {
        let s = indent(l).index
        guard s < l.end, u[s] == C.lbracket,
              let (labelEnd, afterLabel) = LinkSyntax.label(u, s, l.end),
              afterLabel < l.end, u[afterLabel] == C.colon
        else { return false }
        let destStart = skipSpaceTab(afterLabel + 1, l.end)
        guard let (destination, destEnd) = LinkSyntax.destination(u, destStart, l.end) else { return false }
        var title: String?
        let titleStart = skipSpaceTab(destEnd, l.end)
        if titleStart < l.end {
            guard titleStart > destEnd,
                  let (parsed, titleEnd) = LinkSyntax.title(u, titleStart, l.end),
                  skipSpaceTab(titleEnd, l.end) == l.end
            else { return false }
            title = parsed
        }
        let key = LinkSyntax.normalize(String(decoding: u[(s + 1)..<labelEnd], as: UTF16.self))
        if definitions[key] == nil {
            definitions[key] = LinkDefinition(destination: destination, title: title)
        }
        return true
    }

    // MARK: - Tables

    private func table(_ lines: [SourceLine], _ i: inout Int) -> PendingBlock? {
        guard i + 1 < lines.count else { return nil }
        let headerLine = lines[i]
        let delimiterLine = lines[i + 1]
        let delimiterIndent = indent(delimiterLine)
        guard delimiterIndent.columns < 4, delimiterIndent.index < delimiterLine.end else { return nil }
        let header = splitRow(headerLine)
        guard !header.pipes.isEmpty else { return nil }
        let delimiter = splitRow(delimiterLine)
        guard delimiter.cells.count == header.cells.count,
              !delimiter.pipes.isEmpty || header.cells.count == 1
        else { return nil }
        var alignments: [Table.Alignment] = []
        for cell in delimiter.cells {
            guard let alignment = alignment(cell) else { return nil }
            alignments.append(alignment)
        }

        var markers = header.pipes
        markers.append(NSRange(delimiterIndent.index..<trimEnd(delimiterIndent.index, delimiterLine.end)))
        let headerRow = tableRow(headerLine, header.cells, columns: alignments.count)
        var rows: [TableRow] = []
        var last = i + 1
        i += 2
        while i < lines.count, !isBlank(lines[i]), !interruptsParagraph(lines[i]) {
            let split = splitRow(lines[i])
            markers.append(contentsOf: split.pipes)
            rows.append(tableRow(lines[i], split.cells, columns: alignments.count))
            last = i
            i += 1
        }
        let table = Table(alignments: alignments, header: headerRow, rows: rows)
        return PendingBlock(block: block(
            .table(table), indent(headerLine).index, lines[last].end,
            headerLine.number, lines[last].number, markers: markers))
    }

    private func tableRow(_ l: SourceLine, _ segments: [Segment], columns: Int) -> TableRow {
        var cells = segments.prefix(columns).map {
            TableCell(inlines: [], range: NSRange($0.start..<$0.end))
        }
        let end = trimEnd(l.start, l.end)
        while cells.count < columns {
            cells.append(TableCell(inlines: [], range: NSRange(location: end, length: 0)))
        }
        return TableRow(cells: cells, range: NSRange(indent(l).index..<l.end), line: l.number)
    }

    /// Cells split on unescaped pipes, trimmed; plus the pipes themselves.
    private func splitRow(_ l: SourceLine) -> (cells: [Segment], pipes: [NSRange]) {
        var s = indent(l).index
        var e = trimEnd(s, l.end)
        var pipes: [NSRange] = []
        var trailingPipe: NSRange?
        if s < e, u[s] == C.pipe {
            pipes.append(NSRange(location: s, length: 1))
            s += 1
        }
        if e > s, u[e - 1] == C.pipe, !(e - 2 >= s && u[e - 2] == C.backslash) {
            trailingPipe = NSRange(location: e - 1, length: 1)
            e -= 1
        }
        var cells: [Segment] = []
        var cellStart = s
        var k = s
        while k < e {
            if u[k] == C.backslash {
                k += 2
                continue
            }
            if u[k] == C.pipe {
                cells.append(trimmed(cellStart, k))
                pipes.append(NSRange(location: k, length: 1))
                cellStart = k + 1
            }
            k += 1
        }
        cells.append(trimmed(cellStart, e))
        if let trailingPipe { pipes.append(trailingPipe) }
        return (cells, pipes)
    }

    private func alignment(_ cell: Segment) -> Table.Alignment? {
        guard cell.end > cell.start else { return nil }
        var s = cell.start
        var e = cell.end
        let left = u[s] == C.colon
        if left { s += 1 }
        let right = e > s && u[e - 1] == C.colon
        if right { e -= 1 }
        guard e > s, u[s..<e].allSatisfy({ $0 == C.minus }) else { return nil }
        switch (left, right) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return Table.Alignment.none
        }
    }

    // MARK: - Containers

    private func blockQuote(_ lines: [SourceLine], _ i: inout Int, depth: Int) -> PendingBlock {
        let first = i
        var last = i
        var inner: [SourceLine] = []
        var markers: [NSRange] = []
        var lazy = LazyState()
        while i < lines.count {
            let l = lines[i]
            let ind = indent(l)
            if ind.columns < 4, ind.index < l.end, u[ind.index] == C.gt {
                markers.append(NSRange(location: ind.index, length: 1))
                var content = advance(l, to: ind.index + 1)
                if content.start < content.end, C.isSpaceOrTab(u[content.start]) {
                    content = strip(content, columns: 1)
                }
                inner.append(content)
                feed(&lazy, content)
            } else if ind.index == l.end || !lazy.inParagraph || interruptsParagraph(l) {
                break
            } else {
                inner.append(l)
            }
            last = i
            i += 1
        }
        var pending = PendingBlock(block: block(
            .blockQuote, indent(lines[first]).index, lines[last].end,
            lines[first].number, lines[last].number, markers: markers))
        pending.children = parseBlocks(inner, depth: depth + 1)
        return pending
    }

    private struct ListMarker {
        var ordered: Bool
        var delimiter: UInt16
        var number: Int
        var range: NSRange
        /// The rest of the line once the marker and its padding are gone.
        var content: SourceLine
        /// Absolute visual column continuation lines must reach.
        var contentColumn: Int
        var blank: Bool
    }

    private func listMarker(_ l: SourceLine, _ p: Int) -> ListMarker? {
        var k = p
        var ordered = false
        var number = 0
        let delimiter: UInt16
        let c = u[k]
        if c == C.minus || c == C.plus || c == C.star {
            delimiter = c
            k += 1
        } else if C.isDigit(c) {
            while k < l.end, C.isDigit(u[k]), k - p < 10 {
                number = number * 10 + Int(u[k] - 0x30)
                k += 1
            }
            guard k - p <= 9, k < l.end, u[k] == C.dot || u[k] == C.rparen else { return nil }
            ordered = true
            delimiter = u[k]
            k += 1
        } else {
            return nil
        }
        guard k == l.end || C.isSpaceOrTab(u[k]) else { return nil }
        let afterMarker = advance(l, to: k)
        let rest = indent(afterMarker)
        let blank = rest.index == l.end
        let content: SourceLine
        let contentColumn: Int
        if blank {
            content = advance(afterMarker, to: l.end)
            contentColumn = afterMarker.column + 1
        } else if rest.columns > 4 {
            // Five or more spaces: one is padding, the rest start indented code.
            content = strip(afterMarker, columns: 1)
            contentColumn = afterMarker.column + 1
        } else {
            content = strip(afterMarker, columns: rest.columns)
            contentColumn = afterMarker.column + rest.columns
        }
        return ListMarker(
            ordered: ordered, delimiter: delimiter, number: number, range: NSRange(p..<k),
            content: content, contentColumn: contentColumn, blank: blank)
    }

    private func list(_ lines: [SourceLine], _ i: inout Int, first: ListMarker, depth: Int) -> PendingBlock {
        var items: [PendingBlock] = []
        var tight = true
        var blankBefore = false
        while i < lines.count {
            let l = lines[i]
            let ind = indent(l)
            guard ind.columns < 4, ind.index < l.end, !isThematicBreak(l, ind.index),
                  let marker = listMarker(l, ind.index),
                  marker.ordered == first.ordered, marker.delimiter == first.delimiter
            else { break }
            if blankBefore { tight = false }
            let (item, loose) = listItem(lines, &i, marker, depth: depth)
            if loose { tight = false }
            items.append(item)
            var next = i
            while next < lines.count, isBlank(lines[next]) { next += 1 }
            blankBefore = next > i
            if next == lines.count { break }
            i = next
        }
        let firstItem = items[0].block
        let lastItem = items[items.count - 1].block
        let style = ListStyle(ordered: first.ordered, start: first.number, tight: tight)
        var pending = PendingBlock(block: block(
            .list(style), firstItem.range.location, NSMaxRange(lastItem.range),
            firstItem.line, lastItem.endLine))
        pending.children = items
        return pending
    }

    /// Returns the item and whether blank lines separate its direct children.
    private func listItem(
        _ lines: [SourceLine], _ i: inout Int, _ marker: ListMarker, depth: Int
    ) -> (PendingBlock, Bool) {
        let first = i
        var markers = [marker.range]
        var task: Bool?
        var content = marker.content
        let c = content.start
        if !marker.blank, c + 3 < content.end, u[c] == C.lbracket, u[c + 2] == C.rbracket,
           u[c + 1] == C.space || u[c + 1] == 0x78 || u[c + 1] == 0x58,
           C.isSpaceOrTab(u[c + 3]), skipSpaceTab(c + 3, content.end) < content.end {
            task = u[c + 1] != C.space
            markers.append(NSRange(location: c, length: 3))
            content = advance(content, to: skipSpaceTab(c + 3, content.end))
        }

        var inner = [content]
        var lazy = LazyState()
        feed(&lazy, content)
        var lastContent = i
        i += 1
        while i < lines.count {
            let l = lines[i]
            let ind = indent(l)
            if ind.index == l.end {
                // An item can start with at most one blank line.
                if marker.blank, lastContent == first { break }
                inner.append(l)
                feed(&lazy, l)
            } else if l.column + ind.columns >= marker.contentColumn {
                let stripped = strip(l, columns: marker.contentColumn - l.column)
                inner.append(stripped)
                feed(&lazy, stripped)
                lastContent = i
            } else if lazy.inParagraph, lastContent == i - 1, !interruptsParagraph(l),
                      ind.columns >= 4 || listMarker(l, ind.index) == nil {
                // Inside a list any marker starts a sibling item, even "2.".
                inner.append(l)
                lastContent = i
            } else {
                break
            }
            i += 1
        }
        i = lastContent + 1
        inner.removeLast(inner.count - (lastContent - first + 1))

        let children = parseBlocks(inner, depth: depth + 1)
        var loose = false
        for k in children.indices.dropFirst() where children[k].block.line - children[k - 1].block.endLine > 1 {
            loose = true
        }
        var pending = PendingBlock(block: block(
            .listItem(task: task), marker.range.location, lines[lastContent].end,
            lines[first].number, lines[lastContent].number, markers: markers))
        pending.children = children
        return (pending, loose)
    }

    /// Whether `l`, at the current container level, starts a block that ends
    /// an open paragraph (rather than continuing it).
    private func interruptsParagraph(_ l: SourceLine) -> Bool {
        let ind = indent(l)
        guard ind.columns < 4, ind.index < l.end else { return false }
        let p = ind.index
        if u[p] == C.gt || isThematicBreak(l, p) || atxHeading(l, p) != nil || fenceOpen(l, p) != nil {
            return true
        }
        if let html = htmlBlockStart(l, p) { return html.canInterruptParagraph }
        if let marker = listMarker(l, p) { return !marker.blank && (!marker.ordered || marker.number == 1) }
        return false
    }

    // MARK: - Lazy continuation

    /// Tracks whether the lines collected into a container so far end in an
    /// open paragraph — the condition for accepting a "lazy" line that lacks
    /// the container's prefix. An approximation of full re-parsing that is
    /// exact for the cases people actually write.
    private struct LazyState {
        var inParagraph = false
        var fence: Fence?
        var inHTML = false
    }

    private func feed(_ state: inout LazyState, _ line: SourceLine) {
        var l = line
        var ind = indent(l)
        if ind.index == l.end {
            state.inParagraph = false
            state.inHTML = false
            return
        }
        if let fence = state.fence {
            if isFenceClose(l, fence) { state.fence = nil }
            return
        }
        if state.inHTML || ind.columns >= 4 { return }

        var p = ind.index
        var nested = false
        for _ in 0..<8 {
            if u[p] == C.gt {
                l = advance(l, to: p + 1)
                if l.start < l.end, C.isSpaceOrTab(u[l.start]) { l = strip(l, columns: 1) }
            } else if !isThematicBreak(l, p), let marker = listMarker(l, p) {
                l = marker.content
            } else {
                break
            }
            nested = true
            ind = indent(l)
            if ind.index == l.end || ind.columns >= 4 {
                state.inParagraph = false
                return
            }
            p = ind.index
        }

        if !nested, state.inParagraph, setextLevel(l, p) != nil {
            state.inParagraph = false
        } else if isThematicBreak(l, p) || atxHeading(l, p) != nil {
            state.inParagraph = false
        } else if let fence = fenceOpen(l, p) {
            if !nested { state.fence = fence }
            state.inParagraph = false
        } else if let html = htmlBlockStart(l, p), html.canInterruptParagraph || !state.inParagraph {
            if case .blankLine = html.end, !nested { state.inHTML = true }
            state.inParagraph = false
        } else {
            state.inParagraph = true
        }
    }

    // MARK: - Line helpers

    private struct Indent {
        /// Visual width of the leading whitespace.
        var columns: Int
        /// First code unit that isn't a space or tab.
        var index: Int
    }

    private func indent(_ l: SourceLine) -> Indent {
        var column = l.column
        var k = l.start
        while k < l.end {
            if u[k] == C.space {
                column += 1
            } else if u[k] == C.tab {
                column += 4 - column % 4
            } else {
                break
            }
            k += 1
        }
        return Indent(columns: column - l.column, index: k)
    }

    private func isBlank(_ l: SourceLine) -> Bool {
        indent(l).index == l.end
    }

    /// Consumes up to `columns` of leading whitespace. A tab that straddles
    /// the boundary is consumed whole.
    private func strip(_ l: SourceLine, columns: Int) -> SourceLine {
        var l = l
        let target = l.column + columns
        while l.column < target, l.start < l.end {
            if u[l.start] == C.space {
                l.column += 1
            } else if u[l.start] == C.tab {
                l.column += 4 - l.column % 4
            } else {
                break
            }
            l.start += 1
        }
        return l
    }

    private func advance(_ l: SourceLine, to index: Int) -> SourceLine {
        var l = l
        while l.start < index {
            l.column += u[l.start] == C.tab ? 4 - l.column % 4 : 1
            l.start += 1
        }
        return l
    }

    private func string(_ l: SourceLine) -> String {
        l.end > l.start ? String(decoding: u[l.start..<l.end], as: UTF16.self) : ""
    }

    private func skipSpaceTab(_ start: Int, _ end: Int) -> Int {
        var k = start
        while k < end, C.isSpaceOrTab(u[k]) { k += 1 }
        return k
    }

    private func trimEnd(_ start: Int, _ end: Int) -> Int {
        var e = end
        while e > start, C.isSpaceOrTab(u[e - 1]) { e -= 1 }
        return e
    }

    private func trimmed(_ start: Int, _ end: Int) -> Segment {
        let s = skipSpaceTab(start, end)
        return Segment(start: s, end: trimEnd(s, end))
    }

    private func hasPrefixCI(_ prefix: String, _ start: Int, _ end: Int) -> Bool {
        var k = start
        for p in prefix.utf16 {
            guard k < end, C.lower(u[k]) == p else { return false }
            k += 1
        }
        return true
    }

    private func containsCI(_ l: SourceLine, _ pattern: String) -> Bool {
        let count = pattern.utf16.count
        var k = l.start
        while k + count <= l.end {
            if hasPrefixCI(pattern, k, l.end) { return true }
            k += 1
        }
        return false
    }

    private func block(
        _ kind: Block.Kind, _ start: Int, _ end: Int, _ line: Int, _ endLine: Int, markers: [NSRange] = []
    ) -> Block {
        Block(
            kind: kind, range: NSRange(location: start, length: max(0, end - start)),
            line: line, endLine: endLine, markers: markers)
    }
}
