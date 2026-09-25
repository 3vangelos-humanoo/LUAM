import SwiftUI

/// LUAM — Lift up and Markdown.
///
/// `DocumentGroup` gives us open, save, autosave, Versions, state restoration,
/// document tabs and multi-window for free; everything below it is ours.
@main
struct LUAMApp: App {
    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { configuration in
            DocumentWindow(
                document: configuration.document,
                fileURL: configuration.fileURL,
                isEditable: configuration.isEditable
            )
        }
        .commands {
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                ViewModeCommands()
                WritingModeCommands()
                ZoomCommands()
            }
            CommandMenu("Format") {
                FormatCommands()
            }
            CommandGroup(after: .importExport) {
                ExportCommands()
            }
            CommandGroup(replacing: .printItem) {
                PrintCommand()
            }
            CommandGroup(after: .pasteboard) {
                CopyHTMLCommand()
            }
            CommandGroup(replacing: .help) {
                Link(
                    "Markdown Reference",
                    destination: URL(string: "https://commonmark.org/help/")!
                )
                Link(
                    "GitHub Flavored Markdown Spec",
                    destination: URL(string: "https://github.github.com/gfm/")!
                )
            }
        }

        Settings {
            SettingsView()
        }
    }
}

private struct ViewModeCommands: View {
    @FocusedBinding(\.viewMode) private var mode

    var body: some View {
        Section {
            button("Source Only", .source, "1")
            button("Split", .split, "2")
            button("Preview Only", .preview, "3")
        }
    }

    private func button(_ title: String, _ target: ViewMode, _ key: KeyEquivalent) -> some View {
        Toggle(title, isOn: Binding(
            get: { mode == target },
            set: { if $0 { mode = target } }
        ))
        .keyboardShortcut(key, modifiers: .command)
        .disabled(mode == nil)
    }
}

private struct WritingModeCommands: View {
    @AppStorage(AppSettings.Key.focusMode) private var focusMode = false
    @AppStorage(AppSettings.Key.typewriterMode) private var typewriterMode = false

    var body: some View {
        Section {
            Toggle("Focus Mode", isOn: $focusMode)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Typewriter Scrolling", isOn: $typewriterMode)
                .keyboardShortcut("y", modifiers: [.command, .option])
        }
    }
}

private struct ZoomCommands: View {
    var body: some View {
        Section {
            Button("Bigger Text") { AppSettings.zoom(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { AppSettings.zoom(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { AppSettings.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}

/// The Format menu. Everything edits the source pane, so it's disabled when
/// the window only shows the preview.
private struct FormatCommands: View {
    @FocusedObject private var session: EditorSession?
    @FocusedBinding(\.viewMode) private var mode

    var body: some View {
        Section {
            item("Bold", .bold, "b")
            item("Italic", .italic, "i")
            item("Strikethrough", .strikethrough, "x", [.command, .shift])
            item("Inline Code", .code, "k", [.command, .shift])
            item("Link", .link, "k")
        }
        Section {
            Menu("Heading") {
                item("Body Text", .heading(0), "0", [.command, .control])
                ForEach(1...6, id: \.self) { level in
                    item("Heading \(level)", .heading(level), KeyEquivalent(Character("\(level)")), [.command, .control])
                }
            }
            item("Quote", .lineStyle(.quote), "'", [.command, .shift])
            item("Bulleted List", .lineStyle(.bullet), "l", [.command, .shift])
            item("Numbered List", .lineStyle(.numbered), "l", [.command, .option])
            item("Task List", .lineStyle(.task), "t", [.command, .shift])
        }
        Section {
            Menu("Insert") {
                item("Table", .insert(.table), "t", [.command, .option, .shift])
                item("Code Block", .insert(.codeBlock), "c", [.command, .option, .shift])
                item("Divider", .insert(.rule), "-", [.command, .option, .shift])
            }
            item("Align Table", .formatTable, "t", [.command, .option])
        }
    }

    private func item(
        _ title: String, _ action: FormatAction, _ key: KeyEquivalent,
        _ modifiers: EventModifiers = .command
    ) -> some View {
        Button(title) { session?.textView?.perform(action) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(session == nil || mode == .preview)
    }
}

private struct ExportCommands: View {
    @FocusedObject private var session: EditorSession?

    var body: some View {
        Section {
            Button("Export as HTML…") {
                guard let session else { return }
                Task { await DocumentExporter.exportHTML(.init(session: session), from: session.window) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export as PDF…") {
                guard let session else { return }
                Task { await DocumentExporter.exportPDF(.init(session: session), from: session.window) }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
        }
        .disabled(session == nil)
    }
}

private struct PrintCommand: View {
    @FocusedObject private var session: EditorSession?

    var body: some View {
        Button("Print…") {
            guard let session else { return }
            Task { await DocumentExporter.print(.init(session: session), from: session.window) }
        }
        .keyboardShortcut("p", modifiers: .command)
        .disabled(session == nil)
    }
}

private struct CopyHTMLCommand: View {
    @FocusedObject private var session: EditorSession?

    var body: some View {
        Button("Copy as HTML") {
            guard let session else { return }
            DocumentExporter.copyHTML(.init(session: session))
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(session == nil)
    }
}
