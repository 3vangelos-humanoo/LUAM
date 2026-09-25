import SwiftUI

/// The formatting controls in a document window's toolbar. They run the same
/// `FormatAction`s as the Format menu, so they're disabled whenever the menu
/// is: preview-only windows and read-only documents.
struct FormattingToolbar: ToolbarContent {
    let session: EditorSession
    let isEnabled: Bool

    var body: some ToolbarContent {
        ToolbarItem {
            ControlGroup {
                button("Bold", "bold", .bold, "⌘B")
                button("Italic", "italic", .italic, "⌘I")
                button("Strikethrough", "strikethrough", .strikethrough, "⇧⌘X")
                button("Inline Code", "chevron.left.forwardslash.chevron.right", .code, "⇧⌘K")
                button("Link", "link", .link, "⌘K")
            } label: {
                Label("Text Style", systemImage: "bold.italic.underline")
            }
            .disabled(!isEnabled)
        }

        ToolbarItem {
            Menu {
                menuItem("Body Text", .heading(0))
                Divider()
                ForEach(1...6, id: \.self) { level in
                    menuItem("Heading \(level)", .heading(level))
                }
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            .help("Heading (⌃⌘1…6, ⌃⌘0 for body text)")
            .disabled(!isEnabled)
        }

        ToolbarItem {
            ControlGroup {
                button("Bulleted List", "list.bullet", .lineStyle(.bullet), "⇧⌘L")
                button("Numbered List", "list.number", .lineStyle(.numbered), "⌥⌘L")
                button("Task List", "checklist", .lineStyle(.task), "⇧⌘T")
                button("Quote", "text.quote", .lineStyle(.quote), "⇧⌘'")
            } label: {
                Label("Lists", systemImage: "list.bullet")
            }
            .disabled(!isEnabled)
        }

        ToolbarItem {
            Menu {
                menuItem("Table", .insert(.table), systemImage: "tablecells")
                menuItem("Code Block", .insert(.codeBlock), systemImage: "curlybraces")
                menuItem("Divider", .insert(.rule), systemImage: "minus")
                Divider()
                menuItem("Align Table", .formatTable, systemImage: "tablecells.badge.ellipsis")
            } label: {
                Label("Insert", systemImage: "plus.square.on.square")
            }
            .help("Insert a table, code block or divider")
            .disabled(!isEnabled)
        }
    }

    private func button(_ title: String, _ image: String, _ action: FormatAction, _ shortcut: String) -> some View {
        Button {
            session.textView?.perform(action)
        } label: {
            Label(title, systemImage: image)
        }
        .help("\(title) (\(shortcut))")
    }

    private func menuItem(_ title: String, _ action: FormatAction, systemImage: String? = nil) -> some View {
        Button {
            session.textView?.perform(action)
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
}
