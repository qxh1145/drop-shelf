import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageToolOperation: Hashable, Sendable {
    case resize(maxPixelSize: Int)
    case compress
    case removeMetadata

    var fileSuffix: String {
        switch self {
        case let .resize(maxPixelSize): "\(maxPixelSize)px"
        case .compress: "compressed"
        case .removeMetadata: "no metadata"
        }
    }
}

enum ImageToolError: LocalizedError, Equatable {
    case unsupportedImage
    case alreadySmaller(Int)
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            String(localized: "This image type can’t be edited.")
        case let .alreadySmaller(maxPixelSize):
            String(localized: "The image is already \(maxPixelSize) px or smaller.")
        case .cannotWrite:
            String(localized: "Couldn’t save next to the original. Check that its folder is writable.")
        }
    }
}

/// Resize, compress, and metadata removal for single-frame images. Results
/// are written next to the original, which is never modified.
enum ImageTools {
    static let editableTypes: Set<String> = [
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.heic.identifier,
        UTType.tiff.identifier
    ]
    static let compressibleTypes: Set<String> = [UTType.jpeg.identifier, UTType.heic.identifier]
    static let compressionQuality = 0.6

    /// The image's type identifier when the tools can process it.
    static func editableType(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              editableTypes.contains(type) else {
            return nil
        }
        return type
    }

    static func apply(_ operation: ImageToolOperation, to url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              editableTypes.contains(type as String) else {
            throw ImageToolError.unsupportedImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] ?? [:]

        switch operation {
        case let .resize(maxPixelSize):
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            guard max(width, height) > maxPixelSize else {
                throw ImageToolError.alreadySmaller(maxPixelSize)
            }
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                throw ImageToolError.unsupportedImage
            }

            // Pixels are already rotated upright, so the tag must say so.
            var outputProperties = properties
            outputProperties[kCGImagePropertyOrientation] = 1
            if var tiff = outputProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                outputProperties[kCGImagePropertyTIFFDictionary] = tiff
            }
            outputProperties[kCGImageDestinationLossyCompressionQuality] = 0.9
            return try write(to: url, suffix: operation.fileSuffix, type: type) { destination in
                CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
                return CGImageDestinationFinalize(destination)
            }

        case .compress:
            guard compressibleTypes.contains(type as String) else {
                throw ImageToolError.unsupportedImage
            }
            var outputProperties = properties
            outputProperties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
            return try write(to: url, suffix: operation.fileSuffix, type: type) { destination in
                CGImageDestinationAddImageFromSource(
                    destination,
                    source,
                    0,
                    outputProperties as CFDictionary
                )
                return CGImageDestinationFinalize(destination)
            }

        case .removeMetadata:
            let orientation = properties[kCGImagePropertyOrientation]
            return try write(to: url, suffix: operation.fileSuffix, type: type) { destination in
                // Lossless for JPEG and PNG: pixels are copied, metadata replaced.
                let metadata = CGImageMetadataCreateMutable()
                if let orientation {
                    CGImageMetadataSetValueMatchingImageProperty(
                        metadata,
                        kCGImagePropertyTIFFDictionary,
                        kCGImagePropertyTIFFOrientation,
                        orientation as CFTypeRef
                    )
                }
                let options: [CFString: Any] = [
                    kCGImageDestinationMetadata: metadata,
                    kCGImageDestinationMergeMetadata: false
                ]
                return CGImageDestinationCopyImageSource(
                    destination,
                    source,
                    options as CFDictionary,
                    nil
                )
            } fallback: { destination in
                // Formats without lossless copy are re-encoded at full quality.
                guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    return false
                }
                var outputProperties: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: 1.0
                ]
                outputProperties[kCGImagePropertyOrientation] = orientation
                CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
                return CGImageDestinationFinalize(destination)
            }
        }
    }

    /// Writes "Name (suffix).ext", or "Name (suffix) 2.ext" when taken.
    private static func write(
        to sourceURL: URL,
        suffix: String,
        type: CFString,
        _ body: (CGImageDestination) -> Bool,
        fallback: ((CGImageDestination) -> Bool)? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = "\(sourceURL.deletingPathExtension().lastPathComponent) (\(suffix))"
        let fileExtension = sourceURL.pathExtension

        var outputURL = directory.appendingPathComponent(baseName)
            .appendingPathExtension(fileExtension)
        var index = 2
        while fileManager.fileExists(atPath: outputURL.path) {
            outputURL = directory.appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(fileExtension)
            index += 1
        }

        func attempt(_ encode: (CGImageDestination) -> Bool) throws -> Bool {
            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                type,
                1,
                nil
            ) else {
                throw ImageToolError.cannotWrite
            }
            if encode(destination) { return true }
            try? fileManager.removeItem(at: outputURL)
            return false
        }

        if try attempt(body) {
            return outputURL
        }
        if let fallback, try attempt(fallback) {
            return outputURL
        }
        throw ImageToolError.cannotWrite
    }
}
