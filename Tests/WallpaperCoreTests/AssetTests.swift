import XCTest
import AVFoundation
@testable import WallpaperCore

final class AssetTests: XCTestCase {

    var tempDirectory: URL!
    var generator: SampleAssetGenerator!
    var assetManager: AssetManager!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        generator = SampleAssetGenerator()
        assetManager = AssetManager(baseStorageDirectory: tempDirectory, generator: generator)
    }

    override func tearDown() async throws {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        try await super.tearDown()
    }

    // MARK: - SampleAssetGenerator Tests

    func testSampleVideoGenerationCreatesValidFileUnder15KB() async throws {
        let targetURL = tempDirectory.appendingPathComponent("test_loop.mp4")
        try await generator.generateSampleVideo(at: targetURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        XCTAssertGreaterThan(fileSize, 1000, "Generated video should not be degenerate")
        XCTAssertLessThan(fileSize, 15 * 1024, "Generated video must be strictly less than 15 KB")

        let metadata = try await assetManager.validateVideo(at: targetURL)
        XCTAssertEqual(metadata.naturalSize.width, 320)
        XCTAssertEqual(metadata.naturalSize.height, 180)
        XCTAssertEqual(metadata.frameRate, 24.0)
        XCTAssertEqual(round(metadata.durationSeconds * 10) / 10, 1.0)
    }

    func testSampleCanvasGenerationCreatesValidHTML() throws {
        let canvasDir = tempDirectory.appendingPathComponent("test_canvas")
        let indexURL = try generator.generateSampleCanvas(at: canvasDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        let content = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(content.contains("<canvas id=\"wallpaperCanvas\">"))
        XCTAssertTrue(content.contains("requestAnimationFrame"))
        XCTAssertTrue(content.contains("visibilitychange"))
        XCTAssertTrue(content.contains("devicePixelRatio"))

        let webMeta = try assetManager.validateWebDirectory(at: canvasDir)
        XCTAssertEqual(webMeta.title, "Lively Waves - Canvas Wallpaper")
        XCTAssertGreaterThan(webMeta.totalSizeBytes, 0)
    }

    func testGenerateAllSamplesProducesBothAssets() async throws {
        let outputDir = tempDirectory.appendingPathComponent("all_samples")
        let (videoURL, canvasDir) = try await generator.generateAllSamples(in: outputDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: canvasDir.appendingPathComponent("index.html").path))
    }

    // MARK: - AssetManager Validation Tests

    func testValidateVideoSucceedsOnValidMP4() async throws {
        let videoURL = tempDirectory.appendingPathComponent("valid.mp4")
        try await generator.generateSampleVideo(at: videoURL)

        let meta = try await assetManager.validateVideo(at: videoURL)
        XCTAssertEqual(meta.codec, "avc1")
        XCTAssertEqual(meta.durationSeconds, 1.0, accuracy: 0.1)
    }

    func testValidateVideoFailsOnNonexistentFile() async {
        let missingURL = tempDirectory.appendingPathComponent("missing.mp4")
        do {
            _ = try await assetManager.validateVideo(at: missingURL)
            XCTFail("Should throw fileNotFound")
        } catch let AssetValidationError.fileNotFound(url) {
            XCTAssertEqual(url.path, missingURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateVideoFailsOnEmptyFile() async throws {
        let emptyURL = tempDirectory.appendingPathComponent("empty.mp4")
        try Data().write(to: emptyURL)

        do {
            _ = try await assetManager.validateVideo(at: emptyURL)
            XCTFail("Should throw fileIsEmpty")
        } catch let AssetValidationError.fileIsEmpty(url) {
            XCTAssertEqual(url.path, emptyURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateVideoFailsOnUnsupportedFormat() async throws {
        let textURL = tempDirectory.appendingPathComponent("notes.txt")
        try "test".write(to: textURL, atomically: true, encoding: .utf8)

        do {
            _ = try await assetManager.validateVideo(at: textURL)
            XCTFail("Should throw unsupportedFormat")
        } catch let AssetValidationError.unsupportedFormat(ext) {
            XCTAssertEqual(ext, "txt")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateWebDirectoryFailsWhenIndexMissing() throws {
        let emptyFolder = tempDirectory.appendingPathComponent("empty_web")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        do {
            _ = try assetManager.validateWebDirectory(at: emptyFolder)
            XCTFail("Should throw missingIndexHTML")
        } catch let AssetValidationError.missingIndexHTML(dir) {
            XCTAssertEqual(dir.path, emptyFolder.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateWebDirectoryFailsWhenIndexEmpty() throws {
        let folder = tempDirectory.appendingPathComponent("empty_index_web")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = folder.appendingPathComponent("index.html")
        try Data().write(to: index)

        do {
            _ = try assetManager.validateWebDirectory(at: folder)
            XCTFail("Should throw emptyIndexHTML")
        } catch let AssetValidationError.emptyIndexHTML(file) {
            XCTAssertEqual(file.path, index.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Extraction & Discovery Tests

    func testEnsureDefaultSamplesExtractedIdempotency() async throws {
        let (v1, c1) = try await assetManager.ensureDefaultSamplesExtracted()
        XCTAssertTrue(FileManager.default.fileExists(atPath: v1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: c1.path))

        // Running a second time should not fail and should retain existing files
        let (v2, c2) = try await assetManager.ensureDefaultSamplesExtracted()
        XCTAssertEqual(v1.path, v2.path)
        XCTAssertEqual(c1.path, c2.path)
    }

    func testDiscoverWallpapersFindsExtractedSamples() async throws {
        _ = try await assetManager.ensureDefaultSamplesExtracted()
        let wallpapers = await assetManager.discoverWallpapers(in: tempDirectory)

        XCTAssertEqual(wallpapers.count, 2)
        XCTAssertTrue(wallpapers.contains { $0.type == .video })
        XCTAssertTrue(wallpapers.contains { $0.type == .web })
    }

    func testThumbnailGenerationProducesValidJPEG() async throws {
        let videoURL = tempDirectory.appendingPathComponent("thumb_video.mp4")
        try await generator.generateSampleVideo(at: videoURL)

        let thumbURL = tempDirectory.appendingPathComponent("thumb.jpg")
        let generatedURL = try await assetManager.generateThumbnail(for: videoURL, at: thumbURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: generatedURL.path))
        let thumbAttrs = try FileManager.default.attributesOfItem(atPath: generatedURL.path)
        let thumbSize = (thumbAttrs[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(thumbSize, 500, "Thumbnail should contain valid image data")
    }
}
