import UniformTypeIdentifiers

// There is no built-in `UTType.markdown`. The conventional identifier is
// `net.daringfireball.markdown`, which LUAM declares in Config/Info.plist under
// UTImportedTypeDeclarations (conforming to public.plain-text).
extension UTType {
    /// The Markdown document type LUAM owns. `importedAs:` resolves against the
    /// bundle's declaration, so this is only valid because Info.plist declares
    /// it — if that entry is ever removed this will trap at first use, loudly,
    /// which is the behaviour we want.
    nonisolated static let markdown: UTType =
        UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}
