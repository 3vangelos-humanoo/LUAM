import AppKit

/// A Format menu command, applied to the source pane's selection.
enum FormatAction {
    case bold, italic, strikethrough, code, link
    /// 0 is body text.
    case heading(Int)
    case lineStyle(MarkdownEditing.LineStyle)
    case formatTable
}

/// The source pane's text view. It decides *when* the rules in
/// `MarkdownEditing` and `TableFormatter` apply — Return, Tab, typing a
/// bracket, Backspace, dropping or pasting files and images, the Format
/// menu — and falls back to AppKit's behaviour whenever they return `nil`.
///
/// Structural changes go through `apply(_:)`, i.e. `shouldChangeText` /
/// `didChangeText`, so they're undoable and reach the document like typing.
/// Bracket pairs go through AppKit's own typing path instead, so they undo
/// together with the characters typed around them.
///
/// It also draws the two writing modes: focus (everything but the current
/// paragraph dimmed, via temporary attributes that never touch the text) and
/// typewriter (the caret's line held at the middle of the pane).
final class MarkdownEditingTextView: NSTextView {
    weak var session: EditorSession?

    var focusMode = false {
        didSet { if focusMode != oldValue { updateFocus() } }
    }

    var typewriterMode = false {
        didSet {
            guard typewriterMode != oldValue else { return }
            updateTypewriterInset()
            centerCaret()
        }
    }

    /// The inset outside typewriter mode, as set up by `MarkdownTextView`.
    var standardInset = NSSize(width: 24, height: 24)

