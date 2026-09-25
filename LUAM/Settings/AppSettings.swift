import Foundation

/// User defaults keys and their defaults. SwiftUI views bind these with
/// `@AppStorage`; AppKit code that needs one mid-keystroke reads it here.
enum AppSettings {
    enum Key {
        static let editorFontSize = "editorFontSize"
        static let previewFontSize = "previewFontSize"
        static let previewTheme = "previewTheme"
        static let smartPairs = "smartPairs"
        static let syncScrolling = "syncScrolling"
        static let spellChecking = "spellChecking"
        static let focusMode = "focusMode"
        static let typewriterMode = "typewriterMode"
    }

    static let defaultEditorFontSize = 14.0
    static let defaultPreviewFontSize = 16.0
    static let fontSizes = 9.0...32.0

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.editorFontSize: defaultEditorFontSize,
            Key.previewFontSize: defaultPreviewFontSize,
            Key.previewTheme: PreviewTheme.standard.rawValue,
            Key.smartPairs: true,
            Key.syncScrolling: true,
            Key.spellChecking: true,
            Key.focusMode: false,
            Key.typewriterMode: false,
        ])
    }

    /// Auto-closing brackets and quotes, and stepping over closers.
    static var smartPairs: Bool { UserDefaults.standard.bool(forKey: Key.smartPairs) }

    /// ⌘+ / ⌘- / ⌘0 scale the editor and the preview together.
    static func zoom(by step: Double) {
        let defaults = UserDefaults.standard
        for key in [Key.editorFontSize, Key.previewFontSize] {
            let size = defaults.double(forKey: key) + step
            defaults.set(min(max(size, fontSizes.lowerBound), fontSizes.upperBound), forKey: key)
        }
    }

    static func resetZoom() {
        UserDefaults.standard.set(defaultEditorFontSize, forKey: Key.editorFontSize)
        UserDefaults.standard.set(defaultPreviewFontSize, forKey: Key.previewFontSize)
    }
}
