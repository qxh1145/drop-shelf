import CoreGraphics
import Foundation
import ImageIO

protocol FileConverter: Sendable {
    func supportedOptions(for inputURL: URL) throws -> [ConversionOption]
    func convert(
        inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) throws -> URL
}

final class ConversionService: Sendable {
    static let shared = ConversionService()

    private let imageConverter = ImageIOFileConverter()
    private let videoConverter = AVFoundationVideoConverter()
    private let pdfConverter = PDFFileConverter()

    func supportedOutputFormats(for inputURL: URL) async -> [ConversionOption] {
        let converter = imageConverter
        let pdfConverter = pdfConverter
        let worker = Task.detached(priority: .utility) {
            autoreleasepool {
                let imageOptions = (try? converter.supportedOptions(for: inputURL)) ?? []
                let pdfOptions = (try? pdfConverter.supportedOptions(for: inputURL)) ?? []
                return (imageOptions + pdfOptions).sorted {
                    $0.targetFormat.displayName < $1.targetFormat.displayName
                }
            }
        }

        let imageOptions = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard imageOptions.isEmpty else { return imageOptions }
        guard !Task.isCancelled else { return [] }
        return await videoConverter.supportedOptions(for: inputURL)
    }

    func convert(
        _ inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) async throws -> URL {
        let outputURLs = try await convertAll(
            inputURL,
            to: targetFormat,
            destinationDirectory: destinationDirectory
        )
        guard outputURLs.count == 1, let outputURL = outputURLs.first else {
            throw ConversionError.multipleOutputFiles
        }
        return outputURL
    }

    func convertAll(
        _ inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) async throws -> [URL] {
        if targetFormat.mediaKind == .video {
            return [try await videoConverter.convert(
                inputURL: inputURL,
                to: targetFormat,
                destinationDirectory: destinationDirectory
            )]
        }

        let converter = imageConverter
        let pdfConverter = pdfConverter
        let worker = Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try Task.checkCancellation()

                if try pdfConverter.supportedOptions(for: inputURL).contains(where: {
                    $0.targetFormat == targetFormat
                }) {
                    return try pdfConverter.convert(
                        inputURL: inputURL,
                        to: targetFormat,
                        destinationDirectory: destinationDirectory
                    )
                }

                return [try converter.convert(
                    inputURL: inputURL,
                    to: targetFormat,
                    destinationDirectory: destinationDirectory
                )]
            }
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

struct ImageIOFileConverter: FileConverter {
    func supportedOptions(for inputURL: URL) throws -> [ConversionOption] {
        let inspection = try inspect(inputURL)
        let destinationTypes = Set(
            (CGImageDestinationCopyTypeIdentifiers() as NSArray)
                .compactMap { $0 as? String }
        )

        return ConversionCapabilityMatrix.options(
            from: inspection.format,
            availableDestinationTypes: destinationTypes
        )
    }

    func convert(
        inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) throws -> URL {
        try Task.checkCancellation()

        let inspection = try inspect(inputURL)
        let options = try supportedOptions(for: inputURL)
        guard options.contains(where: { $0.targetFormat == targetFormat }) else {
            throw ConversionError.unsupportedConversion(
                source: inspection.format,
                target: targetFormat
            )
        }

        let destinationValues = try destinationDirectory.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        guard destinationValues.isDirectory == true else {
            throw ConversionError.destinationIsNotDirectory
        }

        let source = inspection.source
        guard let decodedImage = CGImageSourceCreateImageAtIndex(
            source,
            inspection.imageIndex,
            nil
        ) else {
            throw ConversionError.corruptedOrUnreadableSource
        }

        try Task.checkCancellation()

        let outputImage: CGImage
        if targetFormat == .jpeg, hasAlpha(decodedImage) {
            outputImage = try imageByFlatteningTransparency(decodedImage)
        } else {
            outputImage = decodedImage
        }

        let temporaryURL = destinationDirectory
            .appendingPathComponent(".DropShelf-Conversion-\(UUID().uuidString)")
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            targetFormat.typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.cannotCreateOutput
        }

