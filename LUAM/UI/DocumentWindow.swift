import SwiftUI

/// Which panes a document window shows. ⌘1 / ⌘2 / ⌘3.
enum ViewMode: String, CaseIterable {
    case source, split, preview

    var title: String {
        switch self {
        case .source: "Source"
        case .split: "Split"
        case .preview: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .source: "doc.plaintext"
        case .split: "rectangle.split.2x1"
        case .preview: "doc.richtext"
        }
    }
}

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
}

/// One document window's contents: outline | source | preview, plus a status bar.
struct DocumentWindow: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    var isEditable: Bool

    @StateObject private var session = EditorSession()
    @SceneStorage("viewMode") private var mode: ViewMode = .split
    @SceneStorage("showOutline") private var showOutline = true

    @AppStorage(AppSettings.Key.editorFontSize) private var editorFontSize = AppSettings.defaultEditorFontSize
    @AppStorage(AppSettings.Key.previewFontSize) private var previewFontSize = AppSettings.defaultPreviewFontSize
    @AppStorage(AppSettings.Key.previewTheme) private var theme = PreviewTheme.standard
    @AppStorage(AppSettings.Key.syncScrolling) private var syncScrolling = true
    @AppStorage(AppSettings.Key.spellChecking) private var spellChecking = true
    @AppStorage(AppSettings.Key.focusMode) private var focusMode = false
    @AppStorage(AppSettings.Key.typewriterMode) private var typewriterMode = false

    var body: some View {
        NavigationSplitView(columnVisibility: outlineVisibility) {
            OutlineSidebar(session: session)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 360)
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    if mode != .preview {
                        MarkdownTextView(
                            document: document, session: session,
                            isEditable: isEditable, spellChecking: spellChecking,
                            focusMode: focusMode, typewriterMode: typewriterMode
                        )
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if mode != .source {
                        PreviewWebView(controller: session.preview)
                            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Divider()
                StatusBar(stats: session.stats)
            }
        }
        .toolbar {
            FormattingToolbar(session: session, isEnabled: isEditable && mode != .preview)
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $mode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Show source, both, or the preview (⌘1 / ⌘2 / ⌘3)")
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .focusedSceneValue(\.viewMode, $mode)
        .focusedSceneObject(session)
        .onAppear {
            session.document = document
            session.fileURL = fileURL
            applySettings()
            // Preview-only windows never create the text view, so parse here too.
            session.textChanged(document.text, immediately: true)
        }
        .onChange(of: fileURL) { _, url in
            session.fileURL = url
        }
        .onChange(of: ObjectIdentifier(document)) {
            // A revert (e.g. the file changed on disk) can hand us a new document.
            session.document = document
        }
        .onChange(of: document.text) { _, text in
            // Covers edits the text view didn't make (revert, preview-only mode).
            session.textChanged(text)
        }
        .onChange(of: editorFontSize) { applySettings() }
        .onChange(of: previewFontSize) { applySettings() }
        .onChange(of: theme) { applySettings() }
        .onChange(of: syncScrolling) { applySettings() }
    }

    private var outlineVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { showOutline ? .all : .detailOnly },
            set: { showOutline = $0 != .detailOnly }
        )
    }

    private func applySettings() {
        session.editorFontSize = editorFontSize
        session.previewStyle = PreviewStyle(theme: theme, fontSize: previewFontSize)
        session.syncScrolling = syncScrolling
    }
}
