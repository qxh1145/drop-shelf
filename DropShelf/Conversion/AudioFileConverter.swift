@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

struct AudioFileConverter: Sendable {
    func supportedOptions(for inputURL: URL) async -> [ConversionOption] {
        guard let inspection = try? await inspect(inputURL) else { return [] }
        return ConversionCapabilityMatrix.nativeAudioOptions
            .filter { option in
                guard option.sourceFormat == inspection.format else { return false }
                // CoreAudio's AAC encoder rejects more than two channels.
                return option.targetFormat != .m4a || inspection.channelCount <= 2
            }
            .sorted { $0.targetFormat.displayName < $1.targetFormat.displayName }
    }

    func convert(
        inputURL: URL,
        to targetFormat: FileFormat,
        destinationDirectory: URL
    ) async throws -> URL {
        try Task.checkCancellation()

        let inspection = try await inspect(inputURL)
        guard await supportedOptions(for: inputURL).contains(where: {
            $0.targetFormat == targetFormat
        }) else {
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

        let worker = Task.detached(priority: .userInitiated) {
            let temporaryURL = destinationDirectory.appendingPathComponent(
                ".DropShelf-Conversion-\(UUID().uuidString).\(targetFormat.filenameExtension)"
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            try Self.transcode(
                inputURL: inputURL,
                sourceFormat: inspection.format,
                to: targetFormat,
                outputURL: temporaryURL
            )
            try Task.checkCancellation()

            return try moveConvertedFile(
                temporaryURL: temporaryURL,
                inputURL: inputURL,
                targetFormat: targetFormat,
                destinationDirectory: destinationDirectory
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func transcode(
        inputURL: URL,
        sourceFormat: FileFormat,
        to targetFormat: FileFormat,
        outputURL: URL
    ) throws {
        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: inputURL)
        } catch {
            throw ConversionError.corruptedOrUnreadableSource
        }
        let format = input.processingFormat

        var settings: [String: Any] = [
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        switch targetFormat {
        case .m4a:
            // VBR at max quality (~200–256 kbps for stereo 44.1 kHz). A fixed
            // bit rate fails when it exceeds what low sample rates allow.
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_Variable
            settings[AVEncoderAudioQualityForVBRKey] = AVAudioQuality.max.rawValue
        case .wav:
            // ponytail: 16-bit for lossy sources, 24-bit otherwise; 32-bit
            // float sources lose precision below audibility.
            let isLossySource = sourceFormat == .mp3
                || (sourceFormat == .m4a
                    && input.fileFormat.settings[AVFormatIDKey] as? AudioFormatID
                        != kAudioFormatAppleLossless)
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = isLossySource ? 16 : 24
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        default:
            throw ConversionError.unsupportedConversion(source: sourceFormat, target: targetFormat)
        }

        do {
            let output = try AVAudioFile(
                forWriting: outputURL,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
                throw ConversionError.cannotCreateOutput
            }
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.audioEncodingFailed(error.localizedDescription)
        }
    }

    private func inspect(
        _ inputURL: URL
    ) async throws -> (format: FileFormat, channelCount: AVAudioChannelCount) {
        let values: URLResourceValues
        do {
            values = try inputURL.resourceValues(
                forKeys: [.isRegularFileKey, .isReadableKey]
            )
        } catch {
            throw ConversionError.sourceMissing
        }
        guard values.isRegularFile == true else { throw ConversionError.sourceMissing }
        guard values.isReadable != false else { throw ConversionError.sourceUnreadable }

        guard let format = Self.detectContainer(inputURL) else {
            throw ConversionError.unsupportedSource
        }
        // An MPEG-4 container can hold video; that belongs to the video
        // converter. The MIME override lets AVFoundation parse files whose
        // extension is missing or wrong; on macOS 13 such files are rejected.
        if format == .m4a {
            let asset: AVURLAsset
            if #available(macOS 14.0, *) {
                asset = AVURLAsset(
                    url: inputURL,
                    options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"]
                )
            } else {
                asset = AVURLAsset(url: inputURL)
            }
            let tracks = try await asset.load(.tracks)
            guard !tracks.contains(where: { $0.mediaType == .video }) else {
                throw ConversionError.unsupportedSource
            }
        }
        guard let file = try? AVAudioFile(forReading: inputURL),
              file.length > 0 else {
            throw ConversionError.unsupportedSource
        }
        return (format, file.processingFormat.channelCount)
    }

    /// Container type from the file's contents, not its extension.
    private static func detectContainer(_ url: URL) -> FileFormat? {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr,
              let fileID else {
            return nil
        }
        defer { AudioFileClose(fileID) }

        var type: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(fileID, kAudioFilePropertyFileFormat, &size, &type) == noErr else {
            return nil
        }
        switch type {
        case kAudioFileWAVEType, kAudioFileRF64Type, kAudioFileBW64Type: return .wav
        case kAudioFileAIFFType, kAudioFileAIFCType: return .aiff
        case kAudioFileMP3Type: return .mp3
        case kAudioFileFLACType: return .flac
        case kAudioFileM4AType, kAudioFileMPEG4Type: return .m4a
        default: return nil
        }
    }
}
