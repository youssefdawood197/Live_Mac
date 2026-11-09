import Foundation
import AVFoundation
import AppKit

// MARK: - Validation Errors & Models

/// Errors encountered during asset validation and inspection.
public enum AssetValidationError: LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case unreadableFile(URL)
    case fileIsEmpty(URL)
    case unsupportedFormat(String)
    case missingVideoTrack
    case unplayableMedia
    case invalidDuration(Double)
    case notADirectory(URL)
    case missingIndexHTML(URL)
    case emptyIndexHTML(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File or directory not found at: \(url.path)"
        case .unreadableFile(let url):
            return "File is not readable at: \(url.path)"
        case .fileIsEmpty(let url):
            return "File is empty (0 bytes) at: \(url.path)"
        case .unsupportedFormat(let ext):
            return "Unsupported media format: .\(ext)"
        case .missingVideoTrack:
            return "Media file does not contain any enabled video tracks"
        case .unplayableMedia:
            return "Media asset is not playable by AVFoundation"
        case .invalidDuration(let dur):
            return "Media duration is invalid or zero: \(dur) seconds"
        case .notADirectory(let url):
            return "Expected a directory at: \(url.path)"
        case .missingIndexHTML(let url):
            return "Directory is missing index.html at: \(url.path)"
        case .emptyIndexHTML(let url):
            return "index.html is empty (0 bytes) at: \(url.path)"
        }
    }
}

/// Metadata extracted from a verified video file.
public struct VideoMetadata: Sendable, Equatable {
    public let url: URL
    public let durationSeconds: Double
    public let naturalSize: CGSize
    public let frameRate: Float
    public let fileSize: Int64
    public let codec: String
}

/// Metadata extracted from a verified web wallpaper directory.
public struct WebMetadata: Sendable, Equatable {
    public let directoryURL: URL
    public let entryPointURL: URL
    public let title: String?
    public let totalSizeBytes: Int64
}

// MARK: - AssetManager

/// Coordinates wallpaper storage, first-launch sample provisioning, media validation, and discovery.
public final class AssetManager: @unchecked Sendable {

    public let baseStorageDirectory: URL
    private let fileManager: FileManager
    private let resourceBundle: Bundle?
    private let generator: SampleAssetGenerator

    public init(
        baseStorageDirectory: URL? = nil,
        resourceBundle: Bundle? = nil,
        fileManager: FileManager = .default,
        generator: SampleAssetGenerator = SampleAssetGenerator()
    ) {
        self.fileManager = fileManager
        self.resourceBundle = resourceBundle
        self.generator = generator

        if let baseStorageDirectory = baseStorageDirectory {
            self.baseStorageDirectory = baseStorageDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseStorageDirectory = appSupport.appendingPathComponent("LivelyWallpaper/Wallpapers", isDirectory: true)
        }
    }

    public var wallpapersDirectory: URL {
        return baseStorageDirectory
    }

    // MARK: - First Launch Setup & Sample Extraction

    /// Ensures default sample wallpapers (video and canvas) exist in the storage directory.
    /// Extracts from bundle if available, or generates them on-the-fly.
    @discardableResult
    public func ensureDefaultSamplesExtracted() async throws -> (sampleVideoURL: URL, sampleCanvasURL: URL) {
        if !fileManager.fileExists(atPath: baseStorageDirectory.path) {
            try fileManager.createDirectory(at: baseStorageDirectory, withIntermediateDirectories: true)
        }

        let targetVideoURL = baseStorageDirectory.appendingPathComponent(SampleAssetGenerator.defaultVideoFileName)
        let targetCanvasDirURL = baseStorageDirectory.appendingPathComponent(SampleAssetGenerator.defaultCanvasDirectoryName, isDirectory: true)

        // 1. Video extraction / generation
        if !fileManager.fileExists(atPath: targetVideoURL.path) {
            var extractedFromBundle = false
            if let bundle = resourceBundle,
               let bundledVideoURL = bundle.url(forResource: "sample_loop", withExtension: "mp4", subdirectory: "Samples") ??
                                    bundle.url(forResource: "sample_loop", withExtension: "mp4") {
                try fileManager.copyItem(at: bundledVideoURL, to: targetVideoURL)
                extractedFromBundle = true
            }

            if !extractedFromBundle {
                try await generator.generateSampleVideo(at: targetVideoURL)
            }
        }

        // 2. Canvas extraction / generation
        if !fileManager.fileExists(atPath: targetCanvasDirURL.path) {
            var extractedFromBundle = false
            if let bundle = resourceBundle,
               let bundledCanvasDir = bundle.url(forResource: "sample_canvas", withExtension: nil, subdirectory: "Samples") ??
                                     bundle.url(forResource: "sample_canvas", withExtension: nil) {
                try fileManager.copyItem(at: bundledCanvasDir, to: targetCanvasDirURL)
                extractedFromBundle = true
            }

            if !extractedFromBundle {
                try generator.generateSampleCanvas(at: targetCanvasDirURL)
            }
        }

        return (targetVideoURL, targetCanvasDirURL)
    }

