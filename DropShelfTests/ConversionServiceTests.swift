import CoreGraphics
import ImageIO
import AppKit
@preconcurrency import AVFoundation
import CoreVideo
import Darwin
import XCTest
@testable import DropShelf

final class ConversionServiceTests: XCTestCase {
    private var testDirectory: URL!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropShelfConversionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        testDirectory = nil
    }

    func testEveryAdvertisedConversionProducesItsRealTargetFormat() async throws {
        for sourceFormat in FileFormat.imageFormats {
            let sourceURL = testDirectory.appendingPathComponent(
                "source-\(sourceFormat.rawValue).\(sourceFormat.filenameExtension)"
            )
            try makeImage(at: sourceURL, format: sourceFormat, size: 64)
            let sourceBeforeConversion = try Data(contentsOf: sourceURL)

            let options = await ConversionService.shared
                .supportedOutputFormats(for: sourceURL)
            XCTAssertFalse(options.isEmpty, "Expected options for \(sourceFormat)")

            for option in options {
                let outputURL = try await ConversionService.shared.convert(
                    sourceURL,
                    to: option.targetFormat,
                    destinationDirectory: testDirectory
                )

                XCTAssertNotEqual(outputURL, sourceURL)
                XCTAssertEqual(outputURL.pathExtension, option.targetFormat.filenameExtension)
                XCTAssertEqual(try detectedFormat(at: outputURL), option.targetFormat)
                XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBeforeConversion)
            }
        }
    }

    func testHEIFFamilyIdentifiersAreDetectedAsHEIC() {
        XCTAssertEqual(FileFormat.detect(imageIOTypeIdentifier: "public.heif"), .heic)
        XCTAssertEqual(FileFormat.detect(imageIOTypeIdentifier: "public.heic"), .heic)
        XCTAssertEqual(FileFormat.detect(imageIOTypeIdentifier: "public.heics"), .heic)
    }

    func testMultiImageHEIFContainerConvertsItsPrimaryImage() async throws {
        let heicsIdentifier = "public.heics"
        let destinationTypes = Set(
            (CGImageDestinationCopyTypeIdentifiers() as NSArray)
                .compactMap { $0 as? String }
        )
        guard destinationTypes.contains(heicsIdentifier) else {
            throw XCTSkip("This macOS ImageIO runtime cannot encode HEICS test data.")
        }

        let sourceURL = testDirectory.appendingPathComponent("multi-image.heic")
        guard let destination = CGImageDestinationCreateWithURL(
            sourceURL as CFURL,
            heicsIdentifier as CFString,
            2,
            nil
        ) else {
            throw XCTSkip("ImageIO could not create a HEICS test destination.")
        }

        CGImageDestinationAddImage(destination, try makeCGImage(size: 48, red: 0.9), nil)
        CGImageDestinationAddImage(destination, try makeCGImage(size: 48, red: 0.2), nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("ImageIO could not finalize HEICS test data.")
        }

        let imageSource = try XCTUnwrap(
            CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
        )
        XCTAssertGreaterThan(CGImageSourceGetCount(imageSource), 1)

        let options = await ConversionService.shared
            .supportedOutputFormats(for: sourceURL)
        XCTAssertEqual(Set(options.map(\.targetFormat)), [.jpeg, .png, .pdf])

        let outputURL = try await ConversionService.shared.convert(
            sourceURL,
            to: .png,
            destinationDirectory: testDirectory
        )
        XCTAssertEqual(try detectedFormat(at: outputURL), .png)
    }

    func testMOVAndMP4AreRemuxedWithoutChangingTheSource() async throws {
        let sourceURL = testDirectory.appendingPathComponent("sample.mov")
        try await makeVideo(at: sourceURL, fileType: .mov)
        let sourceData = try Data(contentsOf: sourceURL)

        let movOptions = await ConversionService.shared
            .supportedOutputFormats(for: sourceURL)
        guard movOptions.contains(where: { $0.targetFormat == .mp4 }) else {
            throw XCTSkip("AVFoundation cannot remux the generated H.264 MOV to MP4 here.")
        }

        let mp4URL = try await ConversionService.shared.convert(
            sourceURL,
            to: .mp4,
            destinationDirectory: testDirectory
        )
        XCTAssertEqual(try VideoContainerDetector.detect(at: mp4URL), .mp4)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)

        let mp4Options = await ConversionService.shared
            .supportedOutputFormats(for: mp4URL)
        guard mp4Options.contains(where: { $0.targetFormat == .mov }) else {
            throw XCTSkip("AVFoundation cannot remux the generated MP4 back to MOV here.")
        }

        let movURL = try await ConversionService.shared.convert(
            mp4URL,
            to: .mov,
            destinationDirectory: testDirectory
        )
        XCTAssertEqual(try VideoContainerDetector.detect(at: movURL), .mov)
    }

    func testProResMOVIsReencodedToMP4WhenPassthroughCannotWork() async throws {
        let sourceURL = testDirectory.appendingPathComponent("prores.mov")
        try await makeVideo(at: sourceURL, fileType: .mov, codec: .proRes422)
        let sourceData = try Data(contentsOf: sourceURL)

        let options = await ConversionService.shared.supportedOutputFormats(for: sourceURL)
        let mp4Option = try XCTUnwrap(options.first { $0.targetFormat == .mp4 })
        XCTAssertEqual(mp4Option.risk, .medium)

        let mp4URL = try await ConversionService.shared.convert(
            sourceURL,
            to: .mp4,
            destinationDirectory: testDirectory
        )
        XCTAssertEqual(try VideoContainerDetector.detect(at: mp4URL), .mp4)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)

        let tracks = try await AVURLAsset(url: mp4URL).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        let codec = try XCTUnwrap(formats.first).mediaSubType
        XCTAssertNotEqual(codec, .proRes422)
    }

    func testStillWebPConvertsToJPEGPNGAndPDFAndKeepsAlphaInPNG() async throws {
        let sourceURL = testDirectory.appendingPathComponent("still.webp")
        try Self.stillWebPWithAlpha.write(to: sourceURL)

        let options = await ConversionService.shared.supportedOutputFormats(for: sourceURL)
        XCTAssertEqual(Set(options.map(\.targetFormat)), [.jpeg, .png, .pdf])

        let pngURL = try await ConversionService.shared.convert(
            sourceURL,
            to: .png,
            destinationDirectory: testDirectory
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(pngURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertFalse([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
    }

    func testAnimatedWebPExposesNoConversionOptions() async throws {
        let sourceURL = testDirectory.appendingPathComponent("animated.webp")
        try Self.animatedWebP.write(to: sourceURL)

        let options = await ConversionService.shared.supportedOutputFormats(for: sourceURL)
        XCTAssertTrue(options.isEmpty)
    }

    func testEveryAudioSourceConvertsToItsAdvertisedTargets() async throws {
        let expected: [FileFormat: Set<FileFormat>] = [
            .wav: [.m4a], .aiff: [.m4a, .wav], .flac: [.m4a, .wav],
            .mp3: [.m4a, .wav], .m4a: [.wav]
        ]
        for sourceFormat in FileFormat.audioFormats {
            // Content detection, not the extension, must identify the source.
            let sourceURL = testDirectory.appendingPathComponent("tone-\(sourceFormat.rawValue).bin")
            try makeAudio(at: sourceURL, format: sourceFormat)
            let sourceData = try Data(contentsOf: sourceURL)

            let options = await ConversionService.shared.supportedOutputFormats(for: sourceURL)
            XCTAssertEqual(Set(options.map(\.targetFormat)), expected[sourceFormat], "\(sourceFormat)")
            XCTAssertTrue(options.allSatisfy { $0.sourceFormat == sourceFormat })

            for option in options {
                let outputURL = try await ConversionService.shared.convert(
                    sourceURL,
                    to: option.targetFormat,
                    destinationDirectory: testDirectory
                )
                XCTAssertEqual(outputURL.pathExtension, option.targetFormat.filenameExtension)
                let outputOptions = await ConversionService.shared.supportedOutputFormats(for: outputURL)
                XCTAssertEqual(outputOptions.first?.sourceFormat, option.targetFormat)
                XCTAssertGreaterThan(try AVAudioFile(forReading: outputURL).length, 0)
            }
            XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        }
    }

    func testSurroundAudioDoesNotOfferAAC() async throws {
        let sourceURL = testDirectory.appendingPathComponent("surround.aiff")
        try makeAudio(at: sourceURL, format: .aiff, channels: 6)

        let options = await ConversionService.shared.supportedOutputFormats(for: sourceURL)
        XCTAssertEqual(options.map(\.targetFormat), [.wav])
    }

    func testMP4VideoOffersNoAudioConversion() async throws {
        let sourceURL = testDirectory.appendingPathComponent("video.mp4")
        try await makeVideo(at: sourceURL, fileType: .mp4)

        let options = await ConversionService.shared.supportedOutputFormats(for: sourceURL)
        XCTAssertTrue(options.allSatisfy { $0.targetFormat.mediaKind == .video })
    }

    func testFakeVideoContainerExposesNoConversionOptions() async throws {
        let fakeVideo = testDirectory.appendingPathComponent("fake.mp4")
        try Data("not a video".utf8).write(to: fakeVideo)

        let options = await ConversionService.shared
            .supportedOutputFormats(for: fakeVideo)
        XCTAssertTrue(options.isEmpty)
    }

    func testMultiPagePDFCreatesOneRealPNGPerPage() async throws {
        let sourceURL = testDirectory.appendingPathComponent("report.pdf")
        try makePDF(
            at: sourceURL,
            pageSizes: [
                CGSize(width: 200, height: 100),
                CGSize(width: 100, height: 200)
            ]
        )
        let sourceData = try Data(contentsOf: sourceURL)

        let options = await ConversionService.shared
            .supportedOutputFormats(for: sourceURL)
        XCTAssertEqual(Set(options.map(\.targetFormat)), [.jpeg, .png])

        let outputURLs = try await ConversionService.shared.convertAll(
            sourceURL,
            to: .png,
            destinationDirectory: testDirectory
        )

        XCTAssertEqual(outputURLs.map(\.lastPathComponent), [
            "report - Page 1.png",
            "report - Page 2.png"
        ])
        XCTAssertEqual(outputURLs.count, 2)
        XCTAssertEqual(try imagePixelSize(at: outputURLs[0]), CGSize(width: 400, height: 200))
        XCTAssertEqual(try imagePixelSize(at: outputURLs[1]), CGSize(width: 200, height: 400))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testPDFToJPEGProducesJPEGForEveryPage() async throws {
        let sourceURL = testDirectory.appendingPathComponent("slides.pdf")
        try makePDF(
            at: sourceURL,
            pageSizes: [
                CGSize(width: 160, height: 90),
                CGSize(width: 160, height: 90),
                CGSize(width: 160, height: 90)
            ]
        )

        let outputURLs = try await ConversionService.shared.convertAll(
            sourceURL,
            to: .jpeg,
            destinationDirectory: testDirectory
        )

        XCTAssertEqual(outputURLs.count, 3)
        for outputURL in outputURLs {
            XCTAssertEqual(try detectedFormat(at: outputURL), .jpeg)
        }
    }

    func testImageToPDFCreatesAValidOnePageDocument() async throws {
        let imageURL = testDirectory.appendingPathComponent("poster.png")
        try makeImage(at: imageURL, format: .png, size: 120)
        let sourceData = try Data(contentsOf: imageURL)

        let outputURL = try await ConversionService.shared.convert(
            imageURL,
            to: .pdf,
            destinationDirectory: testDirectory
        )

        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertEqual(try Data(contentsOf: imageURL), sourceData)
    }

    func testPDFPageFilenameCollisionsDoNotOverwriteExistingFiles() async throws {
        let sourceURL = testDirectory.appendingPathComponent("manual.pdf")
        let existingURL = testDirectory.appendingPathComponent("manual - Page 1.png")
        try makePDF(
            at: sourceURL,
            pageSizes: [CGSize(width: 100, height: 100), CGSize(width: 100, height: 100)]
        )
        try Data("keep me".utf8).write(to: existingURL)

        let outputURLs = try await ConversionService.shared.convertAll(
            sourceURL,
            to: .png,
            destinationDirectory: testDirectory
        )

        XCTAssertEqual(outputURLs.map(\.lastPathComponent), [
            "manual 2 - Page 1.png",
            "manual 2 - Page 2.png"
        ])
        XCTAssertEqual(try Data(contentsOf: existingURL), Data("keep me".utf8))
    }

    func testCorruptedPDFExposesNoOptions() async throws {
        let sourceURL = testDirectory.appendingPathComponent("broken.pdf")
        try Data("%PDF-1.7\nnot a valid document".utf8).write(to: sourceURL)

        let options = await ConversionService.shared
            .supportedOutputFormats(for: sourceURL)
        XCTAssertTrue(options.isEmpty)
    }

    func testContentDetectionWorksWithoutAnExtension() async throws {
        let sourceURL = testDirectory.appendingPathComponent("extensionless-image")
        try makeImage(at: sourceURL, format: .png, size: 32)

        let options = await ConversionService.shared
            .supportedOutputFormats(for: sourceURL)

        XCTAssertEqual(options.map(\.targetFormat), [.jpeg, .pdf])
    }

    func testUppercaseExtensionDoesNotAffectDetection() async throws {
        let sourceURL = testDirectory.appendingPathComponent("PHOTO.PNG")
        try makeImage(at: sourceURL, format: .png, size: 32)

        let options = await ConversionService.shared
            .supportedOutputFormats(for: sourceURL)

        XCTAssertEqual(options.map(\.targetFormat), [.jpeg, .pdf])
    }

    func testFilenameCollisionsNeverOverwriteExistingFiles() async throws {
        let sourceURL = testDirectory.appendingPathComponent("photo.png")
        let existingURL = testDirectory.appendingPathComponent("photo.jpg")
        try makeImage(at: sourceURL, format: .png, size: 32)
        try Data("keep me".utf8).write(to: existingURL)

        let firstOutput = try await ConversionService.shared.convert(
            sourceURL,
            to: .jpeg,
            destinationDirectory: testDirectory
        )
        let secondOutput = try await ConversionService.shared.convert(
            sourceURL,
            to: .jpeg,
            destinationDirectory: testDirectory
        )

        XCTAssertEqual(firstOutput.lastPathComponent, "photo 2.jpg")
        XCTAssertEqual(secondOutput.lastPathComponent, "photo 3.jpg")
        XCTAssertEqual(try Data(contentsOf: existingURL), Data("keep me".utf8))
    }

    func testUnsupportedAndCorruptedFilesExposeNoOptions() async throws {
        let textURL = testDirectory.appendingPathComponent("notes.txt")
        let corruptedURL = testDirectory.appendingPathComponent("broken.png")
        try Data("plain text".utf8).write(to: textURL)
        try Data("not a PNG".utf8).write(to: corruptedURL)

        let textOptions = await ConversionService.shared
            .supportedOutputFormats(for: textURL)
        let corruptedOptions = await ConversionService.shared
            .supportedOutputFormats(for: corruptedURL)

        XCTAssertTrue(textOptions.isEmpty)
        XCTAssertTrue(corruptedOptions.isEmpty)

        do {
            _ = try await ConversionService.shared.convert(
                corruptedURL,
                to: .jpeg,
                destinationDirectory: testDirectory
            )
            XCTFail("Corrupted input should fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testMissingSourceAndInvalidDestinationFailCleanly() async throws {
        let missingURL = testDirectory.appendingPathComponent("missing.png")
        let sourceURL = testDirectory.appendingPathComponent("source.png")
        let nonDirectoryURL = testDirectory.appendingPathComponent("not-a-folder")
        try makeImage(at: sourceURL, format: .png, size: 32)
        try Data().write(to: nonDirectoryURL)

        do {
            _ = try await ConversionService.shared.convert(
                missingURL,
                to: .jpeg,
                destinationDirectory: testDirectory
            )
            XCTFail("Missing source should fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        do {
            _ = try await ConversionService.shared.convert(
                sourceURL,
                to: .jpeg,
                destinationDirectory: nonDirectoryURL
            )
            XCTFail("A file cannot be used as a destination folder")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testUnwritableDestinationFailsWithoutChangingSource() async throws {
        let sourceURL = testDirectory.appendingPathComponent("protected-source.png")
        let readOnlyDirectory = testDirectory.appendingPathComponent("ReadOnly")
        try makeImage(at: sourceURL, format: .png, size: 32)
        let originalData = try Data(contentsOf: sourceURL)
        try FileManager.default.createDirectory(
            at: readOnlyDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: readOnlyDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: readOnlyDirectory.path
            )
        }

        do {
            _ = try await ConversionService.shared.convert(
                sourceURL,
                to: .jpeg,
                destinationDirectory: readOnlyDirectory
            )
            XCTFail("An unwritable destination should fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
    }

    func testLargeImageConversionRunsAsynchronously() async throws {
        let sourceURL = testDirectory.appendingPathComponent("large.png")
        try makeImage(at: sourceURL, format: .png, size: 2_048)

        let outputURL = try await ConversionService.shared.convert(
            sourceURL,
            to: .jpeg,
            destinationDirectory: testDirectory
        )

        XCTAssertEqual(try detectedFormat(at: outputURL), .jpeg)
    }

    func testCancelledConversionDoesNotCreateOutput() async throws {
        let sourceURL = testDirectory.appendingPathComponent("cancelled.png")
        try makeImage(at: sourceURL, format: .png, size: 1_024)

        let task = Task {
            try await ConversionService.shared.convert(
                sourceURL,
                to: .jpeg,
                destinationDirectory: testDirectory
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled conversion should not succeed")
        } catch is CancellationError {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: testDirectory.appendingPathComponent("cancelled.jpg").path
                )
            )
        }
    }

    func testCancelledFolderPickerDoesNotChooseADestination() {
        let proposedURL = URL(fileURLWithPath: "/tmp/should-not-be-used")

        XCTAssertNil(
            ConversionDestinationSelection.resolve(
                response: .cancel,
                selectedURL: proposedURL
            )
        )
        XCTAssertEqual(
            ConversionDestinationSelection.resolve(
                response: .OK,
                selectedURL: proposedURL
            ),
            proposedURL
        )
    }

    @MainActor
    func testBatchOptionsOnlyOfferTargetsEveryFileSupports() async throws {
        let png = testDirectory.appendingPathComponent("batch.png")
        let jpeg = testDirectory.appendingPathComponent("batch.jpg")
        try makeImage(at: png, format: .png, size: 16)
        try makeImage(at: jpeg, format: .jpeg, size: 16)

        let options = await ConversionOptionsCache.commonOptions(for: [png, jpeg])

        XCTAssertEqual(options.map(\.targetFormat), [.pdf])
    }

    /// 16x16 lossless WEBP, top half semi-transparent (made with cwebp).
    private static let stillWebPWithAlpha = Data(base64Encoded:
        "UklGRiYAAABXRUJQVlA4TBoAAAAvD8ADEA8wTFM+mQMY8BALJvlLd04hov8ZJw=="
    )!

    /// Two-frame 16x16 animated WEBP (made with img2webp).
    private static let animatedWebP = Data(base64Encoded:
        "UklGRogAAABXRUJQVlA4WAoAAAASAAAADwAADwAAQU5JTQYAAAD/////AABBTk1GKgAAAAAAAAQAAA8AAAcAAGQAAAJWUDhMEQAAAC8PwAEQB1CmljezgIGI6H8AAEFOTUYqAAAAAAAABAAADwAABwAAZAAAAFZQOEwRAAAALw/AAQAH0KZqNLP/gYjofwAA"
    )!

    /// 0.2 s mono 8 kHz MP3 (made with ffmpeg); macOS has no MP3 encoder.
    private static let tinyMP3 = Data(base64Encoded:
        "SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAxAAAAAAAAAAAAAAD/4zjAAAAAAAAAAAAASW5mbwAAAA8AAAAFAAACQACAgICAgICAgICAgICAgICAgICAoKCgoKCgoKCgoKCgoKCgoKCgoKDAwMDAwMDAwMDAwMDAwMDAwMDAwODg4ODg4ODg4ODg4ODg4ODg4ODg//////////////////////////8AAAAATGF2YzYzLjEuAAAAAAAAAAAAAAAAJALAAAAAAAAAAkDg0tHcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4xjEAAxIkpR5TwAABAkoAve973ve9KUpSlKUve79/ffvEqny3i3ibi5lzVYbEAIBisH3//5T39H+BDnP9ComhzhZxDf8ZUT/4xjECQ7w8pABlFAAKjlCFv8G3g/UD3IAMqIk4B8TAcyOsDvUw98CUAqAqKwihFf/kI9HpEPh8Cv+EgaEoSBqwAAAjMq/////4xjECA64yjmBlxAAgYAMBoAYx+UMAYHMA/QMAKA9wMMCLcwMBzAf4GAcggAGErFxwGASgN03xvj6P90p8cNV///feajM1K7/4xjECA65KqABmTgANf//zOvlEYhDrpfETX/ith9DoofNkaGSCzP/0Y892AcC0ICI2H/8z+cOlGCpX/2BUqwegH9SlKXihQz/4xjECA1gomAZyRgArjGPkiRRpZEi0qCIIkyqFDnihJdQilCAgaPA0HSoKrDX///T///////b1ed5akxBTUU0LjCqqqqqqqo="
    )!

    /// `channels` is 2 (stereo) or 6 (5.1).
    private func makeAudio(at url: URL, format: FileFormat, channels: Int = 2) throws {
        if format == .mp3 {
            try Self.tinyMP3.write(to: url)
            return
        }
        var settings: [String: Any] = [AVSampleRateKey: 44_100, AVNumberOfChannelsKey: channels]
        switch format {
        case .wav, .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = format == .aiff
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        default:
            XCTFail("makeAudio only accepts audio formats")
            return
        }

        // AVAudioFile picks the container from the extension, so write to a
        // properly named file and move it to `url`.
        let namedURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).\(format.filenameExtension)")
        let layout = try XCTUnwrap(AVAudioChannelLayout(
            layoutTag: channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : kAudioChannelLayoutTag_Stereo
        ))
        let pcm = AVAudioFormat(standardFormatWithSampleRate: 44_100, channelLayout: layout)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 8_820))
        buffer.frameLength = 8_820
        for channel in 0..<channels {
            let samples = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<Int(buffer.frameLength) {
                samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100)) * 0.5
            }
        }
        try AVAudioFile(forWriting: namedURL, settings: settings).write(from: buffer)
        try FileManager.default.moveItem(at: namedURL, to: url)
    }

    private func makeImage(at url: URL, format: FileFormat, size: Int) throws {
        guard format.mediaKind == .image else {
            XCTFail("makeImage only accepts image formats")
            return
        }
        // ImageIO has no WEBP encoder, so WEBP sources come from a fixture.
        if format == .webp {
            try Self.stillWebPWithAlpha.write(to: url)
            return
        }

        let image = try makeCGImage(size: size, red: 0.2)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.typeIdentifier as CFString,
            1,
            nil
        ) else {
            XCTFail("Could not create test image destination")
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makeCGImage(size: Int, red: CGFloat) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw TestSupportError.cannotCreateImage
        }

        context.setFillColor(CGColor(red: red, green: 0.5, blue: 0.9, alpha: 0.6))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else {
            throw TestSupportError.cannotCreateImage
        }
        return image
    }

    private func makeVideo(
        at url: URL,
        fileType: AVFileType,
        codec: AVVideoCodecType = .h264
    ) async throws {
        let width = 64
        let height = 64
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else { throw TestSupportError.cannotCreateVideo }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TestSupportError.cannotCreateVideo
        }
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw TestSupportError.cannotCreateVideo
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0x7f, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        guard input.isReadyForMoreMediaData,
              adaptor.append(pixelBuffer, withPresentationTime: .zero) else {
            throw writer.error ?? TestSupportError.cannotCreateVideo
        }
        input.markAsFinished()

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: writer.error ?? TestSupportError.cannotCreateVideo
                    )
                }
            }
        }
    }

    private func makePDF(at url: URL, pageSizes: [CGSize]) throws {
        guard var firstPageBox = pageSizes.first.map({
            CGRect(origin: .zero, size: $0)
        }), let context = CGContext(url as CFURL, mediaBox: &firstPageBox, nil) else {
            throw TestSupportError.cannotCreatePDF
        }

        for (index, pageSize) in pageSizes.enumerated() {
            var pageBox = CGRect(origin: .zero, size: pageSize)
            let mediaBoxData = Data(
                bytes: &pageBox,
                count: MemoryLayout<CGRect>.size
            )
            let pageInfo: [String: Any] = [
                kCGPDFContextMediaBox as String: mediaBoxData
            ]
            context.beginPDFPage(pageInfo as CFDictionary)

            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(pageBox)
            context.setFillColor(
                CGColor(
                    red: index.isMultiple(of: 2) ? 0.9 : 0.1,
                    green: 0.35,
                    blue: index.isMultiple(of: 2) ? 0.15 : 0.85,
                    alpha: 1
                )
            )
            context.fill(
                CGRect(
                    x: pageBox.width * 0.1,
                    y: pageBox.height * 0.1,
                    width: pageBox.width * 0.8,
                    height: pageBox.height * 0.8
                )
            )
            context.endPDFPage()
        }
        context.closePDF()

        guard let document = CGPDFDocument(url as CFURL),
              document.numberOfPages == pageSizes.count else {
            throw TestSupportError.cannotCreatePDF
        }
    }

    private func imagePixelSize(at url: URL) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        )
        let width = try XCTUnwrap(
            (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
        )
        let height = try XCTUnwrap(
            (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        )
        return CGSize(width: width, height: height)
    }

    private func detectedFormat(at url: URL) throws -> FileFormat {
        if let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 {
            return .pdf
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let typeIdentifier = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        return try XCTUnwrap(FileFormat.detect(imageIOTypeIdentifier: typeIdentifier))
    }
}

private enum TestSupportError: Error {
    case cannotCreateImage
    case cannotCreateVideo
    case cannotCreatePDF
}
