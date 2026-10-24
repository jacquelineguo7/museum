import SwiftUI
import ImageIO

/// Loads an image file off the main thread and shows it scaled to fit.
struct LocalImage: View {
    let url: URL?
    var maxPixelSize = 1600

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit()
            } else {
                Rectangle().fill(.quaternary).frame(height: 160)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await Self.load(url, maxPixelSize: maxPixelSize).map { Image(decorative: $0, scale: 1) }
        }
    }

    @concurrent
    private static func load(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
