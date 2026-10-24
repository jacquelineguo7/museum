import Foundation
import Observation

/// In-memory state for the whole app. Views read from and write through this; it talks to a `LibraryStore`.
@Observable
final class LibraryModel {
    private(set) var blocks: [Block] = []
    private(set) var collections: [BlockCollection] = []
    private(set) var libraryURL: URL?
    var errorMessage: String?

    private var store: (any LibraryStore)?
    private var scopedURL: URL?

    init(store: (any LibraryStore)? = nil) {
        self.store = store
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    /// True once a library is open and ready.
    var isOpen: Bool { store != nil }

    /// Saved but not yet reflected on, newest first.
    var inbox: [Block] {
        blocks.filter { !$0.isReflected }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Everything that has a "why", newest first.
    var library: [Block] {
        blocks.filter(\.isReflected).sorted { $0.createdAt > $1.createdAt }
    }

    /// Every tag in use, most-used first, so suggestions can reuse them.
    var knownTags: [String] {
        let counts = blocks.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    func blocks(in collection: BlockCollection) -> [Block] {
        let ids = Set(collection.blockIDs)
        return library.filter { ids.contains($0.id) }
    }

    // MARK: Opening a library

    /// Reopens the folder remembered from the last launch, if any.
    func restoreLibrary() async {
        guard !isOpen, let url = LibraryLocation.restore() else { return }
        await open(url)
    }

    /// Opens a folder the user just picked and remembers it.
    func openLibrary(at url: URL) async {
        await open(url, remember: true)
    }

    func closeLibrary() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        store = nil
        libraryURL = nil
        blocks = []
        collections = []
        LibraryLocation.forget()
    }

    private func open(_ url: URL, remember: Bool = false) async {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        do {
            if remember { try LibraryLocation.remember(url) }
            store = FolderLibraryStore(root: url)
            libraryURL = url
            try await reload()
        } catch {
            store = nil
            libraryURL = nil
            errorMessage = "Couldn't open the library: \(error.localizedDescription)"
        }
    }

    func reload() async throws {
        guard let store else { return }
        let snapshot = try await store.loadAll()
        blocks = snapshot.blocks
        collections = snapshot.collections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Blocks

    /// Adds a new block (and its image, if any). It lands in the Inbox until it has a note.
    @discardableResult
    func add(_ block: Block, imageData: Data? = nil, imageExtension: String = "jpg") async -> Block? {
        guard let store else { return nil }
        do {
            var saved = try await store.save(block)
            if let imageData {
                saved = try await store.storeAsset(imageData, filename: "image.\(imageExtension)", for: saved)
            }
            replace(saved)
            if saved.kind == .link, saved.url != nil {
                // Fill in the page's title and image in the background.
                Task { await enrichLink(saved) }
            }
            return saved
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return nil
        }
    }

    /// Fetches the page's title and preview image and stores them with the block.
    private func enrichLink(_ original: Block) async {
        guard let url = original.url, let store, let preview = await LinkPreviewService.fetch(url) else { return }
        // Start from the latest version, since the user may have edited it meanwhile.
        guard var current = blocks.first(where: { $0.id == original.id }) else { return }
        // Don't overwrite a title the user already changed.
        if let title = preview.title, current.title == original.title { current.title = title }
        do {
            if let data = preview.imageData {
                current = try await store.storeAsset(data, filename: "preview.\(LinkPreviewService.imageExtension(for: data))", for: current)
            } else {
                current = try await store.save(current)
            }
            replace(current)
        } catch {
            errorMessage = "Couldn't save the link preview: \(error.localizedDescription)"
        }
    }

    func update(_ block: Block) async {
        guard let store else { return }
        do {
            replace(try await store.save(block))
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func delete(_ block: Block) async {
        guard let store else { return }
        do {
            try await store.delete(block)
            blocks.removeAll { $0.id == block.id }
            for var collection in collections where collection.blockIDs.contains(block.id) {
                collection.blockIDs.removeAll { $0 == block.id }
                await update(collection)
            }
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
    }

    /// Picks a random reflected block and records that it was seen.
    func wander(excluding current: Block.ID? = nil) async -> Block? {
        guard var block = RandomPicker.pick(from: library, excluding: current) else { return nil }
        block.lastSurfacedAt = .now
        await update(block)
        return block
    }

    func assetURL(for block: Block) -> URL? {
        guard let libraryURL, let folder = block.folderName, let file = block.assetFilename else { return nil }
        return libraryURL.appending(path: "saves/\(folder)/\(file)")
    }

    private func replace(_ block: Block) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
    }

    // MARK: Collections

    func addCollection(named name: String) async {
        let collection = BlockCollection(name: name)
        await update(collection)
    }

    func update(_ collection: BlockCollection) async {
        guard let store else { return }
        do {
            try await store.save(collection)
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[index] = collection
            } else {
                collections.append(collection)
                collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        } catch {
            errorMessage = "Couldn't save collection: \(error.localizedDescription)"
        }
    }

    func delete(_ collection: BlockCollection) async {
        guard let store else { return }
        do {
            try await store.delete(collection)
            collections.removeAll { $0.id == collection.id }
        } catch {
            errorMessage = "Couldn't delete collection: \(error.localizedDescription)"
        }
    }

    func toggle(_ block: Block, in collection: BlockCollection) async {
        var collection = collection
        if collection.blockIDs.contains(block.id) {
            collection.blockIDs.removeAll { $0 == block.id }
        } else {
            collection.blockIDs.append(block.id)
        }
        await update(collection)
    }
}
