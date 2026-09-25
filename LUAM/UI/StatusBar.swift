import SwiftUI

/// The strip along the bottom of a document window.
struct StatusBar: View {
    let stats: EditorSession.Stats

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("\(stats.words, format: .number) \(stats.words == 1 ? "word" : "words")")
            Text("·")
            Text("\(stats.minutes) min read")
            Text("·")
            Text("\(stats.lines, format: .number) \(stats.lines == 1 ? "line" : "lines")")
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
