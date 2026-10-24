import SwiftUI

/// A small search box for choosing which block to link to.
struct LinkPicker: View {
    /// Left out of the list, so a block can't link to itself.
    var excluding: Block.ID?
    let onPick: (Block) -> Void

    @Environment(LibraryModel.self) private var library
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var matches: [Block] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return library.blocks
            .filter { $0.id != excluding && !$0.title.isEmpty }
            .filter { trimmed.isEmpty || $0.title.localizedStandardContains(trimmed) || $0.tags.contains { $0.localizedStandardContains(trimmed) } }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Link to…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { if let first = matches.first { onPick(first) } }
            if matches.isEmpty {
                Text("No matching blocks").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(matches) { block in
                            Button { onPick(block) } label: {
                                HStack {
                                    Text(block.title).lineLimit(1)
                                    Spacer()
                                    Text(block.kind.rawValue).font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { isFocused = true }
    }
}
