import Foundation
import Testing

@testable import LUAM

@MainActor @Suite struct PreviewPageTests {
    @Test func buildsAStandalonePage() {
        let body = HTMLRenderer(options: .export)
            .render(parse("# Hello & World\n\ntext"))
        let page = PreviewPage.document(
            title: "A & B", style: PreviewStyle(theme: .sepia, fontSize: 18).css, body: body, bodyClass: "luam-export"
        )
        #expect(page.contains("<title>A &amp; B</title>"))
        #expect(page.contains("<body class=\"luam-export\">"))
        #expect(page.contains("<h1 id=\"hello--world\">Hello &amp; World</h1>"))
        #expect(!page.contains("data-line"))
        #expect(!page.contains("<script>"))
    }

    @Test func styleCarriesSizeAndTheme() {
        #expect(PreviewStyle(theme: .standard, fontSize: 17.4).css == ":root { --luam-font-size: 17px; }\n")
        for theme in PreviewTheme.allCases where theme != .standard {
            #expect(PreviewStyle(theme: theme).css.count > 60)
        }
    }
}