    // MARK: - Validation

    /// Validates an MP4/MOV video file for playable tracks and dimensions.
    public func validateVideo(at url: URL) async throws -> VideoMetadata {
        guard fileManager.fileExists(atPath: url.path) else {
            throw AssetValidationError.fileNotFound(url)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw AssetValidationError.unreadableFile(url)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            throw AssetValidationError.fileIsEmpty(url)
        }

        let ext = url.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else {
            throw AssetValidationError.unsupportedFormat(ext)
        }

        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw AssetValidationError.unplayableMedia
        }

        let durationCMTime = try await asset.load(.duration)
        let durationSeconds = durationCMTime.seconds
        guard durationSeconds > 0 && !durationSeconds.isNaN && !durationSeconds.isInfinite else {
            throw AssetValidationError.invalidDuration(durationSeconds)
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let primaryTrack = tracks.first else {
            throw AssetValidationError.missingVideoTrack
        }

        let naturalSize = try await primaryTrack.load(.naturalSize)
        let frameRate = try await primaryTrack.load(.nominalFrameRate)

        var codecName = "H.264"
        let formatDescriptions = try await primaryTrack.load(.formatDescriptions)
        if let firstFormat = formatDescriptions.first {
            let mediaSubtype = CMFormatDescriptionGetMediaSubType(firstFormat)
            let fourCC = String(
                bytes: [
                    UInt8((mediaSubtype >> 24) & 0xff),
                    UInt8((mediaSubtype >> 16) & 0xff),
                    UInt8((mediaSubtype >> 8) & 0xff),
                    UInt8(mediaSubtype & 0xff)
                ],
                encoding: .ascii
            ) ?? "avc1"
            codecName = fourCC
        }

        return VideoMetadata(
            url: url,
            durationSeconds: durationSeconds,
            naturalSize: naturalSize,
            frameRate: frameRate,
            fileSize: fileSize,
            codec: codecName
        )
    }

    /// Validates an HTML5 directory containing index.html.
    public func validateWebDirectory(at url: URL) throws -> WebMetadata {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw AssetValidationError.fileNotFound(url)
        }

        var entryPointURL: URL
        var directoryURL: URL

        if isDir.boolValue {
            directoryURL = url
            entryPointURL = url.appendingPathComponent("index.html")
        } else {
            guard url.pathExtension.lowercased() == "html" else {
                throw AssetValidationError.notADirectory(url)
            }
            directoryURL = url.deletingLastPathComponent()
            entryPointURL = url
        }

        guard fileManager.fileExists(atPath: entryPointURL.path) else {
            throw AssetValidationError.missingIndexHTML(directoryURL)
        }

        guard fileManager.isReadableFile(atPath: entryPointURL.path) else {
            throw AssetValidationError.unreadableFile(entryPointURL)
        }

        let attributes = try fileManager.attributesOfItem(atPath: entryPointURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            throw AssetValidationError.emptyIndexHTML(entryPointURL)
        }

        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        var title: String? = nil
        if let htmlContent = try? String(contentsOf: entryPointURL, encoding: .utf8) {
            if let titleStart = htmlContent.range(of: "<title>", options: .caseInsensitive),
               let titleEnd = htmlContent.range(of: "</title>", options: .caseInsensitive),
               titleStart.upperBound < titleEnd.lowerBound {
                title = String(htmlContent[titleStart.upperBound..<titleEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return WebMetadata(
            directoryURL: directoryURL,
            entryPointURL: entryPointURL,
            title: title,
            totalSizeBytes: totalSize
        )
    }

    // MARK: - Asset Discovery

    /// Scans a directory and returns valid `WallpaperItem` entries for all videos and web wallpaper folders found.
    public func discoverWallpapers(in directory: URL) async -> [WallpaperItem] {
        var items: [WallpaperItem] = []
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        for itemURL in contents {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                if let _ = try? await validateVideo(at: itemURL) {
                    let title = itemURL.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized
                    items.append(WallpaperItem(
                        title: title,
                        type: .video,
                        pathOrURL: itemURL.path,
                        isBundled: itemURL.path.contains(baseStorageDirectory.path)
                    ))
                }
            } else {
                if let webMeta = try? validateWebDirectory(at: itemURL) {
                    let title = webMeta.title ?? itemURL.lastPathComponent
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized
                    items.append(WallpaperItem(
                        title: title,
                        type: .web,
                        pathOrURL: itemURL.path,
                        isInteractive: true,
                        isBundled: itemURL.path.contains(baseStorageDirectory.path)
                    ))
                }
            }
        }

        return items
    }

    // MARK: - Thumbnail Generation

    /// Extracts a static JPEG thumbnail from a video file.
    public func generateThumbnail(
        for videoURL: URL,
        at destinationURL: URL,
        maximumSize: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = maximumSize

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        let (cgImage, _) = try await imageGenerator.image(at: time)

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw NSError(domain: "AssetManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to compress thumbnail to JPEG"])
        }

        let destinationDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        try jpegData.write(to: destinationURL)
        return destinationURL
    }
}
