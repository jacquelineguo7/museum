import Foundation

/// The kind of thing a block holds. Only changes how the block is displayed.
nonisolated enum BlockKind: String, Codable, CaseIterable, Sendable {
    case image, link, post, quote, text, list, color, type, file
}

/// A position on an artifact as a fraction (0–1) of its width and height,
/// so annotations stay put when the artifact is resized or zoomed.
nonisolated struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

/// A mark made on (or about) an artifact.
nonisolated struct Annotation: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var payload: Payload

    enum Payload: Codable, Hashable, Sendable {
        case color(hex: String, name: String?, at: NormalizedPoint)
        case lasso(points: [NormalizedPoint])
        case highlight(quote: String)
        case typeface(fontName: String, sample: String?)
    }
}

/// The universal unit of the library: a link, image, quote, thought, and so on.
nonisolated struct Block: Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: BlockKind
    var title = ""
    var url: URL?
    var sourceDomain: String?
    var createdAt = Date()
    var lastSurfacedAt: Date?
    var tags: [String] = []
    /// Markdown body of `block.md`. This is the "why".
    var notes = ""
    /// File name of the image/preview stored next to `block.md`.
    var assetFilename: String?
    var annotations: [Annotation] = []
    /// Name of the block's folder inside `saves/`. Set by the store, never written to disk.
    var folderName: String?

    /// A block graduates from the Inbox once it has a note or an annotation.
    var isReflected: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !annotations.isEmpty
    }

    /// First line of the notes, shown under cards like a museum wall label.
    var wallLabel: String? {
        notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

/// A named set of blocks. One block can be in many collections.
nonisolated struct BlockCollection: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var blurb = ""
    var blockIDs: [Block.ID] = []
}

nonisolated struct LibrarySnapshot: Sendable {
    var blocks: [Block] = []
    var collections: [BlockCollection] = []
}
