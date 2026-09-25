import AppKit
import SwiftUI

/// The source pane: an `NSTextView` in a scroll view, bridged into SwiftUI.
///
/// The view only moves text in and out; the `EditorSession` reparses after
/// edits and restyles the same `textStorage` via `SyntaxStyler`.
struct MarkdownTextView: NSViewRepresentable {
    /// The document. Observed, not copied: the text view mutates `text` in place
    /// and its own undo manager is the document's.
    @ObservedObject var document: MarkdownDocument
    let session: EditorSession
    var isEditable: Bool
    var spellChecking = true
    var focusMode = false
    var typewriterMode = false

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, session: session)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        // TextKit 1: scroll sync and the styler work in layout-manager terms.
        let textView = MarkdownEditingTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        textView.delegate = context.coordinator

        // The find bar is free here and impossible in SwiftUI's TextEditor — it's
        // one of the reasons this view exists at all.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = textView.standardInset

        textView.string = document.text
        session.attach(textView)
        session.textChanged(document.text, immediately: true)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownEditingTextView else { return }

        context.coordinator.document = document
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isContinuousSpellCheckingEnabled = spellChecking
        textView.focusMode = focusMode
        textView.typewriterMode = typewriterMode

        // Only write back when the document really diverged from what's on screen
        // — e.g. a revert, or an edit made somewhere other than this view. Doing
        // it unconditionally would stomp the selection on every keystroke.
        if textView.string != document.text {
            let selection = textView.selectedRange()
            textView.string = document.text
            let clamped = NSRange(
                location: min(selection.location, document.text.utf16.count),
                length: 0
            )
            textView.setSelectedRange(clamped)
            session.textChanged(document.text, immediately: true)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        let session: EditorSession

        init(document: MarkdownDocument, session: EditorSession) {
            self.document = document
            self.session = session
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.text = textView.string
            session.textChanged(textView.string)
        }

        /// Hand SwiftUI's document machinery the text view's own undo manager, so
        /// ⌘Z undoes typing *and* drives the document's edited state and Versions.
        func undoManager(for view: NSTextView) -> UndoManager? {
            view.window?.undoManager
        }
    }
}