        let properties = destinationProperties(
            source: source,
            imageIndex: inspection.imageIndex,
            targetFormat: targetFormat
        )
        CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)

        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.encodingFailed
        }
        try Task.checkCancellation()

        return try moveToAvailableDestination(
            temporaryURL: temporaryURL,
            inputURL: inputURL,
            targetFormat: targetFormat,
            destinationDirectory: destinationDirectory
        )
    }

    private func inspect(
        _ inputURL: URL
    ) throws -> (format: FileFormat, source: CGImageSource, imageIndex: Int) {
        let values: URLResourceValues
        do {
            values = try inputURL.resourceValues(
                forKeys: [.isRegularFileKey, .isReadableKey]
            )
        } catch {
            throw ConversionError.sourceMissing
        }

        guard values.isRegularFile == true else {
            throw ConversionError.sourceMissing
        }
        guard values.isReadable != false else {
            throw ConversionError.sourceUnreadable
        }
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let format = FileFormat.detect(imageIOTypeIdentifier: typeIdentifier),
              format.mediaKind == .image else {
            throw ConversionError.unsupportedSource
        }
        let imageCount = CGImageSourceGetCount(source)
        guard imageCount > 0 else {
            throw ConversionError.corruptedOrUnreadableSource
        }

        let imageIndex: Int
        if format == .heic {
            let primaryImageIndex = CGImageSourceGetPrimaryImageIndex(source)
            imageIndex = primaryImageIndex >= 0 && primaryImageIndex < imageCount
                ? primaryImageIndex
                : 0
        } else {
            guard imageCount == 1 else {
                throw ConversionError.multiFrameSourceUnsupported
            }
            imageIndex = 0
        }

        return (format, source, imageIndex)
    }

    private func destinationProperties(
        source: CGImageSource,
        imageIndex: Int,
        targetFormat: FileFormat
    ) -> [String: Any] {
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(
            source,
            imageIndex,
            nil
        ) as NSDictionary?
        var properties: [String: Any] = [:]

        for key in [
            kCGImagePropertyOrientation,
            kCGImagePropertyDPIWidth,
            kCGImagePropertyDPIHeight
        ] {
            if let value = sourceProperties?[key] {
                properties[key as String] = value
            }
        }

        if targetFormat == .jpeg || targetFormat == .heic {
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.9
        }

        return properties
    }

    private func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            return true
        @unknown default:
            return true
        }
    }

    private func imageByFlatteningTransparency(_ image: CGImage) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw ConversionError.cannotFlattenTransparency
        }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)

        guard let flattenedImage = context.makeImage() else {
            throw ConversionError.cannotFlattenTransparency
        }
        return flattenedImage
    }

    private func moveToAvailableDestination(
        temporaryURL: URL,
        inputURL: URL,
        targetFormat: FileFormat,
        destinationDirectory: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let rawBaseName = inputURL.deletingPathExtension().lastPathComponent
        let baseName = rawBaseName.isEmpty ? "Converted File" : rawBaseName

        for index in 1...10_000 {
            try Task.checkCancellation()
            let suffix = index == 1 ? "" : " \(index)"
            let filename = "\(baseName)\(suffix).\(targetFormat.filenameExtension)"
            let candidate = destinationDirectory.appendingPathComponent(filename)

            do {
                try fileManager.moveItem(at: temporaryURL, to: candidate)
                return candidate
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileWriteFileExistsError {
                continue
            }
        }

        throw ConversionError.tooManyFilenameCollisions
    }
}

enum ConversionError: LocalizedError {
    case sourceMissing
    case sourceUnreadable
    case unsupportedSource
    case multiFrameSourceUnsupported
    case unsupportedConversion(source: FileFormat, target: FileFormat)
    case unsupportedVideoSource
    case unsupportedVideoTarget
    case cannotCreateVideoExportSession
    case videoExportFailed(String)
    case encryptedPDFUnsupported
    case corruptedOrUnreadablePDF
    case unsupportedPDFTarget
    case cannotCreatePDF
    case multipleOutputFiles
    case corruptedOrUnreadableSource
    case destinationIsNotDirectory
    case cannotCreateOutput
    case cannotFlattenTransparency
    case encodingFailed
    case tooManyFilenameCollisions

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "The source file no longer exists."
        case .sourceUnreadable:
            return "DropShelf does not have permission to read the source file."
        case .unsupportedSource:
            return "This file is not a supported JPEG, PNG, HEIC, PDF, MOV, or MP4 file."
        case .multiFrameSourceUnsupported:
            return "Animated or multi-frame images are not supported."
        case let .unsupportedConversion(source, target):
            return "Converting \(source.displayName) to \(target.displayName) is not supported."
        case .unsupportedVideoSource:
            return "This is not a supported MOV or MP4 video, or it does not contain a video track."
        case .unsupportedVideoTarget:
            return "The selected output is not a supported video format."
        case .cannotCreateVideoExportSession:
            return "macOS could not prepare this video for conversion. Its codecs may be unsupported."
        case let .videoExportFailed(message):
            return "The video could not be converted. \(message)"
        case .encryptedPDFUnsupported:
            return "Password-protected PDFs must be unlocked before conversion."
        case .corruptedOrUnreadablePDF:
            return "The PDF could not be read. It may be damaged or contain an invalid page."
        case .unsupportedPDFTarget:
            return "PDF pages can currently be converted only to PNG or JPEG."
        case .cannotCreatePDF:
            return "macOS could not create a valid PDF from this image."
        case .multipleOutputFiles:
            return "This conversion produced multiple files. Use the multi-file conversion result."
        case .corruptedOrUnreadableSource:
            return "The image could not be decoded. It may be damaged or use an unsupported codec."
        case .destinationIsNotDirectory:
            return "The selected destination is not a folder."
        case .cannotCreateOutput:
            return "The output file could not be created. Check folder permissions and free disk space."
        case .cannotFlattenTransparency:
            return "The image transparency could not be prepared for JPEG."
        case .encodingFailed:
            return "macOS could not encode the converted image. Check disk space and try again."
        case .tooManyFilenameCollisions:
            return "A unique output filename could not be created."
        }
    }
}
