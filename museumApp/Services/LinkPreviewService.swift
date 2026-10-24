import Foundation
import LinkPresentation
import UniformTypeIdentifiers

struct LinkPreview: Sendable {
    var title: String?
    var imageData: Data?
}

/// Fetches a page's title and preview image so links can show real content in the gallery.
enum LinkPreviewService {
    static func fetch(_ url: URL) async -> LinkPreview? {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }

        var imageData: Data?
        if let imageProvider = metadata.imageProvider {
            imageData = await loadData(from: imageProvider)
        }
        return LinkPreview(title: metadata.title, imageData: imageData)
    }

    private static func loadData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// File extension matching the image bytes (the system sniffs content, but plain names help in Finder).
    static func imageExtension(for data: Data) -> String {
        data.first == 0xFF ? "jpg" : "png"
    }
}
