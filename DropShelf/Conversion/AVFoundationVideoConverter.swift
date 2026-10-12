@preconcurrency import AVFoundation
import Foundation

struct AVFoundationVideoConverter: Sendable {
    func supportedOptions(for inputURL: URL) async -> [ConversionOption] {
        do {
            let inspection = try await inspect(inputURL)
            var options: [ConversionOption] = []

            for option in ConversionCapabilityMatrix.nativeVideoOptions
            where option.sourceFormat == inspection.format {
                try Task.checkCancellation()
                guard let fileType = option.targetFormat.avFileType else { continue }
                switch await Self.exportPreset(for: inspection.asset, outputFileType: fileType) {
                case AVAssetExportPresetPassthrough?:
                    options.append(option)
                case .some:
                    options.append(ConversionCapabilityMatrix.videoTranscodeOption(
                        from: option.sourceFormat,
                        to: option.targetFormat
                    ))
                case nil:
                    continue
                }
            }

            return options.sorted { $0.targetFormat.displayName < $1.targetFormat.displayName }
        } catch {
            return []
        }
    }

    /// Passthrough when the existing codecs fit the target container,
    /// otherwise a full re-encode. `supportedFileTypes` is not enough here:
    /// it lists MP4 for ProRes MOV even though passthrough export then fails.
    private static func exportPreset(
        for asset: AVAsset,
        outputFileType: AVFileType
    ) async -> String? {
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            if await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: outputFileType
            ) {
                return preset
            }
        }
        return nil
    }

    func convert(
        inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) async throws -> URL {
        try Task.checkCancellation()

        guard let targetFileType = targetFormat.avFileType else {
            throw ConversionError.unsupportedVideoTarget
        }

        let inspection = try await inspect(inputURL)
        guard ConversionCapabilityMatrix.nativeVideoOptions.contains(where: {
                  $0.sourceFormat == inspection.format && $0.targetFormat == targetFormat
              }),
              let preset = await Self.exportPreset(
                for: inspection.asset,
                outputFileType: targetFileType
              ) else {
            throw ConversionError.unsupportedConversion(
                source: inspection.format,
                target: targetFormat
            )
        }
        guard let session = AVAssetExportSession(
            asset: inspection.asset,
            presetName: preset
        ) else {
            throw ConversionError.cannotCreateVideoExportSession
        }

        let destinationValues = try destinationDirectory.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        guard destinationValues.isDirectory == true else {
            throw ConversionError.destinationIsNotDirectory
        }

        let temporaryURL = destinationDirectory.appendingPathComponent(
            ".DropShelf-Conversion-\(UUID().uuidString).\(targetFormat.filenameExtension)"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        session.outputURL = temporaryURL
        session.outputFileType = targetFileType
        session.shouldOptimizeForNetworkUse = true

        try await export(session)
        try Task.checkCancellation()

        return try moveConvertedFile(
            temporaryURL: temporaryURL,
            inputURL: inputURL,
            targetFormat: targetFormat,
            destinationDirectory: destinationDirectory
        )
    }

    private func inspect(
        _ inputURL: URL
    ) async throws -> (format: FileFormat, asset: AVURLAsset) {
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

        let format = try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try VideoContainerDetector.detect(at: inputURL)
        }.value
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw ConversionError.unsupportedVideoSource
        }

        return (format, asset)
    }

    private func export(_ session: AVAssetExportSession) async throws {
        let sessionBox = ExportSessionBox(session)

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                sessionBox.session.exportAsynchronously {
                    switch sessionBox.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(
                            throwing: ConversionError.videoExportFailed(
                                sessionBox.session.error?.localizedDescription
                                    ?? String(localized: "The video codec is not compatible with the selected container.")
                            )
                        )
                    case .unknown, .waiting, .exporting:
                        continuation.resume(
                            throwing: ConversionError.videoExportFailed(
                                String(localized: "macOS ended the export without producing a video.")
                            )
                        )
                    @unknown default:
                        continuation.resume(
                            throwing: ConversionError.videoExportFailed(
                                String(localized: "macOS returned an unknown video export status.")
                            )
                        )
                    }
                }
            }
        } onCancel: {
            sessionBox.session.cancelExport()
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum VideoContainerDetector {
    private static let quickTimeBrand = "qt  "
    private static let mp4Brands: Set<String> = [
        "isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9",
        "mp41", "mp42", "avc1", "dash", "MSNV", "NDAS", "M4V ", "F4V "
    ]

    static func detect(at url: URL) throws -> FileFormat {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ConversionError.sourceUnreadable
        }
        defer { try? handle.close() }

        let data = try handle.read(upToCount: 64 * 1_024) ?? Data()
        var offset = 0

        while offset + 8 <= data.count {
            let atomSize = Int(readUInt32(in: data, at: offset))
            let atomType = asciiString(in: data, range: (offset + 4)..<(offset + 8))

            if atomType == "ftyp" {
                let availableEnd = atomSize >= 8
                    ? min(data.count, offset + atomSize)
                    : data.count
                guard offset + 12 <= availableEnd else {
                    throw ConversionError.unsupportedVideoSource
                }

                var brands = [asciiString(
                    in: data,
                    range: (offset + 8)..<(offset + 12)
                )]
                var brandOffset = offset + 16
                while brandOffset + 4 <= availableEnd {
                    brands.append(
                        asciiString(in: data, range: brandOffset..<(brandOffset + 4))
                    )
                    brandOffset += 4
                }

                if brands.contains(quickTimeBrand) { return .mov }
                if brands.contains(where: mp4Brands.contains) { return .mp4 }
                throw ConversionError.unsupportedVideoSource
            }

            guard atomSize >= 8, offset + atomSize <= data.count else { break }
            offset += atomSize
        }

        throw ConversionError.unsupportedVideoSource
    }

    private static func readUInt32(in data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func asciiString(in data: Data, range: Range<Int>) -> String {
        String(bytes: data[range], encoding: .ascii) ?? ""
    }
}

private extension FileFormat {
    var avFileType: AVFileType? {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        case .jpeg, .png, .heic, .webp, .pdf, .wav, .aiff, .mp3, .flac, .m4a: return nil
        }
    }

    init?(avFileType: AVFileType) {
        switch avFileType {
        case .mov: self = .mov
        case .mp4: self = .mp4
        default: return nil
        }
    }
}
