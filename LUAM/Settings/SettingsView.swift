import SwiftUI

/// LUAM ▸ Settings… (⌘,)
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Editor", systemImage: "character.cursor.ibeam") { EditorSettings() }
            Tab("Preview", systemImage: "doc.richtext") { PreviewSettings() }
        }
        .frame(width: 460)
        .scenePadding()
    }
}

private struct EditorSettings: View {
    @AppStorage(AppSettings.Key.editorFontSize) private var fontSize = AppSettings.defaultEditorFontSize
    @AppStorage(AppSettings.Key.smartPairs) private var smartPairs = true
    @AppStorage(AppSettings.Key.spellChecking) private var spellChecking = true

    var body: some View {
        Form {
            FontSizeRow(title: "Font size", size: $fontSize)
            Toggle("Close brackets and quotes automatically", isOn: $smartPairs)
            Toggle("Check spelling while typing", isOn: $spellChecking)
            LabeledContent("Shortcuts") {
                Text("Return continues lists, Tab indents or moves between table cells, ⌥⌘T aligns a table.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PreviewSettings: View {
    @AppStorage(AppSettings.Key.previewTheme) private var theme = PreviewTheme.standard
    @AppStorage(AppSettings.Key.previewFontSize) private var fontSize = AppSettings.defaultPreviewFontSize
    @AppStorage(AppSettings.Key.syncScrolling) private var syncScrolling = true

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                ForEach(PreviewTheme.allCases) { Text($0.title).tag($0) }
            }
            FontSizeRow(title: "Text size", size: $fontSize)
            Toggle("Scroll source and preview together", isOn: $syncScrolling)
            LabeledContent("Export") {
                Text("HTML, PDF and printed pages use this theme, always in its light variant for paper.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FontSizeRow: View {
    let title: String
    @Binding var size: Double

    var body: some View {
        Stepper(value: $size, in: AppSettings.fontSizes, step: 1) {
            LabeledContent(title) {
                Text("\(Int(size)) pt").monospacedDigit()
            }
        }
    }
}
