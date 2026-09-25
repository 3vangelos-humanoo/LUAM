import Foundation
import Testing

@testable import LUAM

/// Applies an edit and marks the resulting caret with `|`, so expectations read
/// like the editor looks. A ranged selection is bracketed with `|…|`.
private func edited(_ text: String, _ edit: TextEdit?) -> String? {
    guard let edit else { return nil }
    let result = edit.applied(to: text) as NSString
    let selection = edit.selection
    let head = result.substring(to: selection.location)
    let body = result.substring(with: selection)
    let tail = result.substring(from: NSMaxRange(selection))
    return selection.length == 0 ? head + "|" + tail : head + "|" + body + "|" + tail
}

/// Splits `text` on a single `|` into (text, caret offset).
private func caret(_ text: String) -> (String, NSRange) {
    let parts = text.components(separatedBy: "|")
    #expect(parts.count == 2 || parts.count == 3)
    if parts.count == 3 {
        let start = (parts[0] as NSString).length
        return (parts.joined(), NSRange(location: start, length: (parts[1] as NSString).length))
    }
    return (parts.joined(), NSRange(location: (parts[0] as NSString).length, length: 0))
}

private func newline(_ marked: String) -> String? {
    let (text, selection) = caret(marked)
    return edited(text, MarkdownEditing.insertNewline(in: text, selection: selection))
}

@Suite struct LinePrefixTests {
    @Test func bullets() {
        let prefix = MarkdownEditing.listPrefix(of: "- item")
        #expect(prefix?.marker == "-")
        #expect(prefix?.isListItem == true)
        #expect(prefix?.length == 2)
    }

    @Test func orderedMarker() {
        let prefix = MarkdownEditing.listPrefix(of: "  12) item")
        #expect(prefix?.marker == "12)")
        #expect(prefix?.number == 12)
        #expect(prefix?.delimiter == ")")
        #expect(prefix?.indent == "  ")
        #expect(prefix?.nextMarker == "13)")
    }

    @Test func taskBox() {
        let prefix = MarkdownEditing.listPrefix(of: "- [x] done")
        #expect(prefix?.task == "[x] ")
        #expect(prefix?.length == 6)
    }

    @Test func quoteOnly() {
        let prefix = MarkdownEditing.listPrefix(of: "> quoted")
        #expect(prefix?.quote == "> ")
        #expect(prefix?.isListItem == false)
    }

    @Test func quotedList() {
        let prefix = MarkdownEditing.listPrefix(of: "> - item")
        #expect(prefix?.quote == "> ")
        #expect(prefix?.marker == "-")
    }

    @Test func thematicBreakIsNotAList() {
        #expect(MarkdownEditing.listPrefix(of: "- - -") == nil)
        #expect(MarkdownEditing.listPrefix(of: "***") == nil)
    }

    @Test func plainParagraph() {
        #expect(MarkdownEditing.listPrefix(of: "just text") == nil)
    }
}

@Suite struct InsertNewlineTests {
    @Test func continuesBullet() {
        #expect(newline("- one|") == "- one\n- |")
    }

    @Test func continuesOrdered() {
        #expect(newline("1. one|") == "1. one\n2. |")
    }

    @Test func continuesTask() {
        #expect(newline("- [x] done|") == "- [x] done\n- [ ] |")
    }

    @Test func continuesQuote() {
        #expect(newline("> quoted|") == "> quoted\n> |")
    }

    @Test func emptyTopLevelItemDropsMarker() {
        #expect(newline("- one\n- |") == "- one\n|")
    }

    @Test func emptyNestedItemStepsOut() {
        #expect(newline("- one\n    - |") == "- one\n- |")
    }

    @Test func emptyQuoteLineEndsQuote() {
        #expect(newline("> one\n> |") == "> one\n|")
    }

    @Test func keepsIndentOfPlainLine() {
        #expect(newline("    indented|") == "    indented\n    |")
    }

    @Test func noEditWithoutIndentOrMarker() {
        #expect(newline("plain|") == nil)
    }

    @Test func listsDisabledInCodeBlocks() {
        let (text, selection) = caret("- one|")
        #expect(MarkdownEditing.insertNewline(in: text, selection: selection, listsEnabled: false) == nil)
    }

    @Test func splitsInTheMiddleOfAnItem() {
        #expect(newline("- one|two") == "- one\n- |two")
    }
}

@Suite struct RenumberTests {
    private func renumbered(_ marked: String) -> String? {
        let (text, selection) = caret(marked)
        return edited(text, MarkdownEditing.renumberList(in: text, around: selection.location, selection: selection))
    }

