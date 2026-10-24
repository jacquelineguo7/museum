import Foundation
import UniformTypeIdentifiers

/// Turns whatever was dragged onto the window into something we can save:
/// an image file, image data from a browser, a link, or text.
enum DropReader {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    static func read(_ providers: [NSItemProvider]) async -> CapturedContent? {
        for provider in providers {
            if let content = await read(provider) { return content }
        }
        return nil
    }

    private static func read(_ provider: NSItemProvider) async -> CapturedContent? {
        // A file from Finder: keep it only if it's an image.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await load(URL.self, from: provider), url.isFileURL {
            guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                  let data = try? Data(contentsOf: url) else { return nil }
            return .image(CapturedImage(data: data, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension.lowercased()))
        }
        // An image dragged from a browser or another app.
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadData(from: provider, type: .image) {
            return .image(CapturedImage(data: data, name: provider.suggestedName ?? "Dropped image", fileExtension: LinkPreviewService.imageExtension(for: data)))
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await load(URL.self, from: provider) {
            return .text(url.absoluteString)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), let text = await load(String.self, from: provider) {
            return .text(text)
        }
        return nil
    }

    private static func load<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
        where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
