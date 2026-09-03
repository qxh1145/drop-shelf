import Foundation
import UniformTypeIdentifiers

enum FileFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png
    case heic
    case mov
    case mp4
    case pdf

    enum MediaKind: Sendable {
        case image
        case video
        case document
    }

    static let imageFormats: [FileFormat] = [.jpeg, .png, .heic]
    static let videoFormats: [FileFormat] = [.mov, .mp4]
    static let documentFormats: [FileFormat] = [.pdf]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .mov: return "MOV"
        case .mp4: return "MP4"
        case .pdf: return "PDF"
        }
    }

    var filenameExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .mov: return "mov"
        case .mp4: return "mp4"
        case .pdf: return "pdf"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .heic: return UTType.heic.identifier
        case .mov: return UTType.quickTimeMovie.identifier
        case .mp4: return UTType.mpeg4Movie.identifier
        case .pdf: return UTType.pdf.identifier
        }
    }

    var mediaKind: MediaKind {
        switch self {
        case .jpeg, .png, .heic:
            return .image
        case .mov, .mp4:
            return .video
        case .pdf:
            return .document
        }
    }

    static func detect(imageIOTypeIdentifier identifier: String) -> FileFormat? {
        guard let type = UTType(identifier) else { return nil }

        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .pdf) { return .pdf }
        if identifier == UTType.heic.identifier
            || identifier == UTType.heif.identifier
            || identifier == "public.heics"
            || type.conforms(to: .heic)
            || type.conforms(to: .heif) {
            return .heic
        }
        return nil
    }
}

enum ConversionRisk: Int, Sendable {
    case none
    case low
    case medium
    case high
}

struct ConversionOption: Identifiable, Hashable, Sendable {
    let sourceFormat: FileFormat
    let targetFormat: FileFormat
    let risk: ConversionRisk
    let warning: String?

    var id: String {
        "\(sourceFormat.rawValue)-to-\(targetFormat.rawValue)"
    }
}

enum ConversionState: Equatable, Sendable {
    case idle
    case converting
    case success(URL)
    case failed(String)
}

enum ConversionCapabilityMatrix {
    static let nativeImageOptions: [ConversionOption] = [
        ConversionOption(
            sourceFormat: .heic,
            targetFormat: .jpeg,
            risk: .medium,
            warning: "JPEG uses lossy compression. HDR range and some HEIC metadata may be reduced. For a multi-image HEIF/HEICS file, only its primary image is converted."
        ),
        ConversionOption(
            sourceFormat: .heic,
            targetFormat: .png,
            risk: .low,
            warning: "Some HEIC-specific metadata and HDR information may not be preserved. For a multi-image HEIF/HEICS file, only its primary image is converted."
        ),
        ConversionOption(
            sourceFormat: .jpeg,
            targetFormat: .png,
            risk: .low,
            warning: "Pixel data is preserved, but some JPEG-specific metadata may not be copied."
        ),
        ConversionOption(
            sourceFormat: .jpeg,
            targetFormat: .heic,
            risk: .medium,
            warning: "This re-encodes an already compressed image and may introduce additional quality loss."
        ),
        ConversionOption(
            sourceFormat: .png,
            targetFormat: .jpeg,
            risk: .medium,
            warning: "JPEG does not support transparency. Transparent pixels will be placed on a white background."
        )
    ]

    static let nativeVideoOptions: [ConversionOption] = [
        ConversionOption(
            sourceFormat: .mov,
            targetFormat: .mp4,
            risk: .low,
            warning: "This changes the video container without re-encoding. It is available only when the existing video and audio codecs are compatible with MP4."
        ),
        ConversionOption(
            sourceFormat: .mp4,
            targetFormat: .mov,
            risk: .low,
            warning: "This changes the video container without re-encoding. It is available only when the existing video and audio codecs are compatible with MOV."
        )
    ]

    static let nativePDFOptions: [ConversionOption] = [
        ConversionOption(
            sourceFormat: .pdf,
            targetFormat: .png,
            risk: .medium,
            warning: "Every PDF page will be rasterized at 144 DPI. Text, vectors, links, forms, and annotations will no longer be editable. A multi-page PDF creates one PNG per page."
        ),
        ConversionOption(
            sourceFormat: .pdf,
            targetFormat: .jpeg,
            risk: .high,
            warning: "Every PDF page will be rasterized as a lossy JPEG at 144 DPI. Text, vectors, links, forms, and annotations will no longer be editable. A multi-page PDF creates one JPEG per page."
        ),
        ConversionOption(
            sourceFormat: .jpeg,
            targetFormat: .pdf,
            risk: .low,
            warning: "The image will remain raster content inside a one-page PDF; this does not create editable or searchable text."
        ),
        ConversionOption(
            sourceFormat: .png,
            targetFormat: .pdf,
            risk: .low,
            warning: "The image will remain raster content inside a one-page PDF. Transparent areas will appear on a white page."
        ),
        ConversionOption(
            sourceFormat: .heic,
            targetFormat: .pdf,
            risk: .medium,
            warning: "The image will remain raster content inside a one-page PDF. HDR and HEIC metadata may be reduced; multi-image HEIF/HEICS uses only its primary image."
        )
    ]

    static func options(
        from sourceFormat: FileFormat,
        availableDestinationTypes: Set<String>
    ) -> [ConversionOption] {
        nativeImageOptions
            .filter {
                $0.sourceFormat == sourceFormat
                    && availableDestinationTypes.contains($0.targetFormat.typeIdentifier)
            }
            .sorted { $0.targetFormat.displayName < $1.targetFormat.displayName }
    }

    static func videoOptions(
        from sourceFormat: FileFormat,
        availableDestinationFormats: Set<FileFormat>
    ) -> [ConversionOption] {
        nativeVideoOptions
            .filter {
                $0.sourceFormat == sourceFormat
                    && availableDestinationFormats.contains($0.targetFormat)
            }
            .sorted { $0.targetFormat.displayName < $1.targetFormat.displayName }
    }

    static func pdfOptions(
        from sourceFormat: FileFormat,
        availableImageDestinationTypes: Set<String>
    ) -> [ConversionOption] {
        nativePDFOptions
            .filter { option in
                guard option.sourceFormat == sourceFormat else { return false }
                if option.targetFormat == .pdf { return true }
                return availableImageDestinationTypes.contains(
                    option.targetFormat.typeIdentifier
                )
            }
            .sorted { $0.targetFormat.displayName < $1.targetFormat.displayName }
    }
}
