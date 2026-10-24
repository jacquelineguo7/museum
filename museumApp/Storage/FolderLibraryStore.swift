import Foundation

/// Stores the library as plain files:
///
///     <root>/saves/<date>-<slug>-<id>/block.md, reflections.json, image.*
///     <root>/collections/<slug>-<id>.md
///
/// The files are the source of truth. Writes are atomic, and deleting moves items to the Trash.
actor FolderLibraryStore: LibraryStore {
    nonisolated let root: URL
    private let fileManager = FileManager.default

    private var savesURL: URL { root.appending(path: "saves", directoryHint: .isDirectory) }
    private var collectionsURL: URL { root.appending(path: "collections", directoryHint: .isDirectory) }

    init(root: URL) {
        self.root = root
    }

    // MARK: Loading

    func loadAll() throws -> LibrarySnapshot {
        try fileManager.createDirectory(at: savesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: collectionsURL, withIntermediateDirectories: true)

        var snapshot = LibrarySnapshot()
        for folder in try contents(of: savesURL) where isDirectory(folder) {
            guard let text = try? String(contentsOf: folder.appending(path: "block.md"), encoding: .utf8),
                  var block = BlockMarkdown.parse(text) else { continue }
            block.folderName = folder.lastPathComponent
            if let data = try? Data(contentsOf: folder.appending(path: "reflections.json")),
               let annotations = try? Self.decoder.decode([Annotation].self, from: data) {
                block.annotations = annotations
            }
            snapshot.blocks.append(block)
        }
        for file in try contents(of: collectionsURL) where file.pathExtension == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let collection = BlockMarkdown.parseCollection(text) else { continue }
            snapshot.collections.append(collection)
        }
        return snapshot
    }

    // MARK: Blocks

    func save(_ block: Block) throws -> Block {
        var block = block
        let folder = try folderURL(for: &block)
        try write(BlockMarkdown.render(block), to: folder.appending(path: "block.md"))

        let annotationsURL = folder.appending(path: "reflections.json")
        if block.annotations.isEmpty {
            if fileManager.fileExists(atPath: annotationsURL.path) { try fileManager.trashItem(at: annotationsURL, resultingItemURL: nil) }
        } else {
            try Self.encoder.encode(block.annotations).write(to: annotationsURL, options: .atomic)
        }
        return block
    }

    func delete(_ block: Block) throws {
        guard let name = block.folderName else { return }
        try fileManager.trashItem(at: savesURL.appending(path: name, directoryHint: .isDirectory), resultingItemURL: nil)
    }

    func storeAsset(_ data: Data, filename: String, for block: Block) throws -> Block {
        var block = block
        let folder = try folderURL(for: &block)
        try data.write(to: folder.appending(path: filename), options: .atomic)
        block.assetFilename = filename
        return try save(block)
    }

    // MARK: Collections

    func save(_ collection: BlockCollection) throws {
        try fileManager.createDirectory(at: collectionsURL, withIntermediateDirectories: true)
        let newName = Self.collectionFileName(collection)
        // The name may have changed, so find any older file for this collection first.
        let old = collectionFile(for: collection.id)
        try write(BlockMarkdown.render(collection), to: collectionsURL.appending(path: newName))
        if let old, old.lastPathComponent != newName {
            try fileManager.trashItem(at: old, resultingItemURL: nil)
        }
    }

    func delete(_ collection: BlockCollection) throws {
        if let file = collectionFile(for: collection.id) {
            try fileManager.trashItem(at: file, resultingItemURL: nil)
        }
    }

    // MARK: Helpers

    /// Returns the block's folder, creating it (and assigning `folderName`) the first time.
    private func folderURL(for block: inout Block) throws -> URL {
        if block.folderName == nil {
            block.folderName = Self.folderName(for: block)
        }
        let url = savesURL.appending(path: block.folderName ?? "", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func collectionFile(for id: BlockCollection.ID) -> URL? {
        let suffix = "-\(id.uuidString.prefix(8).lowercased()).md"
        return (try? contents(of: collectionsURL))?.first { $0.lastPathComponent.hasSuffix(suffix) }
    }

    private func contents(of url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    nonisolated static func folderName(for block: Block) -> String {
        let day = block.createdAt.formatted(.iso8601.year().month().day())
        let name = block.title.isEmpty ? (block.sourceDomain ?? block.kind.rawValue) : block.title
        return "\(day)-\(slug(name))-\(block.id.uuidString.prefix(8).lowercased())"
    }

    nonisolated static func collectionFileName(_ collection: BlockCollection) -> String {
        "\(slug(collection.name))-\(collection.id.uuidString.prefix(8).lowercased()).md"
    }

    nonisolated static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        let trimmed = String(collapsed.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