    @Test func fixesDuplicateNumbers() {
        #expect(renumbered("1. a\n1. b|\n1. c") == "1. a\n2. b|\n3. c")
    }

    @Test func countsFromTheFirstItem() {
        #expect(renumbered("3. a\n9. b|\n9. c") == "3. a\n4. b|\n5. c")
    }

    @Test func leavesCorrectListsAlone() {
        #expect(renumbered("1. a\n2. b|\n3. c") == nil)
    }

    @Test func staysWithinOneNestingLevel() {
        let text = "1. a\n    1. x\n    1. y\n1. b"
        let location = (text as NSString).range(of: "1. y").location
        let edit = MarkdownEditing.renumberList(in: text, around: location, selection: NSRange(location: location, length: 0))
        #expect(edit?.applied(to: text) == "1. a\n    1. x\n    2. y\n1. b")
    }

    @Test func ignoresBullets() {
        #expect(renumbered("- a\n- b|") == nil)
    }
}

@Suite struct IndentTests {
    private func indented(_ marked: String) -> String? {
        let (text, selection) = caret(marked)
        return edited(text, MarkdownEditing.indent(in: text, selection: selection))
    }

    private func outdented(_ marked: String) -> String? {
        let (text, selection) = caret(marked)
        return edited(text, MarkdownEditing.outdent(in: text, selection: selection))
    }

    @Test func indentsOneLine() {
        #expect(indented("- one|") == "    - one|")
    }

    @Test func indentsAfterQuoteMarkers() {
        #expect(indented("> - one|") == ">     - one|")
    }

    @Test func keepsTabsWhenTheLineUsesThem() {
        #expect(indented("\t- one|") == "\t\t- one|")
    }

    @Test func indentsEveryTouchedLine() {
        #expect(indented("|- a\n- b|") == "    |- a\n    - b|")
    }

    @Test func skipsBlankLinesInAMultiLineSelection() {
        #expect(indented("|- a\n\n- b|") == "    |- a\n\n    - b|")
    }

    @Test func outdentsSpaces() {
        #expect(outdented("    - one|") == "- one|")
    }

    @Test func outdentsAtMostFourSpaces() {
        #expect(outdented("      - one|") == "  - one|")
    }

    @Test func outdentsOneTab() {
        #expect(outdented("\t\t- one|") == "\t- one|")
    }

    @Test func outdentDoesNothingAtTheMargin() {
        #expect(outdented("- one|") == nil)
    }
}

@Suite struct PairingTests {
    private func inserted(_ string: String, _ marked: String) -> String? {
        let (text, selection) = caret(marked)
        return edited(text, MarkdownEditing.insert(string, in: text, selection: selection))
    }

    @Test func wrapsASelection() {
        #expect(inserted("(", "say |hello| there") == "say (|hello|) there")
    }

    @Test func wrapsWithAsterisks() {
        #expect(inserted("*", "|word|") == "*|word|*")
    }

    @Test func pairsBeforeEndOfLine() {
        #expect(inserted("(", "call|") == "call(|)")
    }

    @Test func doesNotPairBeforeAWord() {
        #expect(inserted("(", "|word") == nil)
    }

    @Test func stepsOverAClosingBracket() {
        #expect(inserted(")", "call(|)") == "call()|")
    }

    @Test func quotesNeedSpaceOnBothSides() {
        #expect(inserted("\"", "say |") == "say \"|\"")
        #expect(inserted("\"", "say|") == nil)
    }

    @Test func asterisksNeverAutoPair() {
        #expect(inserted("*", "text |") == nil)
        #expect(inserted("_", "text |") == nil)
    }

    @Test func backspaceRemovesBothHalves() {
        let (text, selection) = caret("call(|)")
        #expect(edited(text, MarkdownEditing.deleteBackward(in: text, selection: selection)) == "call|")
    }

    @Test func backspaceIsNormalOutsideAPair() {
        let (text, selection) = caret("call(x|)")
        #expect(MarkdownEditing.deleteBackward(in: text, selection: selection) == nil)
    }
}

@Suite struct EmphasisTests {
    private func toggled(_ marker: String, _ marked: String) -> String {
        let (text, selection) = caret(marked)
        return edited(text, MarkdownEditing.toggleWrap(marker: marker, in: text, selection: selection))!
    }

    @Test func boldsASelection() {
        #expect(toggled("**", "say |hello| now") == "say **|hello|** now")
    }

    @Test func boldsTheWordUnderTheCursor() {
        #expect(toggled("**", "say hel|lo now") == "say **|hello|** now")
    }

