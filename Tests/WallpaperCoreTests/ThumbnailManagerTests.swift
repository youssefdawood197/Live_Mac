import XCTest
import AppKit
import AVFoundation
@testable import WallpaperCore

@MainActor
final class ThumbnailManagerTests: XCTestCase {

    var tempDirectory: URL!
    var manager: ThumbnailManager!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ThumbnailTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        manager = ThumbnailManager(thumbnailsDirectory: tempDirectory)
    }

    override func tearDown() async throws {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        try await super.tearDown()
    }

    func testMemoryAndDiskCacheHit() async throws {
        let item = WallpaperItem(
            title: "Test Video",
            type: .video,
            pathOrURL: "/nonexistent/video.mp4"
        )

        // Initially nil
        XCTAssertNil(manager.cachedImage(for: item))

        // Create a dummy image and save to persistent disk cache
        let testImage = NSImage(size: NSSize(width: 320, height: 180))
        testImage.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 180).fill()
        testImage.unlockFocus()

        let diskPath = tempDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
        let tiff = testImage.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
        try jpeg.write(to: diskPath)

        // Now cachedImage should find it on disk and cache in memory
        let loaded = manager.cachedImage(for: item)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.size.width, 320)
    }

    func testVideoThumbnailGenerationFromSample() async throws {
        let sampleVideoURL = URL(fileURLWithPath: "Resources/Samples/sample_loop.mp4")
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            throw XCTSkip("Resources/Samples/sample_loop.mp4 not found in current directory")
        }

        // Copy video to isolated temp location without sibling jpg to test AVAssetImageGenerator
        let isolatedVideo = tempDirectory.appendingPathComponent("isolated_loop.mp4")
        try FileManager.default.copyItem(at: sampleVideoURL, to: isolatedVideo)

        let item = WallpaperItem(
            title: "Sample Video",
            type: .video,
            sourceURL: isolatedVideo
        )

        let image = await manager.loadThumbnail(for: item)
        XCTAssertNotNil(image)

        // Verify disk cache file exists
        let diskPath = tempDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: diskPath.path))
    }

    func testWebThumbnailDiscoveryInDirectory() async throws {
        let webDir = tempDirectory.appendingPathComponent("custom_web", isDirectory: true)
        try FileManager.default.createDirectory(at: webDir, withIntermediateDirectories: true)

        let indexHTML = webDir.appendingPathComponent("index.html")
        try "<html><body><h1>Test</h1></body></html>".write(to: indexHTML, atomically: true, encoding: .utf8)

        let thumbURL = webDir.appendingPathComponent("thumbnail.jpg")
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        testImage.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        testImage.unlockFocus()
        let rep = NSBitmapImageRep(data: testImage.tiffRepresentation!)!
        try rep.representation(using: .jpeg, properties: [:])!.write(to: thumbURL)

        let item = WallpaperItem(
            title: "Custom Web",
            type: .web,
            sourceURL: webDir
        )

        let image = await manager.loadThumbnail(for: item)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width, 100)
    }

    func testBackfillThumbnails() async throws {
        let sampleVideoURL = URL(fileURLWithPath: "Resources/Samples/sample_loop.mp4")
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            throw XCTSkip("Resources/Samples/sample_loop.mp4 not found")
        }

        let item = WallpaperItem(
            title: "Needs Thumbnail",
            type: .video,
            sourceURL: sampleVideoURL
        )
        XCTAssertNil(item.thumbnailPath)

        let libraryStorage = tempDirectory.appendingPathComponent("library", isDirectory: true)
        let library = WallpaperLibrary(storageDirectory: libraryStorage)
        try await library.add(item)

        let appState = AppState(wallpapers: [item])

        await manager.backfillThumbnails(for: [item], library: library, appState: appState)

        let updated = appState.wallpapers.first
        XCTAssertNotNil(updated?.thumbnailPath)
        if let path = updated?.thumbnailPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }

        // Verify library persisted it
        let reloaded = try await library.loadWallpapers()
        XCTAssertNotNil(reloaded.first?.thumbnailPath)
    }
}
