import AppKit
import Combine

/// Per-window glue between the source pane, the parser and the preview.
///
/// Edits are debounced (~100 ms), parsed and rendered off the main actor, and
/// applied only if the text hasn't moved on in the meantime. The session also
/// keeps the two panes' scroll positions in step via source line numbers,
/// feeds the outline, and knows what an export needs.
final class EditorSession: ObservableObject {
    struct Stats: Equatable {
        var words = 0
        var lines = 0
        var minutes: Int { words == 0 ? 0 : max(1, Int((Double(words) / 230).rounded())) }
    }

    @Published private(set) var stats = Stats()
    @Published private(set) var outline: [OutlineItem] = []
    /// The heading whose section is at the top of the visible pane.
    @Published private(set) var currentHeading: OutlineItem.ID?

    let preview = PreviewController()
    private(set) weak var textView: MarkdownEditingTextView?

    /// The saved file, if any: the base for relative links, dropped files and
    /// export names.
    var fileURL: URL? {
        didSet { preview.setBaseURL(fileURL?.deletingLastPathComponent()) }
    }

    var syncScrolling = true

    /// For edits made from the preview while no editor is showing.
    weak var document: MarkdownDocument?

    var editorFontSize = AppSettings.defaultEditorFontSize {
        didSet {
            guard editorFontSize != oldValue else { return }
            restyleEditor()
        }
    }

    var previewStyle = PreviewStyle() {
        didSet { preview.setStyle(previewStyle.css) }
    }

    /// The newest text handed to `textChanged`, parsed or not.
    private(set) var source = ""

    private var tree: MarkdownTree?
    private var parsedText: String?
    private var pending: Task<Void, Never>?
    private var ignoreEditorScrollUntil = Date.distantPast
    private var ignorePreviewScrollUntil = Date.distantPast
    private var scrollObserver: NSObjectProtocol?

    init() {
        preview.onScroll = { [weak self] line in self?.previewDidScroll(toLine: line) }
        preview.onToggleTask = { [weak self] line in self?.toggleTask(line: line) }
    }

    // MARK: Editor