    // MARK: Typing

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(),
              let edit = MarkdownEditing.insertNewline(
                  in: string, selection: selectedRange(), listsEnabled: !isInCodeBlock
              )
        else { return super.insertNewline(sender) }
        apply(edit)
        renumberList()
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertTab(sender) }
        let selection = selectedRange()
        if !isInCodeBlock, let edit = TableFormatter.moveCell(in: string, selection: selection, forward: true) {
            return apply(edit)
        }
        let isListItem = !isInCodeBlock && MarkdownEditing.isListItem(in: string, at: selection.location)
        if selection.length > 0 || isListItem, let edit = MarkdownEditing.indent(in: string, selection: selection) {
            apply(edit)
            return renumberAfterMove()
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertBacktab(sender) }
        let selection = selectedRange()
        if !isInCodeBlock, let edit = TableFormatter.moveCell(in: string, selection: selection, forward: false) {
            return apply(edit)
        }
        guard let edit = MarkdownEditing.outdent(in: string, selection: selection) else { return super.insertBacktab(sender) }
        apply(edit)
        renumberAfterMove()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let typed = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        if AppSettings.smartPairs, !hasMarkedText(), replacementRange.location == NSNotFound,
           let typed, !isInCodeBlock,
           let edit = MarkdownEditing.insert(typed, in: string, selection: selectedRange()) {
            if edit.range.length == 0, edit.replacement.isEmpty {
                // Stepping over a closer that's already there.
                return setSelectedRange(edit.selection)
            }
            super.insertText(edit.replacement, replacementRange: edit.range)
            return setSelectedRange(edit.selection)
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if AppSettings.smartPairs, !hasMarkedText(),
           let edit = MarkdownEditing.deleteBackward(in: string, selection: selectedRange()) {
            // Deleting the pair as a selection keeps it in the typing undo group.
            setSelectedRange(edit.range)
        }
        super.deleteBackward(sender)
    }

    // MARK: Format menu

    func perform(_ action: FormatAction) {
        let text = string
        let selection = selectedRange()
        let edit: TextEdit? = switch action {
        case .bold: MarkdownEditing.toggleWrap(marker: "**", in: text, selection: selection)
        case .italic: MarkdownEditing.toggleWrap(marker: "*", in: text, selection: selection)
        case .strikethrough: MarkdownEditing.toggleWrap(marker: "~~", in: text, selection: selection)
        case .code: MarkdownEditing.toggleWrap(marker: "`", in: text, selection: selection)
        case .link:
            MarkdownEditing.link(in: text, selection: selection, clipboard: NSPasteboard.general.string(forType: .string))
        case .heading(let level): MarkdownEditing.setHeading(level: level, in: text, selection: selection)
        case .lineStyle(let style): MarkdownEditing.toggleLineStyle(style, in: text, selection: selection)
        case .formatTable: TableFormatter.formatTable(in: text, selection: selection)
        }
        window?.makeFirstResponder(self)
        guard let edit else { return NSSound.beep() }
        apply(edit)
        if case .lineStyle(.numbered) = action { renumberList() }
    }

    // MARK: Dropped files

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        var types = super.acceptableDragTypes
        if !types.contains(.fileURL) { types.append(.fileURL) }
        return types
    }

    override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        type == .fileURL ? .copy : super.dragOperation(for: dragInfo, type: type)
    }

    /// Files dropped from Finder become Markdown links (images embed), with
    /// paths relative to the document when it has been saved.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard isEditable, !urls.isEmpty else { return super.performDragOperation(sender) }

        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        window?.makeFirstResponder(self)
        insertLinks(to: urls, at: index)
        return true
    }

    // MARK: Pasting

    /// Files copied in Finder paste as links, like a drop; a copied image
    /// (a screenshot, say) is saved to `assets/` next to the document and
    /// pasted as an image link. Anything with text on it pastes normally.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard isEditable else { return super.paste(sender) }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            return insertLinks(to: urls)
        }
        if pasteboard.string(forType: .string) == nil, let png = Self.pngData(from: pasteboard) {
            return pasteImage(png)
        }
        super.paste(sender)
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func pasteImage(_ png: Data) {
        guard let document = session?.fileURL else {
            let alert = NSAlert()
            alert.messageText = "Save the document first"
            alert.informativeText = "Pasted images are stored in an “\(PastedImage.folder)” folder next to the document, so it needs a place on disk."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        let folder = document.deletingLastPathComponent().appendingPathComponent(PastedImage.folder, isDirectory: true)
        let name = document.deletingPathExtension().lastPathComponent
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now = Date()
            var index = 0
            var url = folder.appendingPathComponent(PastedImage.fileName(documentName: name, date: now))
            while FileManager.default.fileExists(atPath: url.path) {
                index += 1
                url = folder.appendingPathComponent(PastedImage.fileName(documentName: name, date: now, index: index))
            }
            try png.write(to: url, options: .withoutOverwriting)
            insertLinks(to: [url])
        } catch {
            let alert = NSAlert(error: error)
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }

    private func insertLinks(to urls: [URL], at location: Int? = nil) {
        let markdown = MarkdownEditing.fileLinks(for: urls, relativeTo: session?.fileURL?.deletingLastPathComponent())
        let range = location.map { NSRange(location: $0, length: 0) } ?? selectedRange()
        apply(TextEdit(
            range: range, replacement: markdown,
            selection: NSRange(location: range.location + markdown.utf16.count, length: 0)
        ))
    }

    // MARK: Focus and typewriter

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting else { return }
        updateFocus()
        centerCaret()
    }

    override func didChangeText() {
        super.didChangeText()
        updateFocus()
    }

    private func updateFocus() {
        guard let layout = layoutManager else { return }
        let length = (string as NSString).length
        let full = NSRange(location: 0, length: length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        guard focusMode, length > 0 else { return }
        let focus = MarkdownEditing.paragraphRange(in: string, at: selectedRange().location)
        let dim: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor]
        layout.addTemporaryAttributes(dim, forCharacterRange: NSRange(location: 0, length: focus.location))
        layout.addTemporaryAttributes(dim, forCharacterRange: NSRange(location: NSMaxRange(focus), length: length - NSMaxRange(focus)))
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateTypewriterInset()
        centerCaret()
    }

    /// Half a pane of room above the first line and below the last, so they
    /// can reach the middle too.
    private func updateTypewriterInset() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let inset = typewriterMode
            ? NSSize(width: standardInset.width, height: max(standardInset.height, clip.bounds.height / 2))
            : standardInset
        if textContainerInset != inset { textContainerInset = inset }
    }

    private func centerCaret() {
        guard typewriterMode, let layout = layoutManager, let container = textContainer,
              let scrollView = enclosingScrollView else { return }
        updateTypewriterInset()
        let clip = scrollView.contentView
        let length = (string as NSString).length
        let location = selectedRange().location
        let line: NSRect
        if location >= length, layout.extraLineFragmentTextContainer === container {
            line = layout.extraLineFragmentRect
        } else if length > 0 {
            let glyph = layout.glyphIndexForCharacter(at: min(location, length - 1))
            line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            line = .zero
        }
        let y = line.midY + textContainerOrigin.y - clip.bounds.height / 2
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Applying edits

    func apply(_ edit: TextEdit) {
        if edit.range.length == 0, edit.replacement.isEmpty {
            return setSelectedRange(edit.selection)
        }
        guard isEditable, let storage = textStorage, NSMaxRange(edit.range) <= storage.length,
              shouldChangeText(in: edit.range, replacementString: edit.replacement)
        else { return }
        breakUndoCoalescing()
        storage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    private func renumberAfterMove() {
        guard let edit = MarkdownEditing.renumberAfterMove(in: string, selection: selectedRange()) else { return }
        apply(edit)
    }

    private func renumberList() {
        let selection = selectedRange()
        guard let edit = MarkdownEditing.renumberList(in: string, around: selection.location, selection: selection)
        else { return }
        apply(edit)
    }

    /// Lists, pairing and table navigation stay out of fenced and indented code.
    private var isInCodeBlock: Bool {
        session?.isInCodeBlock(at: selectedRange().location) ?? false
    }
}
