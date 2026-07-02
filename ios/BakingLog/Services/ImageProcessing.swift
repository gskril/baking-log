import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared image-processing helper for the photo upload pipeline.
///
/// Every photo upload goes through `downsampledJPEGData(from:)` at pick time,
/// which is why `APIClient.uploadPhoto`'s hardcoded `photo.jpg` /
/// `image/jpeg` labels are always correct.
enum ImageProcessing {
    /// Longest edge of an uploaded photo, in pixels.
    static let maxPixelSize = 2048

    /// JPEG compression quality for uploads.
    static let jpegQuality: Double = 0.8

    enum ImageProcessingError: LocalizedError {
        case unreadableImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "The photo couldn't be read."
            case .encodingFailed:
                return "The photo couldn't be converted to JPEG."
            }
        }
    }

    /// Downsamples arbitrary image data (HEIC, PNG, JPEG, …) to at most
    /// `maxPixelSize` on the longest edge and re-encodes it as JPEG with the
    /// EXIF orientation baked in.
    ///
    /// Nonisolated `async`, so it runs on the global concurrent executor —
    /// decoding/encoding never blocks the main actor. Only `Data` (Sendable)
    /// crosses the boundary.
    static func downsampledJPEGData(from data: Data) async throws -> Data {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw ImageProcessingError.unreadableImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageProcessingError.unreadableImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.encodingFailed
        }
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, cgImage, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.encodingFailed
        }
        return output as Data
    }
}