    func attach(_ textView: MarkdownEditingTextView) {
        guard self.textView !== textView else { return }
        self.textView = textView
        textView.session = self
        let styler = styler
        textView.font = .monospacedSystemFont(ofSize: styler.baseSize, weight: .regular)
        textView.typingAttributes = styler.baseAttributes
        if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
        guard let clip = textView.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.editorDidScroll() }
        }
    }

    /// Schedules a reparse. `immediately` skips the debounce and always
    /// restyles — use it when the text view's string was replaced wholesale
    /// (first load, revert), which drops all attributes.
    func textChanged(_ text: String, immediately: Bool = false) {
        source = text
        guard immediately || text != parsedText else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            let result = await Task.detached(priority: .userInitiated) {
                let tree = MarkdownParser().parse(text)
                return (tree, HTMLRenderer().render(tree), Self.wordCount(text), DocumentOutline.items(in: tree))
            }.value
            guard !Task.isCancelled, let self else { return }
            self.apply(text: text, tree: result.0, html: result.1, words: result.2, outline: result.3)
        }
    }

    private func apply(text: String, tree: MarkdownTree, html: String, words: Int, outline: [OutlineItem]) {
        // The user may have typed while we parsed; ranges would be stale.
        if let textView, textView.string == text, let storage = textView.textStorage {
            styler.apply(tree, to: storage)
        }
        self.tree = tree
        parsedText = text
        preview.setContent(html)
        let stats = Stats(words: words, lines: tree.lineCount)
        if stats != self.stats { self.stats = stats }
        if outline != self.outline { self.outline = outline }
        updateCurrentHeading()
    }

    private var styler: SyntaxStyler { SyntaxStyler(baseSize: CGFloat(editorFontSize)) }

    private func restyleEditor() {
        guard let textView else { return }
        let styler = styler
        textView.font = .monospacedSystemFont(ofSize: styler.baseSize, weight: .regular)
        textView.typingAttributes = styler.baseAttributes
        if let tree, textView.string == parsedText, let storage = textView.textStorage {
            styler.apply(tree, to: storage)
        } else {
            textChanged(textView.string, immediately: true)
        }
    }

    /// Whether `location` is inside a code block, going by the last parse —
    /// at most one debounce behind the text, which is close enough for
    /// deciding how Return and Tab behave.
    func isInCodeBlock(at location: Int) -> Bool {
        var inside = false
        tree?.forEachBlock { block in
            guard !inside, case .codeBlock = block.kind else { return }
            inside = location > block.range.location && location < NSMaxRange(block.range)
        }
        return inside
    }

    // MARK: Preview edits

    /// A task checkbox clicked in the preview. Goes through the text view
    /// when it's on screen (so it's one undo step like any edit), otherwise
    /// straight into the document with its own undo.
    func toggleTask(line: Int) {
        if let textView, textView.window != nil {
            let selection = textView.selectedRange()
            if let edit = MarkdownEditing.toggleTask(in: textView.string, line: line, selection: selection) {
                textView.apply(edit)
            }
            return
        }
        guard let document, let edit = MarkdownEditing.toggleTask(
            in: document.text, line: line, selection: NSRange(location: 0, length: 0)
        ) else { return }
        replaceText(of: document, with: edit.applied(to: document.text))
    }

    private func replaceText(of document: MarkdownDocument, with text: String) {
        let old = document.text
        document.text = text
        let undo = window?.undoManager
        undo?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.replaceText(of: document, with: old) }
        }
        undo?.setActionName("Toggle Task")
    }

    // MARK: Outline

    /// Scrolls both panes to a heading and puts the cursor on it.
    func reveal(_ item: OutlineItem) {
        let line = Double(item.line)
        let now = Date()
        ignoreEditorScrollUntil = now.addingTimeInterval(0.3)
        ignorePreviewScrollUntil = now.addingTimeInterval(0.3)
        scrollEditor(toLine: line)
        if let textView, let start = Self.offset(ofLine: item.line, in: textView.string as NSString) {
            textView.setSelectedRange(NSRange(location: start, length: 0))
        }
        preview.scrollToLine(line)
        visibleLine = line
        currentHeading = item.id
    }

    private var visibleLine = 1.0

    private func updateCurrentHeading() {
        let id = DocumentOutline.item(containing: visibleLine, in: outline)?.id
        if id != currentHeading { currentHeading = id }
    }

    // MARK: Export

    /// Title for exported files and pages: the file name, else the first heading.
    var documentTitle: String {
        if let name = fileURL?.deletingPathExtension().lastPathComponent { return name }
        return outline.first?.title ?? "Untitled"
    }

    /// The window a save panel or print sheet should attach to.
    var window: NSWindow? {
        textView?.window ?? preview.webView.window
    }

    nonisolated private static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    // MARK: Scroll sync

    private func editorDidScroll() {
        guard Date() >= ignoreEditorScrollUntil, let line = topVisibleLine() else { return }
        visibleLine = line
        updateCurrentHeading()
        guard syncScrolling else { return }
        ignorePreviewScrollUntil = Date().addingTimeInterval(0.2)
        preview.scrollToLine(line)
    }

    private func previewDidScroll(toLine line: Double) {
        guard Date() >= ignorePreviewScrollUntil else { return }
        // Without a visible editor the preview decides where the reader is.
        if !syncScrolling && textView?.window != nil { return }
        visibleLine = line
        updateCurrentHeading()
        guard syncScrolling else { return }
        ignoreEditorScrollUntil = Date().addingTimeInterval(0.2)
        scrollEditor(toLine: line)
    }

    /// The 1-based source line at the top of the editor, with a fraction for
    /// how far into that line's fragment the viewport starts.
    private func topVisibleLine() -> Double? {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
              let clip = textView.enclosingScrollView?.contentView else { return nil }
        let text = textView.string as NSString
        guard text.length > 0 else { return 1 }

        let y = clip.bounds.minY - textView.textContainerOrigin.y
        guard y > 0 else { return 1 }
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let char = min(layout.characterIndexForGlyph(at: glyph), text.length - 1)

        let lineRange = text.lineRange(for: NSRange(location: char, length: 0))
        let lineNumber = Self.lineNumber(at: lineRange.location, in: text)
        let glyphs = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let fraction = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 0.999) : 0
        return Double(lineNumber) + fraction
    }

    private func scrollEditor(toLine line: Double) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }
        let text = textView.string as NSString
        let whole = max(1, Int(line.rounded(.down)))
        guard let start = Self.offset(ofLine: whole, in: text) else { return }

        let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
        let glyphs = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let y = rect.minY + rect.height * (line - Double(whole)) + textView.textContainerOrigin.y

        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    private static func lineNumber(at offset: Int, in text: NSString) -> Int {
        var line = 1
        var index = 0
        while index < offset {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            guard NSMaxRange(range) <= offset, NSMaxRange(range) > index else { break }
            index = NSMaxRange(range)
            line += 1
        }
        return line
    }

    private static func offset(ofLine target: Int, in text: NSString) -> Int? {
        guard text.length > 0 else { return nil }
        var line = 1
        var index = 0
        while line < target {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            guard NSMaxRange(range) < text.length else { return index }
            index = NSMaxRange(range)
            line += 1
        }
        return index
    }
}
