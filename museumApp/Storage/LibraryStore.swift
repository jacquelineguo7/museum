import Foundation

/// Where the library lives. Views never talk to this directly; they go through `LibraryModel`.
nonisolated protocol LibraryStore: Sendable {
    func loadAll() async throws -> LibrarySnapshot
    /// Saves the block and returns it with `folderName` filled in.
    func save(_ block: Block) async throws -> Block
    func delete(_ block: Block) async throws
    func save(_ collection: BlockCollection) async throws
    func delete(_ collection: BlockCollection) async throws
    /// Stores an image next to the block and returns the block with `assetFilename` set.
    func storeAsset(_ data: Data, filename: String, for block: Block) async throws -> Block
}

/// Used by previews and tests.
actor InMemoryLibraryStore: LibraryStore {
    private var blocks: [Block.ID: Block]
    private var collections: [BlockCollection.ID: BlockCollection]

    init(blocks: [Block] = [], collections: [BlockCollection] = []) {
        self.blocks = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        self.collections = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
    }

    func loadAll() -> LibrarySnapshot {
        LibrarySnapshot(blocks: Array(blocks.values), collections: Array(collections.values))
    }

    func save(_ block: Block) -> Block {
        blocks[block.id] = block
        return block
    }

    func delete(_ block: Block) { blocks[block.id] = nil }
    func save(_ collection: BlockCollection) { collections[collection.id] = collection }
    func delete(_ collection: BlockCollection) { collections[collection.id] = nil }

    func storeAsset(_ data: Data, filename: String, for block: Block) -> Block {
        var block = block
        block.assetFilename = filename
        blocks[block.id] = block
        return block
    }
}