    @Test func unwrapsASelectionThatIncludesTheMarkers() {
        #expect(toggled("**", "say |**hello**| now") == "say |hello| now")
    }

    @Test func unwrapsMarkersAroundTheSelection() {
        #expect(toggled("**", "say **|hello|** now") == "say |hello| now")
    }

    @Test func insertsAnEmptyPairWithNothingToWrap() {
        #expect(toggled("**", "say | now") == "say **|** now")
    }

    @Test func removesAnEmptyPairAroundTheCursor() {
        #expect(toggled("**", "say **|** now") == "say | now")
    }

    @Test func italicsUseASingleMarker() {
        #expect(toggled("*", "say |hello| now") == "say *|hello|* now")
    }

    @Test func italicIgnoresBoldMarkers() {
        // `**` is a run of two, which isn't italic emphasis, so this wraps.
        #expect(toggled("*", "say |**hello**| now") == "say *|**hello**|* now")
    }

    @Test func trimsTrailingSpaceOutOfTheWrap() {
        #expect(toggled("**", "say |hello |now") == "say **|hello|** now")
    }
}

@Suite struct LinkTests {
    private func linked(_ marked: String, clipboard: String? = nil) -> String {
        let (text, selection) = caret(marked)
        return edited(text, MarkdownEditing.link(in: text, selection: selection, clipboard: clipboard))!
    }

    @Test func emptySelectionWithoutClipboard() {
        #expect(linked("see |") == "see [|]()")
    }

    @Test func emptySelectionWithAURL() {
        #expect(linked("see |", clipboard: "https://example.com") == "see [|](https://example.com)")
    }

    @Test func textSelectionWithoutClipboard() {
        #expect(linked("see |docs| now") == "see [docs](|) now")
    }

    @Test func textSelectionWithAURL() {
        #expect(linked("see |docs|", clipboard: "https://example.com") == "see [docs](https://example.com)|")
    }

    @Test func selectedURLBecomesTheTarget() {
        #expect(linked("see |https://example.com|") == "see [|](https://example.com)")
    }

    @Test func clipboardNoiseIsIgnored() {
        #expect(linked("see |docs|", clipboard: "not a url") == "see [docs](|)")
    }

    @Test func validURLAcceptsCommonSchemes() {
        #expect(MarkdownEditing.validURL("https://example.com") == "https://example.com")
        #expect(MarkdownEditing.validURL("  mailto:a@b.com \n") == "mailto:a@b.com")
        #expect(MarkdownEditing.validURL("example.com") == nil)
        #expect(MarkdownEditing.validURL("https://") == nil)
        #expect(MarkdownEditing.validURL("https://a b.com") == nil)
    }
}

@Suite struct DroppedFileTests {
    private let base = URL(fileURLWithPath: "/Users/me/notes")

    @Test func imagesEmbedAndOthersLink() {
        let urls = [
            URL(fileURLWithPath: "/Users/me/notes/img/shot.png"),
            URL(fileURLWithPath: "/Users/me/notes/spec.pdf"),
        ]
        #expect(
            MarkdownEditing.fileLinks(for: urls, relativeTo: base)
                == "![shot](img/shot.png)\n[spec.pdf](spec.pdf)"
        )
    }

    @Test func pathsClimbOutOfTheDocumentFolder() {
        let url = URL(fileURLWithPath: "/Users/me/pictures/a.png")
        #expect(MarkdownEditing.linkPath(for: url, relativeTo: base) == "../pictures/a.png")
    }

    @Test func unrelatedPathsStayAbsolute() {
        let url = URL(fileURLWithPath: "/Volumes/disk/a.png")
        #expect(MarkdownEditing.linkPath(for: url, relativeTo: base) == "file:///Volumes/disk/a.png")
    }

    @Test func spacesAndParenthesesArePercentEncoded() {
        let url = URL(fileURLWithPath: "/Users/me/notes/my shot (1).png")
        let path = MarkdownEditing.linkPath(for: url, relativeTo: base)
        #expect(path == "my%20shot%20%281%29.png")
    }

    @Test func bracketsInTheLabelAreEscaped() {
        let url = URL(fileURLWithPath: "/Users/me/notes/a[1].png")
        #expect(MarkdownEditing.fileLinks(for: [url], relativeTo: base).hasPrefix("![a\\[1\\]]"))
    }

    @Test func noBaseMeansAbsolute() {
        let url = URL(fileURLWithPath: "/Users/me/notes/a.png")
        #expect(MarkdownEditing.linkPath(for: url, relativeTo: nil) == "file:///Users/me/notes/a.png")
    }
}
