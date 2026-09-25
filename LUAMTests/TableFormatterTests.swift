import Foundation
import Testing

@testable import LUAM

private let sample = """
| Name | Qty | Price |
| :--- | :-: | ----: |
| Tea | 2 | 3.50 |
"""

@Suite struct SplitCellsTests {
    @Test func trimsOuterPipesAndWhitespace() {
        #expect(TableFormatter.splitCells("| a | b |") == ["a", "b"])
    }

    @Test func worksWithoutOuterPipes() {
        #expect(TableFormatter.splitCells("a | b") == ["a", "b"])
    }

    @Test func keepsEmptyCells() {
        #expect(TableFormatter.splitCells("| a |  | c |") == ["a", "", "c"])
    }

    @Test func escapedPipesStayInTheCell() {
        #expect(TableFormatter.splitCells(#"| a \| b | c |"# ) == [#"a \| b"#, "c"])
    }

    @Test func pipesInCodeSpansDoNotSplit() {
        #expect(TableFormatter.splitCells("| `a | b` | c |") == ["`a | b`", "c"])
    }

    @Test func aTrailingEscapedPipeIsContent() {
        #expect(TableFormatter.splitCells(#"| a | b \|"#) == ["a", #"b \|"#])
    }
}

@Suite struct TableDetectionTests {
    @Test func findsTheTableAroundTheCursor() {
        let table = TableFormatter.table(in: sample, at: 0)
        #expect(table?.columnCount == 3)
        #expect(table?.rows.count == 3)
        #expect(table?.rows[0] == ["Name", "Qty", "Price"])
        #expect(table?.rows[2] == ["Tea", "2", "3.50"])
        #expect(table?.alignments == [.left, .center, .right])
    }

    @Test func picksUpTheIndent() {
        let text = "  | a | b |\n  | - | - |\n  | 1 | 2 |"
        #expect(TableFormatter.table(in: text, at: 0)?.indent == "  ")
    }

    @Test func padsShortRows() {
        let text = "| a | b | c |\n| - | - | - |\n| 1 |"
        let table = TableFormatter.table(in: text, at: 0)
        #expect(table?.rows[2] == ["1", "", ""])
    }

    @Test func alignmentsDefaultToNone() {
        let text = "| a | b |\n| --- | --- |\n| 1 | 2 |"
        #expect(TableFormatter.table(in: text, at: 0)?.alignments == [.none, .none])
    }

    @Test func nilWithoutADelimiterRow() {
        let text = "| a | b |\n| 1 | 2 |"
        #expect(TableFormatter.table(in: text, at: 0) == nil)
    }

    @Test func nilOutsideAnyTable() {
        let text = "just a paragraph"
        #expect(TableFormatter.table(in: text, at: 0) == nil)
    }

    @Test func aBlankLineEndsTheTable() {
        let text = sample + "\n\n| x | y |\n| - | - |"
        let table = TableFormatter.table(in: text, at: 0)
        #expect(table?.rows.count == 3)
    }

    @Test func nilWhenTheCursorIsOnAPrecedingLine() {
        let text = "intro | text\n" + sample
        #expect(TableFormatter.table(in: text, at: 0) == nil)
    }
}

@Suite struct FormattedLinesTests {
    @Test func padsColumnsToTheWidestCell() {
        let table = TableFormatter.table(in: sample, at: 0)!
        #expect(
            TableFormatter.formattedLines(table) == [
                "| Name | Qty | Price |",
                "| :--- | :-: | ----: |",
                "| Tea  |  2  |  3.50 |",
            ]
        )
    }

    @Test func columnsAreAtLeastThreeWide() {
        let text = "| a | b |\n| - | - |\n| 1 | 2 |"
        let table = TableFormatter.table(in: text, at: 0)!
        #expect(
            TableFormatter.formattedLines(table) == [
                "| a   | b   |",
                "| --- | --- |",
                "| 1   | 2   |",
            ]
        )
    }

    @Test func centeredCellsSplitThePadding() {
        let text = "| head |\n| :-: |\n| x |"
        let table = TableFormatter.table(in: text, at: 0)!
        #expect(TableFormatter.formattedLines(table)[2] == "|  x   |")
    }

    @Test func keepsTheIndent() {
        let text = "  | a |\n  | - |\n  | 1 |"
        let table = TableFormatter.table(in: text, at: 0)!
        #expect(TableFormatter.formattedLines(table)[0] == "  | a   |")
    }

    @Test func theDelimiterRowDoesNotSetTheWidth() {
        let text = "| a |\n| --------- |\n| 1 |"
        let table = TableFormatter.table(in: text, at: 0)!
        #expect(TableFormatter.formattedLines(table)[0] == "| a   |")
    }
}

