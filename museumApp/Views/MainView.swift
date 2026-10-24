import SwiftUI

enum SidebarItem: Hashable {
    case inbox
    case all
    case collection(BlockCollection.ID)
}

struct MainView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.colorScheme) private var colorScheme

    @State private var selection: SidebarItem? = .inbox
    @State private var openBlock: Block?
    @State private var isAdding = false
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            gallery
                .background(Color.paper(colorScheme))
                .toolbar {
                    ToolbarItem {
                        Button("Wander", systemImage: "dice") { wander() }
                            .keyboardShortcut("r")
                            .help("Open a random block (⌘R)")
                    }
                    ToolbarItem {
                        Button("Add", systemImage: "plus") { isAdding = true }
                            .keyboardShortcut("n")
                            .help("Save something new (⌘N)")
                    }
                }
        }
        .sheet(isPresented: $isAdding) { AddBlockSheet() }
        .sheet(item: $openBlock) { block in
            BlockDetailView(block: block, onWander: { Task { openBlock = await library.wander(excluding: block.id) } })
        }
        .alert("New Collection", isPresented: $isNamingCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { Task { await library.addCollection(named: name) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Label("Inbox", systemImage: "tray")
                .badge(library.inbox.count)
                .tag(SidebarItem.inbox)
            Label("All", systemImage: "square.grid.2x2")
                .tag(SidebarItem.all)

            Section("Collections") {
                ForEach(library.collections) { collection in
                    Label(collection.name, systemImage: "rectangle.stack")
                        .tag(SidebarItem.collection(collection.id))
                        .contextMenu {
                            Button("Delete Collection", role: .destructive) {
                                if selection == .collection(collection.id) { selection = .all }
                                Task { await library.delete(collection) }
                            }
                        }
                }
                Button("New Collection", systemImage: "plus") {
                    newCollectionName = ""
                    isNamingCollection = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    // MARK: Gallery

    private var title: String {
        switch selection {
        case .inbox, nil: "Inbox"
        case .all: "All"
        case .collection(let id): library.collections.first { $0.id == id }?.name ?? "Collection"
        }
    }

    private var visibleBlocks: [Block] {
        switch selection {
        case .inbox, nil: library.inbox
        case .all: library.library
        case .collection(let id):
            library.collections.first { $0.id == id }.map(library.blocks(in:)) ?? []
        }
    }

    @ViewBuilder
    private var gallery: some View {
        let blocks = visibleBlocks
        if blocks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16, alignment: .top)], spacing: 20) {
                    ForEach(blocks) { block in
                        BlockCard(block: block, imageURL: library.assetURL(for: block))
                            .onTapGesture { openBlock = block }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch selection {
        case .inbox, nil:
            ContentUnavailableView(
                "Nothing waiting",
                systemImage: "tray",
                description: Text("Save a link, image, quote or thought with ⌘N. It stays here until you say why it matters.")
            )
        default:
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "square.grid.2x2",
                description: Text("Blocks appear here once you've written a note about them.")
            )
        }
    }

    private func wander() {
        Task {
            if let block = await library.wander(excluding: openBlock?.id) {
                openBlock = block
            } else {
                library.errorMessage = "Nothing to wander through yet. Add a note to a block in your Inbox first."
            }
        }
    }
}

#Preview {
    let model = LibraryModel(store: InMemoryLibraryStore(blocks: [
        Block(kind: .quote, title: "Less, but better.", notes: "Dieter Rams, on the whole idea."),
        Block(kind: .link, title: "Swiss Style poster archive", url: URL(string: "https://example.com"), sourceDomain: "example.com", notes: "The grid is broken on purpose."),
        Block(kind: .text, title: "Unreflected idea"),
    ]))
    MainView()
        .environment(model)
        .task { try? await model.reload() }
        .frame(width: 900, height: 600)
}
