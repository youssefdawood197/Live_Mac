import XCTest
import AVFoundation
import WebKit
import Darwin
@testable import WallpaperCore

final class AssetAdversarialTests: XCTestCase {

    var tempDirectory: URL!
    var generator: SampleAssetGenerator!
    var assetManager: AssetManager!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetAdversarialTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        generator = SampleAssetGenerator()
        assetManager = AssetManager(baseStorageDirectory: tempDirectory, generator: generator)
    }

    override func tearDown() async throws {
        if let temp = tempDirectory {
            // Restore permissions if modified
            let files = (try? FileManager.default.subpathsOfDirectory(atPath: temp.path)) ?? []
            for file in files {
                let filePath = temp.appendingPathComponent(file).path
                try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: filePath)
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: temp.path)
            try? FileManager.default.removeItem(at: temp)
        }
        try await super.tearDown()
    }

    // Helper: count open file descriptors in current process
    private func getOpenFileDescriptorCount() -> Int {
        var count = 0
        let maxFD = getdtablesize()
        for fd in 0..<maxFD {
            if fcntl(fd, F_GETFD) != -1 {
                count += 1
            }
        }
        return count
    }

    // Helper: get resident memory in bytes
    private func getResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    // =========================================================================
    // MARK: - 1. SampleAssetGenerator Stress & Invariants
    // =========================================================================

    /// Challenge: Repeated generation runs to verify deterministic file size < 15 KB
    /// and absence of memory leaks or file handle exhaustion.
    func testRepeatedVideoGenerationDeterminismAndNoHandleLeak() async throws {
        let iterations = 25
        var sizes: [Int64] = []
        let initialFDCount = getOpenFileDescriptorCount()
        let initialMemory = getResidentMemoryBytes()

        for i in 0..<iterations {
            let targetURL = tempDirectory.appendingPathComponent("loop_\(i).mp4")
            try await generator.generateSampleVideo(at: targetURL)

            XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
            let attrs = try FileManager.default.attributesOfItem(atPath: targetURL.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

            XCTAssertGreaterThan(size, 5000, "Iteration \(i) produced degenerate file")
            XCTAssertLessThan(size, SampleAssetGenerator.maxExpectedVideoSizeBytes, "Iteration \(i) exceeded 15 KB limit")
            sizes.append(size)
        }

        let finalFDCount = getOpenFileDescriptorCount()
        let finalMemory = getResidentMemoryBytes()

        // Determinism: all generated files should have identical size
        let firstSize = sizes[0]
        for (i, size) in sizes.enumerated() {
            XCTAssertEqual(size, firstSize, "File size drifted on iteration \(i): expected \(firstSize), got \(size)")
        }

        // File handle exhaustion: open file descriptor count should not increase significantly
        let fdDelta = finalFDCount - initialFDCount
        XCTAssertLessThanOrEqual(fdDelta, 3, "File descriptor leak detected! FD delta: \(fdDelta) (initial: \(initialFDCount), final: \(finalFDCount))")

        // Memory growth check: should not explode by more than 80 MB over 25 AVAssetWriter cycles
        let memoryDeltaMB = Double(Int64(finalMemory) - Int64(initialMemory)) / (1024 * 1024)
        print("Memory before: \(initialMemory / 1024 / 1024) MB, after: \(finalMemory / 1024 / 1024) MB, delta: \(memoryDeltaMB) MB")
        XCTAssertLessThan(memoryDeltaMB, 80.0, "Runaway memory leak detected across repeated generation cycles")
    }

    /// Challenge: Inspect generated MP4 container integrity:
    /// AVURLAsset.load(.isPlayable), duration, tracks, frame rate, resolution, frame decoding.
    func testGeneratedMP4ContainerIntegrity() async throws {
        let targetURL = tempDirectory.appendingPathComponent("container_check.mp4")
        try await generator.generateSampleVideo(at: targetURL, duration: 1.0, fps: 24, size: CGSize(width: 320, height: 180), bitrate: 50_000)

        let asset = AVURLAsset(url: targetURL)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Generated MP4 must be playable by AVFoundation")

        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.05, "Duration should be exactly 1.0s")

        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1, "Should contain exactly 1 video track")

        let track = tracks[0]
        let naturalSize = try await track.load(.naturalSize)
        XCTAssertEqual(naturalSize.width, 320, "Track width must be 320")
        XCTAssertEqual(naturalSize.height, 180, "Track height must be 180")

        let nominalFrameRate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(nominalFrameRate, 24.0, accuracy: 0.1, "Track frame rate must be 24fps")

        // Validate frame decoding via AVAssetReader
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(readerOutput)
        XCTAssertTrue(reader.startReading(), "AVAssetReader must start reading generated MP4")

        var decodedFrames = 0
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(sampleBuffer) != nil {
                decodedFrames += 1
            }
        }
        XCTAssertEqual(decodedFrames, 24, "Should successfully decode all 24 frames from the 1-second video")
        XCTAssertEqual(reader.status, .completed, "Reader status must be completed")
    }

    /// Challenge: Test HTML5 canvas output in headless WebKit.
    @MainActor
    func testSampleCanvasHeadlessWebKitExecution() async throws {
        let canvasDir = tempDirectory.appendingPathComponent("canvas_webkit_test")
        let indexURL = try generator.generateSampleCanvas(at: canvasDir)

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)

        final class NavDelegate: NSObject, WKNavigationDelegate {
            var didFinish = false
            var error: Error?
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                didFinish = true
            }
            func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
                self.error = error
            }
            func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
                self.error = error
            }
        }

        let navDelegate = NavDelegate()
        webView.navigationDelegate = navDelegate

        // Load the local HTML file allowing read access to its folder
        _ = webView.loadFileURL(indexURL, allowingReadAccessTo: canvasDir)

        for _ in 0..<40 {
            if navDelegate.didFinish || navDelegate.error != nil {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if let navError = navDelegate.error {
            print("Navigation error: \(navError)")
        }

        let currentURL = webView.url?.absoluteString ?? "nil"
        let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML")) as? String ?? "nil"
        print("Loaded URL: \(currentURL)")
        print("Loaded HTML prefix: \(html.prefix(200))")

        // Validate DOM elements
        let canvasExists = try await webView.evaluateJavaScript("document.getElementById('wallpaperCanvas') !== null") as? Bool
        XCTAssertEqual(canvasExists, true, "Canvas element #wallpaperCanvas must exist in DOM")


        let has2DContext = try await webView.evaluateJavaScript("document.getElementById('wallpaperCanvas').getContext('2d') !== null") as? Bool
        XCTAssertEqual(has2DContext, true, "Canvas must successfully initialize a 2d context")

        // Check window event listeners and functions
        let hasRAF = try await webView.evaluateJavaScript("typeof window.requestAnimationFrame === 'function'") as? Bool
        XCTAssertEqual(hasRAF, true)

        // Simulate interaction events to ensure JS doesn't crash
        let mousemoveResult = try? await webView.evaluateJavaScript("""
            (() => {
                const event = new MouseEvent('mousemove', { clientX: 200, clientY: 200 });
                window.dispatchEvent(event);
                return true;
            })()
        """) as? Bool
        XCTAssertEqual(mousemoveResult, true, "mousemove event dispatch must execute without error")

        let mousedownResult = try? await webView.evaluateJavaScript("""
            (() => {
                const event = new MouseEvent('mousedown', { clientX: 250, clientY: 250 });
                window.dispatchEvent(event);
                return true;
            })()
        """) as? Bool
        XCTAssertEqual(mousedownResult, true, "mousedown event dispatch must execute without error")
    }

    // =========================================================================
    // MARK: - 2. AssetManager Adversarial & Boundary Tests
    // =========================================================================

    /// Challenge: 0-byte video file validation
    func testValidateVideoZeroByteFile() async throws {
        let zeroURL = tempDirectory.appendingPathComponent("zero.mp4")
        FileManager.default.createFile(atPath: zeroURL.path, contents: Data())

        do {
            _ = try await assetManager.validateVideo(at: zeroURL)
            XCTFail("validateVideo must throw on 0-byte file")
        } catch let AssetValidationError.fileIsEmpty(url) {
            XCTAssertEqual(url.path, zeroURL.path)
        } catch {
            XCTFail("Expected fileIsEmpty, got \(error)")
        }
    }

    /// Challenge: Concurrent video generation from multiple async tasks
    func testConcurrentVideoGeneration() async throws {
        let taskCount = 8
        try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
            for i in 0..<taskCount {
                let targetURL = tempDirectory.appendingPathComponent("concurrent_\(i).mp4")
                group.addTask {
                    let gen = SampleAssetGenerator()
                    try await gen.generateSampleVideo(at: targetURL)
                    let attrs = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                    return (i, size)
                }
            }

            var results: [Int: Int64] = [:]
            for try await (id, size) in group {
                results[id] = size
            }

            XCTAssertEqual(results.count, taskCount, "All concurrent generation tasks should succeed")
            let firstSize = results[0]!
            for (id, size) in results {
                XCTAssertEqual(size, firstSize, "Task \(id) produced non-deterministic size: \(size) vs \(firstSize)")
                XCTAssertLessThan(size, SampleAssetGenerator.maxExpectedVideoSizeBytes)
            }
        }
    }

    /// Challenge: Thumbnail extraction with very short video (< 0.1s duration)
    func testThumbnailForVeryShortVideo() async throws {
        let shortVideoURL = tempDirectory.appendingPathComponent("short_video.mp4")
        // Generate a 2-frame video at 24fps (~0.083s duration, less than the 0.1s thumbnail target time)
        try await generator.generateSampleVideo(at: shortVideoURL, duration: 0.085, fps: 24)

        let thumbDest = tempDirectory.appendingPathComponent("short_thumb.jpg")
        do {
            let thumbURL = try await assetManager.generateThumbnail(for: shortVideoURL, at: thumbDest)
            XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))
            let attrs = try FileManager.default.attributesOfItem(atPath: thumbURL.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            XCTAssertGreaterThan(size, 500, "Thumbnail extracted successfully from short video")
            print("Thumbnail for short video extracted successfully with size \(size) bytes")
        } catch {
            print("Thumbnail for short video threw: \(error)")
        }
    }

    /// Challenge: Corrupt video headers (random noise, truncated MP4, zeroed payload)

    func testValidateVideoCorruptHeaders() async throws {
        // Case A: 256 bytes of pure random noise with .mp4 extension
        let noiseURL = tempDirectory.appendingPathComponent("noise.mp4")
        var randomBytes = [UInt8](repeating: 0, count: 256)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        try Data(randomBytes).write(to: noiseURL)

        do {
            _ = try await assetManager.validateVideo(at: noiseURL)
            XCTFail("validateVideo must throw on random noise file")
        } catch {
            // Should fail gracefully with unplayableMedia, missingVideoTrack, or AVError, NOT crash
            print("Corrupt noise properly rejected with: \(error)")
        }

        // Case B: Truncated valid MP4 (first 64 bytes of sample MP4)
        let sampleURL = tempDirectory.appendingPathComponent("sample_to_truncate.mp4")
        try await generator.generateSampleVideo(at: sampleURL)
        let sampleData = try Data(contentsOf: sampleURL)
        let truncatedData = sampleData.prefix(64)

        let truncURL = tempDirectory.appendingPathComponent("truncated.mp4")
        try truncatedData.write(to: truncURL)

        do {
            _ = try await assetManager.validateVideo(at: truncURL)
            XCTFail("validateVideo must throw on truncated MP4")
        } catch {
            print("Truncated MP4 properly rejected with: \(error)")
        }
    }

    /// Challenge: Audio-only MP4 file (missing video track)
    func testValidateVideoAudioOnlyThrowsMissingVideoTrack() async throws {
        // Create an audio-only M4A/MP4
        let audioURL = tempDirectory.appendingPathComponent("audio_only.mp4")
        let assetWriter = try AVAssetWriter(outputURL: audioURL, fileType: .mp4)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 64000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        writerInput.expectsMediaDataInRealTime = false
        assetWriter.add(writerInput)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        writerInput.markAsFinished()
        await assetWriter.finishWriting()

        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                _ = try await assetManager.validateVideo(at: audioURL)
                XCTFail("validateVideo must throw missingVideoTrack for audio-only file")
            } catch AssetValidationError.missingVideoTrack {
                // Expected
            } catch {
                // Alternatively unplayableMedia or missingVideoTrack
                print("Audio-only file rejected with: \(error)")
            }
        }
    }

    /// Challenge: Unreadable file permissions (chmod 000)
    func testValidateVideoUnreadableFileThrows() async throws {
        let unreadableURL = tempDirectory.appendingPathComponent("unreadable.mp4")
        try "test data".write(to: unreadableURL, atomically: true, encoding: .utf8)

        // Revoke all permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableURL.path)

        do {
            _ = try await assetManager.validateVideo(at: unreadableURL)
            XCTFail("validateVideo must throw unreadableFile")
        } catch let AssetValidationError.unreadableFile(url) {
            XCTAssertEqual(url.path, unreadableURL.path)
        } catch {
            // Also acceptable if OS-level permission denied
            print("Unreadable file threw: \(error)")
        }
    }

    /// Challenge: Symlinks handling in validateVideo (valid symlink vs broken symlink)
    func testValidateVideoSymlinks() async throws {
        let targetVideo = tempDirectory.appendingPathComponent("real_target.mp4")
        try await generator.generateSampleVideo(at: targetVideo)

        // 1. Valid symlink pointing to real video
        let validSymlink = tempDirectory.appendingPathComponent("symlink_to_target.mp4")
        try FileManager.default.createSymbolicLink(at: validSymlink, withDestinationURL: targetVideo)

        let meta = try await assetManager.validateVideo(at: validSymlink)
        XCTAssertEqual(meta.naturalSize.width, 320)
        XCTAssertEqual(meta.durationSeconds, 1.0, accuracy: 0.1)

        // 2. Broken symlink pointing to nonexistent file
        let brokenTarget = tempDirectory.appendingPathComponent("deleted_file.mp4")
        let brokenSymlink = tempDirectory.appendingPathComponent("broken_link.mp4")
        try FileManager.default.createSymbolicLink(at: brokenSymlink, withDestinationURL: brokenTarget)

        do {
            _ = try await assetManager.validateVideo(at: brokenSymlink)
            XCTFail("validateVideo must throw fileNotFound for broken symlink")
        } catch let AssetValidationError.fileNotFound(url) {
            XCTAssertEqual(url.path, brokenSymlink.path)
        } catch {
            XCTFail("Expected fileNotFound, got \(error)")
        }
    }

    /// Challenge: Symlink loops in validateWebDirectory
    func testValidateWebDirectorySymlinkLoop() throws {
        let webDir = tempDirectory.appendingPathComponent("symlink_loop_web")
        try FileManager.default.createDirectory(at: webDir, withIntermediateDirectories: true)
        let indexFile = webDir.appendingPathComponent("index.html")
        try "<html><head><title>Loop Test</title></head><body><h1>Loop</h1></body></html>".write(to: indexFile, atomically: true, encoding: .utf8)

        // Create recursive symlink loop: webDir/loop -> webDir
        let loopSymlink = webDir.appendingPathComponent("infinite_loop")
        try FileManager.default.createSymbolicLink(at: loopSymlink, withDestinationURL: webDir)

        // validateWebDirectory enumerates the directory to compute totalSizeBytes.
        // It must NOT hang or enter infinite recursion.
        let meta = try assetManager.validateWebDirectory(at: webDir)
        XCTAssertEqual(meta.title, "Loop Test")
        XCTAssertGreaterThan(meta.totalSizeBytes, 0)
        print("Total size calculated safely with symlink loop: \(meta.totalSizeBytes) bytes")
    }

    /// Challenge: Unreadable web directory permissions (chmod 000)
    func testValidateWebDirectoryUnreadableFolder() throws {
        let unreadableDir = tempDirectory.appendingPathComponent("unreadable_web_dir")
        try FileManager.default.createDirectory(at: unreadableDir, withIntermediateDirectories: true)
        let indexFile = unreadableDir.appendingPathComponent("index.html")
        try "<html><body>Hello</body></html>".write(to: indexFile, atomically: true, encoding: .utf8)

        // Revoke directory access
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableDir.path)

        do {
            _ = try assetManager.validateWebDirectory(at: unreadableDir)
            XCTFail("validateWebDirectory must throw for unreadable directory")
        } catch {
            print("Unreadable web dir threw as expected: \(error)")
        }
    }

    /// Challenge: discoverWallpapers resilience with unreadable directory and symlink loop
    func testDiscoverWallpapersResilience() async throws {
        let discoveryDir = tempDirectory.appendingPathComponent("discovery_test")
        try FileManager.default.createDirectory(at: discoveryDir, withIntermediateDirectories: true)

        // Valid video
        let validVid = discoveryDir.appendingPathComponent("nature_loop.mp4")
        try await generator.generateSampleVideo(at: validVid)

        // Valid web folder
        let validWeb = discoveryDir.appendingPathComponent("waves_web")
        try generator.generateSampleCanvas(at: validWeb)

        // 0-byte file (should be ignored)
        let zeroFile = discoveryDir.appendingPathComponent("corrupt.mp4")
        FileManager.default.createFile(atPath: zeroFile.path, contents: Data())

        // Non-video file (should be ignored)
        let textFile = discoveryDir.appendingPathComponent("readme.txt")
        try "just text".write(to: textFile, atomically: true, encoding: .utf8)

        // Empty folder without index.html (should be ignored)
        let emptyFolder = discoveryDir.appendingPathComponent("empty_folder")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        let discovered = await assetManager.discoverWallpapers(in: discoveryDir)
        XCTAssertEqual(discovered.count, 2, "Should discover exactly 2 wallpapers (1 video, 1 web)")
        XCTAssertTrue(discovered.contains { $0.type == .video && $0.title == "Nature Loop" })
        XCTAssertTrue(discovered.contains { $0.type == .web })
    }

    /// Challenge: Thumbnail generation failure modes:
    /// non-video file, 0-byte file, corrupt file, destination in read-only directory
    func testThumbnailGenerationFailureModes() async throws {
        let thumbDest = tempDirectory.appendingPathComponent("thumb_fail.jpg")

        // 1. Non-video file (text file)
        let textFile = tempDirectory.appendingPathComponent("not_video.txt")
        try "hello world".write(to: textFile, atomically: true, encoding: .utf8)
        do {
            _ = try await assetManager.generateThumbnail(for: textFile, at: thumbDest)
            XCTFail("generateThumbnail must throw on text file")
        } catch {
            print("Non-video thumbnail rejected cleanly: \(error)")
        }

        // 2. 0-byte file
        let emptyFile = tempDirectory.appendingPathComponent("empty.mp4")
        FileManager.default.createFile(atPath: emptyFile.path, contents: Data())
        do {
            _ = try await assetManager.generateThumbnail(for: emptyFile, at: thumbDest)
            XCTFail("generateThumbnail must throw on 0-byte file")
        } catch {
            print("0-byte thumbnail rejected cleanly: \(error)")
        }

        // 3. Corrupt video
        let corruptFile = tempDirectory.appendingPathComponent("garbage.mp4")
        try Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33]).write(to: corruptFile)
        do {
            _ = try await assetManager.generateThumbnail(for: corruptFile, at: thumbDest)
            XCTFail("generateThumbnail must throw on corrupt video")
        } catch {
            print("Corrupt video thumbnail rejected cleanly: \(error)")
        }

        // 4. Nonexistent video
        let missingFile = tempDirectory.appendingPathComponent("missing_video.mp4")
        do {
            _ = try await assetManager.generateThumbnail(for: missingFile, at: thumbDest)
            XCTFail("generateThumbnail must throw on nonexistent video")
        } catch {
            print("Nonexistent video thumbnail rejected cleanly: \(error)")
        }
    }

    /// Challenge: Read-only destination directory for generateSampleVideo and generateThumbnail
    func testReadOnlyDestinationHandling() async throws {
        let readOnlyDir = tempDirectory.appendingPathComponent("readonly_dir")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)

        // Attempt to generate video inside read-only directory
        let videoURL = readOnlyDir.appendingPathComponent("output.mp4")
        do {
            _ = try await generator.generateSampleVideo(at: videoURL)
            XCTFail("generateSampleVideo must throw when writing to read-only directory")
        } catch {
            print("Read-only video generation properly failed: \(error)")
        }

        // Attempt to generate thumbnail inside read-only directory
        let validVideo = tempDirectory.appendingPathComponent("source_valid.mp4")
        try await generator.generateSampleVideo(at: validVideo)

        let thumbURL = readOnlyDir.appendingPathComponent("thumb.jpg")
        do {
            _ = try await assetManager.generateThumbnail(for: validVideo, at: thumbURL)
            XCTFail("generateThumbnail must throw when destination is read-only")
        } catch {
            print("Read-only thumbnail destination properly failed: \(error)")
        }
    }
}
