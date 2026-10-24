import Foundation

/// An image waiting to be saved, held in memory until the entry is confirmed.
nonisolated struct CapturedImage: Sendable {
    var data: Data
    var name: String
    var fileExtension: String
}

/// Something dropped onto the window (or pasted) that should become a new entry.
nonisolated enum CapturedContent: Sendable {
    case image(CapturedImage)
    case text(String)
}
