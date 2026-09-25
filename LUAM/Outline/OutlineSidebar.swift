import SwiftUI

/// The sidebar: the document's headings, indented by level. The section at
/// the top of the visible pane is selected; clicking a heading jumps there.
struct OutlineSidebar: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        let top = session.outline.map(\.level).min() ?? 1
        List(selection: selection) {
            ForEach(session.outline) { item in
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fontWeight(item.level == top ? .semibold : .regular)
                    .foregroundStyle(item.level > top + 1 ? .secondary : .primary)
                    .padding(.leading, CGFloat(item.level - top) * 12)
                    .help(item.title)
                    .tag(item.id)
                    .contentShape(Rectangle())
                    // Selection only reports changes; a click on the current
                    // section should still jump back to its heading.
                    .simultaneousGesture(TapGesture().onEnded { session.reveal(item) })
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if session.outline.isEmpty {
                ContentUnavailableView(
                    "No Headings", systemImage: "list.bullet.indent",
                    description: Text("Lines starting with # appear here.")
                )
            }
        }
    }

    private var selection: Binding<OutlineItem.ID?> {
        Binding(
            get: { session.currentHeading },
            set: { id in
                guard let item = session.outline.first(where: { $0.id == id }) else { return }
                session.reveal(item)
            }
        )
    }
}