@Suite struct DisplayWidthTests {
    @Test func asciiCountsOnePerCharacter() {
        #expect(TableFormatter.displayWidth("abc") == 3)
    }

    @Test func emojiCountTwo() {
        #expect(TableFormatter.displayWidth("🎉") == 2)
    }

    @Test func cjkCountsTwo() {
        #expect(TableFormatter.displayWidth("日本語") == 6)
    }

    @Test func mixedText() {
        #expect(TableFormatter.displayWidth("a日b") == 4)
    }
}

@Suite struct FormatTableTests {
    @Test func rewritesARaggedTable() {
        let text = "|a|b|\n|-|-|\n|longer|2|"
        let edit = TableFormatter.formatTable(in: text, selection: NSRange(location: 0, length: 0))
        #expect(
            edit?.applied(to: text) == """
                | a      | b   |
                | ------ | --- |
                | longer | 2   |
                """
        )
    }

    @Test func nilWhenAlreadyFormatted() {
        let text = "| a   | b   |\n| --- | --- |\n| 1   | 2   |"
        #expect(TableFormatter.formatTable(in: text, selection: NSRange(location: 0, length: 0)) == nil)
    }

    @Test func nilOutsideATable() {
        let text = "paragraph"
        #expect(TableFormatter.formatTable(in: text, selection: NSRange(location: 0, length: 0)) == nil)
    }

    @Test func leavesTextAroundTheTableAlone() {
        let text = "intro\n\n|a|b|\n|-|-|\n|1|2|\n\noutro"
        let at = (text as NSString).range(of: "|1|2|").location
        let edit = TableFormatter.formatTable(in: text, selection: NSRange(location: at, length: 0))
        let result = edit?.applied(to: text)
        #expect(result?.hasPrefix("intro\n\n") == true)
        #expect(result?.hasSuffix("\n\noutro") == true)
        #expect(result?.contains("| 1   | 2   |") == true)
    }

    @Test func theCursorStaysInItsCell() {
        let text = "|a|b|\n|-|-|\n|1|2|"
        let at = (text as NSString).range(of: "b").location
        let edit = TableFormatter.formatTable(in: text, selection: NSRange(location: at, length: 0))!
        let result = edit.applied(to: text) as NSString
        #expect(result.substring(from: edit.selection.location).hasPrefix("b"))
    }
}

@Suite struct MoveCellTests {
    /// Runs one Tab / ⇧Tab and returns the text with the resulting selection
    /// bracketed, or `nil` when the formatter declines.
    private func moved(_ text: String, from marker: String, forward: Bool) -> String? {
        let at = (text as NSString).range(of: marker).location
        guard let edit = TableFormatter.moveCell(
            in: text, selection: NSRange(location: at, length: 0), forward: forward
        ) else { return nil }
        let result = edit.applied(to: text) as NSString
        return result.substring(to: edit.selection.location) + "«"
            + result.substring(with: edit.selection) + "»"
            + result.substring(from: NSMaxRange(edit.selection))
    }

    private let grid = """
        | a   | b   |
        | --- | --- |
        | 1   | 2   |
        """

    @Test func tabMovesToTheNextColumn() {
        #expect(moved(grid, from: "a", forward: true)?.contains("| a   | «b»   |") == true)
    }

    @Test func tabSkipsTheDelimiterRow() {
        let result = moved(grid, from: "b", forward: true)
        #expect(result?.contains("| «1»   | 2   |") == true)
    }

    @Test func tabPastTheEndAppendsARow() {
        let result = moved(grid, from: "2", forward: true)
        #expect(result?.components(separatedBy: "\n").count == 4)
        #expect(result?.hasSuffix("| «»    |     |") == true)
    }

    @Test func shiftTabGoesBack() {
        #expect(moved(grid, from: "b", forward: false)?.contains("| «a»   | b   |") == true)
    }

    @Test func shiftTabSkipsTheDelimiterRow() {
        #expect(moved(grid, from: "1", forward: false)?.contains("| a   | «b»   |") == true)
    }

    @Test func shiftTabStaysInTheFirstCell() {
        #expect(moved(grid, from: "a", forward: false)?.hasPrefix("| «a»   | b   |") == true)
    }

    @Test func nilOutsideATable() {
        #expect(TableFormatter.moveCell(in: "plain", selection: NSRange(location: 0, length: 0), forward: true) == nil)
    }
}
