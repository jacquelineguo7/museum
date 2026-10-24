import Foundation
import CoreGraphics

/// Reads colors out of images, for pinning a shade you like.
nonisolated enum ImageSampler {
    /// The average color of a small patch around a point (0–1, origin top-left), as "#RRGGBB".
    /// Averaging a patch avoids picking up a single noisy pixel.
    static func hex(at point: NormalizedPoint, in image: CGImage, patch: Int = 7) -> String? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let centerX = Int((point.x * Double(image.width)).rounded()), centerY = Int((point.y * Double(image.height)).rounded())
        let area = CGRect(x: centerX - patch / 2, y: centerY - patch / 2, width: patch, height: patch).intersection(bounds)
        guard !area.isNull, !area.isEmpty, let cropped = image.cropping(to: area),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // Drawing the patch into a single pixel makes the system do the averaging.
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2]) : nil
    }
}
