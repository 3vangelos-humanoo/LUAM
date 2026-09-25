import SwiftUI
import UniformTypeIdentifiers

/// The document model.
///
/// `ReferenceFileDocument` (class) rather than `FileDocument` (struct) so the
/// NSTextView's own undo manager can *be* the document's undo manager, and so
/// typing doesn't push a fresh `String` value through SwiftUI on every keystroke.
///
/// Isolation: the protocol is `Sendable` with nonisolated requirements, and
/// SwiftUI reads files off the main thread, so the class opts out of the
/// target's default MainActor isolation. `@unchecked Sendable` is sound here
/// because `text` is only ever touched on the main thread once the document is
/// shared — by the editor, and by SwiftUI when it takes a snapshot — while
/// `init(configuration:)` runs before anyone else holds a reference.
nonisolated final class MarkdownDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    /// Backing store for `text`. `@Published` can't be used here: its synthesised
    /// `_text` is a mutable stored property, which a nonisolated class rejects.
    /// `nonisolated(unsafe)` states the main-thread discipline described above.
    nonisolated(unsafe) private var storage: String

    /// The Markdown source. The editor mutates this in place; `objectWillChange`
    /// fires so SwiftUI-side observers (status bar, preview, outline) refresh.
    var text: String {
        get { storage }
        set {
            guard newValue != storage else { return }
            objectWillChange.send()
            storage = newValue
        }
    }

    init(text: String = "") {
        self.storage = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Markdown is text; be forgiving about what we're handed. UTF-8 covers
        // virtually everything, UTF-16 catches files written by Windows editors
        // (both have a BOM we'd otherwise decode as mojibake), and Latin-1 is the
        // last resort that can never fail — it maps every byte to some character.
        guard let decoded = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.storage = decoded
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        text
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
