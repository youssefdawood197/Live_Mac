import Foundation
import AppKit
import AVFoundation
import WebKit

/// Thread-safe, observable manager that coordinates in-memory and on-disk caching
/// and asynchronous generation of video and web wallpaper preview thumbnails.
@MainActor
public final class ThumbnailManager: ObservableObject {

    public static let shared = ThumbnailManager()

    /// In-memory cache for fast, zero-delay rendering during scrolling and grid display.
    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 150
        cache.totalCostLimit = 120 * 1024 * 1024 // 120 MB
        return cache
    }()

    /// Persistent directory where extracted thumbnail JPEGs are stored.
    public let thumbnailsDirectory: URL

    /// File manager instance.
    private let fileManager: FileManager

    /// Published dictionary mapping wallpaper UUIDs to loaded thumbnails for reactive SwiftUI views.
    @Published public private(set) var loadedThumbnails: [UUID: NSImage] = [:]

    public init(
        thumbnailsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let dir = thumbnailsDirectory {
            self.thumbnailsDirectory = dir
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.thumbnailsDirectory = appSupport.appendingPathComponent("LivelyWallpaper/Thumbnails", isDirectory: true)
        }

        // Ensure thumbnails directory exists
        if !self.fileManager.fileExists(atPath: self.thumbnailsDirectory.path) {
            try? self.fileManager.createDirectory(at: self.thumbnailsDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Synchronous In-Memory & Fast Disk Cache Lookup

    /// Returns a cached thumbnail immediately if present in memory or on local disk.
    public func cachedImage(for item: WallpaperItem) -> NSImage? {
        let key = item.id.uuidString as NSString

        // 1. Check in-memory NSCache
        if let memoryImage = memoryCache.object(forKey: key) {
            return memoryImage
        }

        // 2. Check reactive dictionary
        if let dictImage = loadedThumbnails[item.id] {
            memoryCache.setObject(dictImage, forKey: key)
            return dictImage
        }

        // 3. Check item's explicitly set thumbnailURL
        if let thumbURL = item.thumbnailURL, fileManager.fileExists(atPath: thumbURL.path) {
            if let diskImage = NSImage(contentsOf: thumbURL) {
                memoryCache.setObject(diskImage, forKey: key)
                return diskImage
            }
        }

        // 4. Check persistent disk cache at ~/Library/Application Support/LivelyWallpaper/Thumbnails/<id>.jpg
        let persistentURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
        if fileManager.fileExists(atPath: persistentURL.path), let diskImage = NSImage(contentsOf: persistentURL) {
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }

        // 5. For web folders: check folder for thumbnail.jpg / thumbnail.png / preview.jpg
        if item.type == .web {
            let folderURL = item.sourceURL
            for name in ["thumbnail.jpg", "thumbnail.png", "preview.jpg", "preview.png"] {
                let candidate = folderURL.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path), let folderImage = NSImage(contentsOf: candidate) {
                    memoryCache.setObject(folderImage, forKey: key)
                    return folderImage
                }
            }
        }

        // 6. For video files: check sibling <video_name>.jpg or .png
        if item.type == .video {
            let candidateJPG = item.sourceURL.deletingPathExtension().appendingPathExtension("jpg")
            if fileManager.fileExists(atPath: candidateJPG.path), let sibImage = NSImage(contentsOf: candidateJPG) {
                memoryCache.setObject(sibImage, forKey: key)
                return sibImage
            }
        }

        return nil
    }

    // MARK: - Asynchronous Thumbnail Resolution & Generation

    /// Asynchronously loads or generates a high-resolution preview thumbnail for any wallpaper item.
    @discardableResult
    public func loadThumbnail(for item: WallpaperItem) async -> NSImage? {
        let key = item.id.uuidString as NSString
        let destURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")

        // Fast path: if persistent file already exists, return cached
        if fileManager.fileExists(atPath: destURL.path), let existing = cachedImage(for: item) {
            return existing
        }

        switch item.type {
        case .video:
            guard item.fileExists else { return nil }
            let videoURL = item.sourceURL

            // Check if sibling JPG exists
            let candidateJPG = videoURL.deletingPathExtension().appendingPathExtension("jpg")
            if fileManager.fileExists(atPath: candidateJPG.path) {
                if !fileManager.fileExists(atPath: destURL.path) {
                    try? fileManager.copyItem(at: candidateJPG, to: destURL)
                }
                if let sibImage = NSImage(contentsOf: destURL) ?? NSImage(contentsOf: candidateJPG) {
                    memoryCache.setObject(sibImage, forKey: key)
                    loadedThumbnails[item.id] = sibImage
                    return sibImage
                }
            }

            do {
                let image = try await generateVideoFrame(at: videoURL, destinationURL: destURL)
                memoryCache.setObject(image, forKey: key)
                loadedThumbnails[item.id] = image
                return image
            } catch {
                return nil
            }

        case .web:
            // Check folder candidates first
            let folderURL = item.sourceURL
            for name in ["thumbnail.jpg", "thumbnail.png", "preview.jpg", "preview.png"] {
                let candidate = folderURL.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path), let folderImage = NSImage(contentsOf: candidate) {
                    memoryCache.setObject(folderImage, forKey: key)
                    loadedThumbnails[item.id] = folderImage
                    return folderImage
                }
            }

            // Fallback: Headless snapshot using WKWebView if index.html exists
            let indexURL = folderURL.appendingPathComponent("index.html")
            guard fileManager.fileExists(atPath: indexURL.path) else { return nil }
            let destURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")

            if let snapshot = await snapshotWebPage(fileURL: indexURL, allowingDir: folderURL, destinationURL: destURL) {
                memoryCache.setObject(snapshot, forKey: key)
                loadedThumbnails[item.id] = snapshot
                return snapshot
            }
            return nil

        case .url:
            guard let url = item.resolvedURL else { return nil }
            let destURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
            if let snapshot = await snapshotWebPage(remoteURL: url, destinationURL: destURL) {
                memoryCache.setObject(snapshot, forKey: key)
                loadedThumbnails[item.id] = snapshot
                return snapshot
            }
            return nil
        }
    }

    // MARK: - Video Frame Capture

    /// Captures a crisp video frame via AVAssetImageGenerator and writes it as a compressed JPEG to disk.
    private func generateVideoFrame(at videoURL: URL, destinationURL: URL) async throws -> NSImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        // Try at 0.5s into video for an active frame; fallback to 0.05s
        var cgImage: CGImage? = nil
        do {
            let (img, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            cgImage = img
        } catch {
            let (img, _) = try await generator.image(at: CMTime(seconds: 0.05, preferredTimescale: 600))
            cgImage = img
        }

        guard let validCGImage = cgImage else {
            throw NSError(domain: "ThumbnailManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to capture CGImage from video"])
        }

        let nsImage = NSImage(cgImage: validCGImage, size: NSSize(width: 640, height: 360))

        // Write JPEG to disk cache
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? jpegData.write(to: destinationURL)
        }

        return nsImage
    }

    // MARK: - Web Snapshot Capture

    /// Headless snapshot for local HTML or remote URL wallpapers.
    private func snapshotWebPage(
        fileURL: URL? = nil,
        allowingDir: URL? = nil,
        remoteURL: URL? = nil,
        destinationURL: URL
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: config)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = webView
            window.orderBack(nil)

            if let file = fileURL, let dir = allowingDir {
                webView.loadFileURL(file, allowingReadAccessTo: dir)
            } else if let remote = remoteURL {
                webView.load(URLRequest(url: remote))
            } else {
                window.close()
                continuation.resume(returning: nil)
                return
            }

            // Allow 1.2s for JS/WebGL/canvas to render first frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                webView.takeSnapshot(with: nil) { image, error in
                    window.close()
                    guard let image = image,
                          let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    try? jpeg.write(to: destinationURL)
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Library Backfill & Persistence Repair

    /// Discovers and assigns thumbnail paths for any existing wallpapers missing them, and saves the library.
    public func backfillThumbnails(
        for items: [WallpaperItem],
        library: WallpaperLibrary,
        appState: AppState
    ) async {
        var didModify = false

        for item in items {
            // Check if item already has a valid, existing thumbnail file
            if let thumbPath = item.thumbnailPath, !thumbPath.isEmpty, fileManager.fileExists(atPath: thumbPath) {
                continue
            }

            // Attempt to load or generate
            if await loadThumbnail(for: item) != nil {
                // Determine persistent file path
                var resolvedThumbPath: String? = nil

                // 1. Check if persistent thumbnail file was written
                let persistentURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
                if fileManager.fileExists(atPath: persistentURL.path) {
                    resolvedThumbPath = persistentURL.path
                }
                // 2. For web folder, check if thumbnail.jpg exists in folder
                if resolvedThumbPath == nil && item.type == .web {
                    let folderThumb = item.sourceURL.appendingPathComponent("thumbnail.jpg")
                    if fileManager.fileExists(atPath: folderThumb.path) {
                        resolvedThumbPath = folderThumb.path
                    }
                }
                // 3. For video, check sibling
                if resolvedThumbPath == nil && item.type == .video {
                    let sibThumb = item.sourceURL.deletingPathExtension().appendingPathExtension("jpg")
                    if fileManager.fileExists(atPath: sibThumb.path) {
                        resolvedThumbPath = sibThumb.path
                    }
                }

                if let path = resolvedThumbPath {
                    var updated = item
                    updated.thumbnailPath = path
                    appState.updateWallpaper(updated)
                    try? await library.updateWallpaper(updated)
                    didModify = true
                }
            }
        }

        if didModify {
            try? await library.save()
        }
    }
}
