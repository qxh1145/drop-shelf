import CoreGraphics
import Foundation
import ImageIO

struct PDFFileConverter: Sendable {
    private static let rasterDPI: CGFloat = 144
    private static let maximumPixelDimension: CGFloat = 6_000
    private static let maximumPixelCount: CGFloat = 32_000_000
    private static let maximumPDFPageDimension: CGFloat = 14_400

    func supportedOptions(for inputURL: URL) throws -> [ConversionOption] {
        let source = try inspect(inputURL)
        return options(for: source)
    }

    func convert(
        inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) throws -> [URL] {
        try Task.checkCancellation()

        let source = try inspect(inputURL)
        guard options(for: source).contains(where: {
            $0.targetFormat == targetFormat
        }) else {
            throw ConversionError.unsupportedConversion(
                source: source.format,
                target: targetFormat
            )
        }

        let destinationValues = try destinationDirectory.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        guard destinationValues.isDirectory == true else {
            throw ConversionError.destinationIsNotDirectory
        }

        switch source {
        case let .pdf(document):
            return try rasterize(
                document,
                inputURL: inputURL,
                targetFormat: targetFormat,
                destinationDirectory: destinationDirectory
            )
        case let .image(_, imageSource, imageIndex):
            return [try createPDF(
                from: imageSource,
                imageIndex: imageIndex,
                inputURL: inputURL,
                destinationDirectory: destinationDirectory
            )]
        }
    }

    private func options(for source: InspectedSource) -> [ConversionOption] {
        let destinationTypes = Set(
            (CGImageDestinationCopyTypeIdentifiers() as NSArray)
                .compactMap { $0 as? String }
        )
        return ConversionCapabilityMatrix.pdfOptions(
            from: source.format,
            availableImageDestinationTypes: destinationTypes
        )
    }

    private func inspect(_ inputURL: URL) throws -> InspectedSource {
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

        if hasPDFHeader(inputURL) {
            guard let document = CGPDFDocument(inputURL as CFURL) else {
                throw ConversionError.corruptedOrUnreadablePDF
            }
            guard !document.isEncrypted || document.isUnlocked else {
                throw ConversionError.encryptedPDFUnsupported
            }
            guard document.numberOfPages > 0 else {
                throw ConversionError.corruptedOrUnreadablePDF
            }
            return .pdf(document)
        }

        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(imageSource) as String?,
              let format = FileFormat.detect(imageIOTypeIdentifier: typeIdentifier),
              format.mediaKind == .image else {
            throw ConversionError.unsupportedSource
        }

        let imageCount = CGImageSourceGetCount(imageSource)
        guard imageCount > 0 else {
            throw ConversionError.corruptedOrUnreadableSource
        }

        let imageIndex: Int
        if format == .heic {
            let primaryImageIndex = CGImageSourceGetPrimaryImageIndex(imageSource)
            imageIndex = primaryImageIndex >= 0 && primaryImageIndex < imageCount
                ? primaryImageIndex
                : 0
        } else {
            guard imageCount == 1 else {
                throw ConversionError.multiFrameSourceUnsupported
            }
            imageIndex = 0
        }

        return .image(format, imageSource, imageIndex)
    }

