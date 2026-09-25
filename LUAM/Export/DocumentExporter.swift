import AppKit
import UniformTypeIdentifiers
import WebKit

/// File ▸ Export as HTML / PDF, File ▸ Print and Edit ▸ Copy as HTML.
///
/// Every route renders the same standalone page: the current theme inlined,
/// no scroll-sync attributes or script, links and images left relative to the
/// document so an export saved next to it keeps working.
enum DocumentExporter {
    struct Source {
        var markdown: String
        var title: String
        var baseURL: URL?
        var style: PreviewStyle

        @MainActor init(session: EditorSession) {
            markdown = session.source
            title = session.documentTitle
            baseURL = session.fileURL?.deletingLastPathComponent()
            style = session.previewStyle
        }

        var fragment: String {
            HTMLRenderer(options: .export).render(MarkdownParser().parse(markdown))
        }

        /// The standalone page. `vendor` is the script that says where KaTeX
        /// and Mermaid come from: the CDN for HTML files, nothing (the bundle)
        /// for PDF and print, which render in LUAM's own web view.
        func page(vendor: String? = nil) -> String {
            let fragment = fragment
            let script = PreviewPage.needsRichRendering(fragment)
                ? (vendor.map { $0 + "\n" } ?? "") + PreviewPage.script
                : nil
            return PreviewPage.document(
                title: title, style: style.css, body: fragment, script: script, bodyClass: "luam-export"
            )
        }
    }

    // MARK: HTML

    static func exportHTML(_ source: Source, from window: NSWindow?) async {
        guard let url = await chooseDestination(for: source, type: .html, in: window) else { return }
        do {
            try Data(source.page(vendor: VendorSchemeHandler.cdn).utf8).write(to: url, options: .atomic)
        } catch {
            present(error, in: window)
        }
    }

    static func copyHTML(_ source: Source) {
        let fragment = source.fragment
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Rich-text apps take the formatting; code editors get the markup.
        pasteboard.setString(fragment, forType: .html)
        pasteboard.setString(fragment, forType: .string)
    }

    // MARK: PDF and print

    static func exportPDF(_ source: Source, from window: NSWindow?) async {
        guard let window, let url = await chooseDestination(for: source, type: .pdf, in: window) else { return }
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        await run(source, info: info, showPanels: false, in: window)
    }

    static func print(_ source: Source, from window: NSWindow?) async {
        guard let window else { return }
        await run(source, info: printInfo(), showPanels: true, in: window)
    }

    private static func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        for side in [\NSPrintInfo.topMargin, \.bottomMargin] { info[keyPath: side] = 54 }
        for side in [\NSPrintInfo.leftMargin, \.rightMargin] { info[keyPath: side] = 60 }
        return info
    }

    private static func run(_ source: Source, info: NSPrintInfo, showPanels: Bool, in window: NSWindow) async {
        let printer = PagePrinter()
        do {
            try await printer.load(source.page(), baseURL: source.baseURL)
            await printer.print(info: info, showPanels: showPanels, in: window)
        } catch {
            present(error, in: window)
        }
    }

    // MARK: Panels

    private static func chooseDestination(for source: Source, type: UTType, in window: NSWindow?) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = source.title
        if let base = source.baseURL { panel.directoryURL = base }
        let response = if let window {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    private static func present(_ error: Error, in window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// An off-screen web view that loads one export page and prints it —
/// to a printer, or with `jobDisposition = .save`, to a paginated PDF.
/// Always in light appearance: paper is white.
private final class PagePrinter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Error>?
    private var printed: CheckedContinuation<Void, Never>?

    override init() {
        // Printing needs a laid-out view; the page's own width is set by the
        // print info once the operation starts.
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 1100), configuration: VendorSchemeHandler.configuration()
        )
        webView.appearance = NSAppearance(named: .aqua)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ html: String, baseURL: URL?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        // Math and diagrams typeset asynchronously; wait so they're on paper.
        _ = try? await webView.callAsyncJavaScript(
            "if (window.LUAM) { await window.LUAM.renderRich(); }", contentWorld: .page
        )
    }

    func print(info: NSPrintInfo, showPanels: Bool, in window: NSWindow) async {
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = showPanels
        operation.showsProgressPanel = showPanels
        operation.jobTitle = webView.title ?? ""
        operation.view?.frame = webView.bounds
        await withCheckedContinuation { continuation in
            printed = continuation
            // Runs as a sheet and calls back when done; `self` stays alive
            // until then because this call is still awaiting.
            operation.runModal(
                for: window, delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil
            )
        }
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        printed?.resume()
        printed = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }
}