    private func hasPDFHeader(_ inputURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: inputURL) else {
            return false
        }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 5)) == Data("%PDF-".utf8)
    }

    private func rasterize(
        _ document: CGPDFDocument,
        inputURL: URL,
        targetFormat: FileFormat,
        destinationDirectory: URL
    ) throws -> [URL] {
        guard targetFormat == .jpeg || targetFormat == .png else {
            throw ConversionError.unsupportedPDFTarget
        }

        let pageCount = document.numberOfPages
        let finalURLs = try availableOutputURLs(
            inputURL: inputURL,
            targetFormat: targetFormat,
            pageCount: pageCount,
            destinationDirectory: destinationDirectory
        )
        let temporaryURLs = (1...pageCount).map { pageNumber in
            destinationDirectory.appendingPathComponent(
                ".DropShelf-PDF-\(UUID().uuidString)-\(pageNumber).\(targetFormat.filenameExtension)"
            )
        }
        defer {
            for url in temporaryURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for pageNumber in 1...pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageNumber) else {
                throw ConversionError.corruptedOrUnreadablePDF
            }

            try autoreleasepool {
                try render(
                    page,
                    to: temporaryURLs[pageNumber - 1],
                    targetFormat: targetFormat
                )
            }
        }

        try Task.checkCancellation()
        return try moveTemporaryFiles(
            temporaryURLs,
            to: finalURLs
        )
    }

    private func render(
        _ page: CGPDFPage,
        to outputURL: URL,
        targetFormat: FileFormat
    ) throws {
        let box: CGPDFBox = page.getBoxRect(.cropBox).isEmpty ? .mediaBox : .cropBox
        let pageRect = page.getBoxRect(box)
        guard pageRect.width.isFinite,
              pageRect.height.isFinite,
              pageRect.width > 0,
              pageRect.height > 0 else {
            throw ConversionError.corruptedOrUnreadablePDF
        }

        let normalizedRotation = ((page.rotationAngle % 360) + 360) % 360
        let swapsDimensions = normalizedRotation == 90 || normalizedRotation == 270
        let orientedWidth = swapsDimensions ? pageRect.height : pageRect.width
        let orientedHeight = swapsDimensions ? pageRect.width : pageRect.height
        let scale = rasterScale(width: orientedWidth, height: orientedHeight)
        let pixelWidth = max(1, Int(ceil(orientedWidth * scale)))
        let pixelHeight = max(1, Int(ceil(orientedHeight * scale)))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ConversionError.cannotCreateOutput
        }

        let outputRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(outputRect)
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        let pageOutputRect = CGRect(
            x: 0,
            y: 0,
            width: orientedWidth,
            height: orientedHeight
        )
        context.concatenate(
            page.getDrawingTransform(
                box,
                rect: pageOutputRect,
                rotate: 0,
                preserveAspectRatio: true
            )
        )
        context.drawPDFPage(page)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                targetFormat.typeIdentifier as CFString,
                1,
                nil
              ) else {
            throw ConversionError.cannotCreateOutput
        }

        var properties: [String: Any] = [
            kCGImagePropertyDPIWidth as String: Self.rasterDPI,
            kCGImagePropertyDPIHeight as String: Self.rasterDPI
        ]
        if targetFormat == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.9
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.encodingFailed
        }
    }

    private func rasterScale(width: CGFloat, height: CGFloat) -> CGFloat {
        let desiredScale = Self.rasterDPI / 72
        let dimensionScale = Self.maximumPixelDimension / max(width, height)
        let pixelCountScale = sqrt(Self.maximumPixelCount / (width * height))
        return max(0.01, min(desiredScale, dimensionScale, pixelCountScale))
    }

    private func createPDF(
        from source: CGImageSource,
        imageIndex: Int,
        inputURL: URL,
        destinationDirectory: URL
    ) throws -> URL {
        try Task.checkCancellation()

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(
            source,
            imageIndex,
            nil
        ) as NSDictionary?
        let sourceWidth = (sourceProperties?[kCGImagePropertyPixelWidth] as? NSNumber)?
            .doubleValue ?? 0
        let sourceHeight = (sourceProperties?[kCGImagePropertyPixelHeight] as? NSNumber)?
            .doubleValue ?? 0
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ConversionError.corruptedOrUnreadableSource
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ceil(max(sourceWidth, sourceHeight))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            imageIndex,
            thumbnailOptions as CFDictionary
        ) else {
            throw ConversionError.corruptedOrUnreadableSource
        }

        let dpi = validDPI(
            (sourceProperties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
                ?? (sourceProperties?[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue
                ?? 72
        )
        var pageRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width) * 72 / dpi,
            height: CGFloat(image.height) * 72 / dpi
        )
        let pageScale = min(
            1,
            Self.maximumPDFPageDimension / max(pageRect.width, pageRect.height)
        )
        pageRect.size.width *= pageScale
        pageRect.size.height *= pageScale

        let finalURL = try availableOutputURLs(
            inputURL: inputURL,
            targetFormat: .pdf,
            pageCount: 1,
            destinationDirectory: destinationDirectory
        )[0]
        let temporaryURL = destinationDirectory.appendingPathComponent(
            ".DropShelf-PDF-\(UUID().uuidString).pdf"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let context = CGContext(
            temporaryURL as CFURL,
            mediaBox: &pageRect,
            nil
        ) else {
            throw ConversionError.cannotCreatePDF
        }

        context.beginPDFPage(nil as CFDictionary?)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(pageRect)
        context.interpolationQuality = CGInterpolationQuality.high
        context.draw(image, in: pageRect)
        context.endPDFPage()
        context.closePDF()

        try Task.checkCancellation()
        guard let validationDocument = CGPDFDocument(temporaryURL as CFURL),
              validationDocument.numberOfPages == 1 else {
            throw ConversionError.cannotCreatePDF
        }

        return try moveTemporaryFiles([temporaryURL], to: [finalURL])[0]
    }

    private func validDPI(_ candidate: Double) -> CGFloat {
        guard candidate.isFinite, candidate >= 36, candidate <= 1_200 else {
            return 72
        }
        return CGFloat(candidate)
    }

    private func availableOutputURLs(
        inputURL: URL,
        targetFormat: FileFormat,
        pageCount: Int,
        destinationDirectory: URL
    ) throws -> [URL] {
        let rawBaseName = inputURL.deletingPathExtension().lastPathComponent
        let originalBaseName = rawBaseName.isEmpty ? "Converted File" : rawBaseName
        let fileManager = FileManager.default

        for index in 1...10_000 {
            try Task.checkCancellation()
            let baseName = index == 1 ? originalBaseName : "\(originalBaseName) \(index)"
            let candidates: [URL]

            if pageCount == 1 {
                candidates = [destinationDirectory.appendingPathComponent(
                    "\(baseName).\(targetFormat.filenameExtension)"
                )]
            } else {
                candidates = (1...pageCount).map { pageNumber in
                    destinationDirectory.appendingPathComponent(
                        "\(baseName) - Page \(pageNumber).\(targetFormat.filenameExtension)"
                    )
                }
            }

            if candidates.allSatisfy({ !fileManager.fileExists(atPath: $0.path) }) {
                return candidates
            }
        }

        throw ConversionError.tooManyFilenameCollisions
    }

    private func moveTemporaryFiles(
        _ temporaryURLs: [URL],
        to finalURLs: [URL]
    ) throws -> [URL] {
        guard temporaryURLs.count == finalURLs.count else {
            throw ConversionError.cannotCreateOutput
        }

        let fileManager = FileManager.default
        var movedURLs: [URL] = []
        movedURLs.reserveCapacity(finalURLs.count)

        do {
            for (temporaryURL, finalURL) in zip(temporaryURLs, finalURLs) {
                try Task.checkCancellation()
                try fileManager.moveItem(at: temporaryURL, to: finalURL)
                movedURLs.append(finalURL)
            }
            return movedURLs
        } catch {
            for movedURL in movedURLs {
                try? fileManager.removeItem(at: movedURL)
            }
            throw error
        }
    }
}

private enum InspectedSource {
    case pdf(CGPDFDocument)
    case image(FileFormat, CGImageSource, Int)

    var format: FileFormat {
        switch self {
        case .pdf: return .pdf
        case let .image(format, _, _): return format
        }
    }
}
