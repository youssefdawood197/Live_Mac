import XCTest
import AppKit
import AVFoundation
@testable import WallpaperCore

// MARK: - Milestone 3 Video Engine Adversarial & Stress Challenge Tests

@MainActor
final class Milestone3VideoChallengeTests: XCTestCase {

    private var sampleVideoURL: URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WallpaperCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("Resources/Samples/sample_loop.mp4")
    }

    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("M3Challenge_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        try await super.tearDown()
    }

    // MARK: - 1. File Handling & Corruption Resilience Tests

    func testNonExistentVideoFileRaisesMissingFileError() {
        let delegate = MockEngineDelegate()
        let missingURL = tempDirectory.appendingPathComponent("missing_video_\(UUID().uuidString).mp4")
        let item = WallpaperItem(title: "Missing", type: .video, pathOrURL: missingURL.path)

        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertTrue(engine.hasError, "Engine must flag hasError when file does not exist")
        XCTAssertFalse(engine.isPlaying, "Engine must not be playing when file does not exist")
        XCTAssertNotNil(engine.lastEncounteredError, "lastEncounteredError must be populated")
        XCTAssertEqual(delegate.errors.count, 1, "Delegate must receive exactly 1 error notification")

        if let error = delegate.errors.first?.error as? VideoEngineError {
            XCTAssertEqual(error, .missingFile(missingURL))
        } else {
            XCTFail("Expected VideoEngineError.missingFile, got \(String(describing: delegate.errors.first?.error))")
        }

        // Verify calling play() does nothing on error engine
        engine.play()
        XCTAssertFalse(engine.isPlaying, "Calling play() on error engine must remain false")
    }

    func testZeroByteVideoFileRaisesZeroByteFileError() throws {
        let delegate = MockEngineDelegate()
        let zeroByteURL = tempDirectory.appendingPathComponent("empty_\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: zeroByteURL.path, contents: Data())

        let item = WallpaperItem(title: "Empty", type: .video, pathOrURL: zeroByteURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertTrue(engine.hasError, "Engine must flag hasError for 0-byte file")
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.errors.count, 1)

        if let error = delegate.errors.first?.error as? VideoEngineError {
            XCTAssertEqual(error, .zeroByteFile(zeroByteURL))
        } else {
            XCTFail("Expected VideoEngineError.zeroByteFile, got \(String(describing: delegate.errors.first?.error))")
        }

        engine.play()
        XCTAssertFalse(engine.isPlaying)
    }

    func testCorruptHeaderMagicBytesRaisesCorruptFileError() throws {
        let delegate = MockEngineDelegate()
        let corruptURL = tempDirectory.appendingPathComponent("corrupt_magic_\(UUID().uuidString).mp4")
        let corruptData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])
        try corruptData.write(to: corruptURL)

        let item = WallpaperItem(title: "CorruptMagic", type: .video, pathOrURL: corruptURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertTrue(engine.hasError)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.errors.count, 1)

        if let error = delegate.errors.first?.error as? VideoEngineError {
            XCTAssertEqual(error, .corruptFile(corruptURL))
        } else {
            XCTFail("Expected VideoEngineError.corruptFile, got \(String(describing: delegate.errors.first?.error))")
        }
    }

    func testRandomBinaryGarbageResilience() throws {
        let delegate = MockEngineDelegate()
        let garbageURL = tempDirectory.appendingPathComponent("garbage_\(UUID().uuidString).mp4")
        // 4KB of pseudo-random noise (not starting with DEADBEEF)
        var bytes = [UInt8](repeating: 0, count: 4096)
        for i in 0..<bytes.count {
            bytes[i] = UInt8((i * 137 + 73) % 256)
        }
        try Data(bytes).write(to: garbageURL)

        let item = WallpaperItem(title: "Garbage", type: .video, pathOrURL: garbageURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        // Must not crash or hang; looper or AVPlayerItem status will asynchronously flag failure or error
        XCTAssertNotNil(engine.view)
        XCTAssertFalse(engine.isPlaying)
    }

    func testTruncatedFTYPHeaderResilience() throws {
        let delegate = MockEngineDelegate()
        let truncatedURL = tempDirectory.appendingPathComponent("truncated_\(UUID().uuidString).mp4")
        // Valid ftyp atom header but truncated before moov
        let ftypHeader = Data([
            0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size 24, ftyp
            0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00, // isom
            0x6D, 0x70, 0x34, 0x31, 0x69, 0x73, 0x6F, 0x6D  // mp41, isom
        ])
        try ftypHeader.write(to: truncatedURL)

        let item = WallpaperItem(title: "Truncated", type: .video, pathOrURL: truncatedURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertNotNil(engine.view)
        XCTAssertFalse(engine.isPlaying)
    }

    func testUnsupportedVideoFormatRejection() throws {
        let unsupportedExtensions = ["avi", "mkv", "flv", "wmv", "webm", "txt", "png", "gif"]
        for ext in unsupportedExtensions {
            let fileURL = tempDirectory.appendingPathComponent("dummy_\(UUID().uuidString).\(ext)")
            try "fake content".write(to: fileURL, atomically: true, encoding: .utf8)

            let delegate = MockEngineDelegate()
            let item = WallpaperItem(title: "Unsupported", type: .video, pathOrURL: fileURL.path)
            let engine = VideoWallpaperEngine(item: item, delegate: delegate)
            defer { engine.terminate() }

            XCTAssertTrue(engine.hasError, "Extension .\(ext) must be flagged with error")
            XCTAssertFalse(engine.isPlaying)
            XCTAssertEqual(delegate.errors.count, 1)
            XCTAssertEqual(delegate.errors.first?.error as? VideoEngineError, .unsupportedFormat(ext))
        }
    }

    func testDirectoryProvidedInsteadOfVideoFileRejection() throws {
        let dirURL = tempDirectory.appendingPathComponent("fake_video_dir.mp4")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "DirAsVideo", type: .video, pathOrURL: dirURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        // Directories with .mp4 extension must not crash and should fail or reject
        XCTAssertNotNil(engine.view)
    }

    // MARK: - 2. Audio Volume Extremes & Boundary Stress Tests

    func testInitialVolumeExtremeValuesClamping() {
        // Negative initial volumes must clamp to 0.0
        let negItem = WallpaperItem(title: "Neg", type: .video, pathOrURL: "/dummy.mp4", volume: -5.0)
        let negEngine = VideoWallpaperEngine(item: negItem)
        defer { negEngine.terminate() }
        XCTAssertEqual(negEngine.volume, 0.0)
        XCTAssertEqual(negEngine.player.volume, 0.0)

        // Overflow initial volumes (> 1.0) must clamp to 1.0
        let overItem = WallpaperItem(title: "Over", type: .video, pathOrURL: "/dummy.mp4", volume: 42.0)
        let overEngine = VideoWallpaperEngine(item: overItem)
        defer { overEngine.terminate() }
        XCTAssertEqual(overEngine.volume, 1.0)
        XCTAssertEqual(overEngine.player.volume, 1.0)

        // When passed via initialVolume parameter:
        // NaN initial volume must clamp safely to 0.0
        let item = WallpaperItem(title: "Norm", type: .video, pathOrURL: "/dummy.mp4")
        let nanEngine = VideoWallpaperEngine(item: item, initialVolume: Float.nan)
        defer { nanEngine.terminate() }
        XCTAssertEqual(nanEngine.volume, 0.0)
        XCTAssertEqual(nanEngine.player.volume, 0.0)

        // Infinity initial volume must clamp safely to 0.0
        let infEngine = VideoWallpaperEngine(item: item, initialVolume: Float.infinity)
        defer { infEngine.terminate() }
        XCTAssertEqual(infEngine.volume, 0.0)
        XCTAssertEqual(infEngine.player.volume, 0.0)

        // -Infinity initial volume must clamp safely to 0.0
        let negInfEngine = VideoWallpaperEngine(item: item, initialVolume: -Float.infinity)
        defer { negInfEngine.terminate() }
        XCTAssertEqual(negInfEngine.volume, 0.0)
        XCTAssertEqual(negInfEngine.player.volume, 0.0)

    }

    func testDynamicVolumeSetterEdgeCases() {
        let item = WallpaperItem(title: "Vol", type: .video, pathOrURL: "/dummy.mp4", volume: 0.5)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        // Normal values
        engine.volume = 0.75
        XCTAssertEqual(engine.volume, 0.75)
        XCTAssertEqual(engine.player.volume, 0.75)

        engine.volume = 0.0
        XCTAssertEqual(engine.volume, 0.0)
        XCTAssertEqual(engine.player.volume, 0.0)

        engine.volume = 1.0
        XCTAssertEqual(engine.volume, 1.0)
        XCTAssertEqual(engine.player.volume, 1.0)

        // Upper clamp
        engine.volume = 1.0001
        XCTAssertEqual(engine.volume, 1.0)

        engine.volume = 999_999.0
        XCTAssertEqual(engine.volume, 1.0)

        // Lower clamp
        engine.volume = -0.0001
        XCTAssertEqual(engine.volume, 0.0)

        engine.volume = -999_999.0
        XCTAssertEqual(engine.volume, 0.0)

        // NaN
        engine.volume = Float.nan
        XCTAssertEqual(engine.volume, 0.0)
        XCTAssertEqual(engine.player.volume, 0.0)

        // Positive Infinity
        engine.volume = Float.infinity
        XCTAssertEqual(engine.volume, 0.0)
        XCTAssertEqual(engine.player.volume, 0.0)

        // Negative Infinity
        engine.volume = -Float.infinity
        XCTAssertEqual(engine.volume, 0.0)
        XCTAssertEqual(engine.player.volume, 0.0)

        // Smallest non-zero magnitude
        engine.volume = Float.leastNonzeroMagnitude
        XCTAssertGreaterThan(engine.volume, 0.0)
        XCTAssertLessThan(engine.volume, 0.001)
    }

    func testVolumeAdjustmentWhileMutedPreservesMuteState() {
        let item = WallpaperItem(title: "MuteInvariant", type: .video, pathOrURL: "/dummy.mp4", volume: 0.5, isMuted: true)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        XCTAssertTrue(engine.isMuted, "Engine must initialize muted")
        XCTAssertTrue(engine.player.isMuted, "AVPlayer must be muted")

        // Volume adjustments while isMuted = true MUST keep engine.isMuted == true and player.isMuted == true
        let testVolumes: [Float] = [0.0, 0.25, 0.5, 0.8, 1.0, 1.5, -0.5, Float.nan, Float.infinity]
        for vol in testVolumes {
            engine.volume = vol
            XCTAssertTrue(engine.isMuted, "engine.isMuted must remain true after setting volume to \(vol)")
            XCTAssertTrue(engine.player.isMuted, "engine.player.isMuted must remain true after setting volume to \(vol)")
        }

        // Setting engine.volume to 0.85 then unmuting must restore volume 0.85
        engine.volume = 0.85
        XCTAssertTrue(engine.isMuted)
        engine.isMuted = false
        XCTAssertFalse(engine.isMuted)
        XCTAssertFalse(engine.player.isMuted)
        XCTAssertEqual(engine.volume, 0.85)
        XCTAssertEqual(engine.player.volume, 0.85)
    }

    func testRapidVolumeAndMuteStressBombardment() {
        let item = WallpaperItem(title: "VolStress", type: .video, pathOrURL: "/dummy.mp4", volume: 0.5, isMuted: false)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        // 1,000 rapid volume & mute adjustments
        for i in 0..<1000 {
            let nextMute = (i % 2 == 0)
            let nextVol = Float(i % 100) / 100.0

            engine.volume = nextVol
            engine.isMuted = nextMute

            XCTAssertEqual(engine.isMuted, nextMute)
            XCTAssertEqual(engine.player.isMuted, nextMute)
            XCTAssertEqual(engine.volume, nextVol, accuracy: 0.001)
            XCTAssertEqual(engine.player.volume, nextVol, accuracy: 0.001)
        }
    }

    // MARK: - 3. Rapid Play / Pause Cycling Tests

    func testRapidPlayPause100CyclesMaintainsConsistentState() async throws {
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            XCTFail("Sample loop video missing at \(sampleVideoURL.path)")
            return
        }

        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "RapidToggle", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.count, 0)

        // 100 rapid toggles
        for cycle in 1...100 {
            engine.play()
            XCTAssertTrue(engine.isPlaying, "Cycle \(cycle): isPlaying must be true after play()")
            XCTAssertEqual(delegate.stateChanges.last?.isPlaying, true)

            engine.pause()
            XCTAssertFalse(engine.isPlaying, "Cycle \(cycle): isPlaying must be false after pause()")
            XCTAssertEqual(delegate.stateChanges.last?.isPlaying, false)
        }

        XCTAssertEqual(delegate.stateChanges.count, 200, "Delegate must have received exactly 200 state changes")
        XCTAssertFalse(engine.isPlaying)
    }

    func testConsecutiveRedundantPlayCallsAreIdempotent() {
        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "IdempotentPlay", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        // Call play() 20 times consecutively
        for _ in 0..<20 {
            engine.play()
        }

        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.count, 1, "Redundant play() calls must not trigger multiple delegate events")
    }

    func testConsecutiveRedundantPauseCallsAreIdempotent() {
        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "IdempotentPause", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        engine.play()
        XCTAssertEqual(delegate.stateChanges.count, 1)

        // Call pause() 20 times consecutively
        for _ in 0..<20 {
            engine.pause()
        }

        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.count, 2, "Redundant pause() calls must not trigger multiple delegate events")
    }

    // MARK: - 4. Lifecycle Teardown & Resource Dismantling Tests

    func testFullLifecycleTerminationDismantlesResourcesCleanly() {
        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "TermDismantle", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)

        engine.play()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertNotNil(engine.looper)
        XCTAssertNotNil((engine.view as? VideoPlayerView)?.playerLayer.player)

        // Terminate
        engine.terminate()

        // Verify post-termination invariants
        XCTAssertTrue(engine.isTerminated, "isTerminated must be true")
        XCTAssertFalse(engine.isPlaying, "isPlaying must be false after terminate")
        XCTAssertNil(engine.looper, "Looper must be set to nil after terminate")
        XCTAssertNil((engine.view as? VideoPlayerView)?.playerLayer.player, "playerLayer.player must be detached")
        XCTAssertEqual(engine.player.items().count, 0, "player items must be completely emptied")

        // Post-termination calls must be no-ops
        engine.play()
        XCTAssertFalse(engine.isPlaying, "play() after terminate must be a no-op")

        engine.pause()
        XCTAssertFalse(engine.isPlaying, "pause() after terminate must be a no-op")

        // Redundant terminate calls must be idempotent
        for _ in 0..<10 {
            engine.terminate()
            XCTAssertTrue(engine.isTerminated)
        }
    }

    func testRapidEngineCreationAndTeardownChurn() {
        // Create and immediately terminate 50 engines in rapid succession
        for i in 1...50 {
            let item = WallpaperItem(title: "Churn_\(i)", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item)
            engine.play()
            XCTAssertTrue(engine.isPlaying)
            engine.terminate()
            XCTAssertTrue(engine.isTerminated)
            XCTAssertFalse(engine.isPlaying)
            XCTAssertNil(engine.looper)
        }
    }

    func testEngineDeinitTriggersTermination() async throws {
        weak var weakEngineRef: VideoWallpaperEngine?

        autoreleasepool {
            let item = WallpaperItem(title: "DeinitTest", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item)
            weakEngineRef = engine
            engine.play()
            XCTAssertTrue(engine.isPlaying)
            engine.terminate()
            XCTAssertTrue(engine.isTerminated)
        }

        // Allow cooperative thread pool and runloop cycles to complete cleanup
        for _ in 0..<10 {
            if weakEngineRef == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNil(weakEngineRef, "Engine must be deallocated without retain cycle after terminate")
    }

    func testEngineDeinitTriggersAutomaticTermination() async throws {
        weak var weakEngineRef: VideoWallpaperEngine?

        autoreleasepool {
            let item = WallpaperItem(title: "DeinitAuto", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item)
            weakEngineRef = engine
            engine.play()
            XCTAssertTrue(engine.isPlaying)
            // Leave scope without calling terminate() explicitly; deinit handles teardown
        }

        // Allow cooperative thread pool and runloop cycles to complete cleanup
        for _ in 0..<10 {
            if weakEngineRef == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNil(weakEngineRef, "Engine must be deallocated and cleaned up via deinit when leaving scope")
    }







    // MARK: - 5. Looping Mechanics & Simulation Tests

    func testSimulateLoopIterationIncrementsLoopCountOnlyWhenPlaying() {
        let item = WallpaperItem(title: "LoopSim", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        XCTAssertEqual(engine.loopCount, 0)

        // When paused, simulateLoopIteration must do nothing
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 0, "Loop count must not advance when paused")

        // When playing, simulateLoopIteration must advance count
        engine.play()
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 1)

        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 2)

        engine.pause()
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 2, "Loop count must freeze after pause")

        engine.terminate()
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 2, "Loop count must not advance after terminate")
    }

    func testVideoPlayerViewBackingLayerIntegrity() {
        let frame = NSRect(x: 10, y: 20, width: 1280, height: 720)
        let view = VideoPlayerView(frame: frame)

        XCTAssertTrue(view.wantsLayer)
        XCTAssertTrue(view.layer is AVPlayerLayer)
        XCTAssertEqual(view.playerLayer.videoGravity, .resizeAspectFill)
        XCTAssertEqual(view.autoresizingMask, [.width, .height])
    }

    func testSampleVideoDurationResolution() async throws {
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            XCTFail("Sample loop video missing at \(sampleVideoURL.path)")
            return
        }

        let item = WallpaperItem(title: "SampleAsset", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        // Allow async Task to load duration
        for _ in 0..<20 {
            if engine.duration > 0.0 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertGreaterThan(engine.duration, 0.0, "Sample video duration should resolve to > 0.0s")
    }

    func testSymlinkToVideoHandling() throws {
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            XCTFail("Sample loop video missing at \(sampleVideoURL.path)")
            return
        }

        // 1. Valid symlink pointing to real video
        let validSymlink = tempDirectory.appendingPathComponent("symlink_\(UUID().uuidString).mp4")
        try FileManager.default.createSymbolicLink(at: validSymlink, withDestinationURL: sampleVideoURL)

        let validItem = WallpaperItem(title: "SymlinkValid", type: .video, pathOrURL: validSymlink.path)
        let validEngine = VideoWallpaperEngine(item: validItem)
        defer { validEngine.terminate() }

        XCTAssertFalse(validEngine.hasError, "Valid symlink to video must be loaded cleanly without error")
        validEngine.play()
        XCTAssertTrue(validEngine.isPlaying)

        // 2. Broken symlink pointing to nonexistent target
        let brokenSymlink = tempDirectory.appendingPathComponent("broken_\(UUID().uuidString).mp4")
        let nonExistentTarget = tempDirectory.appendingPathComponent("deleted_\(UUID().uuidString).mp4")
        try FileManager.default.createSymbolicLink(at: brokenSymlink, withDestinationURL: nonExistentTarget)

        let delegate = MockEngineDelegate()
        let brokenItem = WallpaperItem(title: "SymlinkBroken", type: .video, pathOrURL: brokenSymlink.path)
        let brokenEngine = VideoWallpaperEngine(item: brokenItem, delegate: delegate)
        defer { brokenEngine.terminate() }

        XCTAssertTrue(brokenEngine.hasError, "Broken symlink must raise an error")
        XCTAssertFalse(brokenEngine.isPlaying)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first?.error as? VideoEngineError, .missingFile(brokenSymlink))
    }

    func testRapidPlayPause500CyclesExtremeStress() {
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            XCTFail("Sample loop video missing at \(sampleVideoURL.path)")
            return
        }

        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "Rapid500", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        let start = CACurrentMediaTime()
        for _ in 1...500 {
            engine.play()
            XCTAssertTrue(engine.isPlaying)
            engine.pause()
            XCTAssertFalse(engine.isPlaying)
        }
        let elapsed = CACurrentMediaTime() - start


        XCTAssertEqual(delegate.stateChanges.count, 1000)
        XCTAssertFalse(engine.isPlaying)
        print("500 rapid play/pause cycles completed in \(String(format: "%.3f", elapsed))s")
    }

    func testMultipleConcurrentVideoEnginesIsolation() {
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            XCTFail("Sample loop video missing at \(sampleVideoURL.path)")
            return
        }

        // Simulate 4 displays with independent engines
        var engines: [VideoWallpaperEngine] = []
        var delegates: [MockEngineDelegate] = []

        for i in 1...4 {
            let del = MockEngineDelegate()
            delegates.append(del)
            let item = WallpaperItem(title: "Screen_\(i)", type: .video, pathOrURL: sampleVideoURL.path, volume: Float(i) * 0.2, isMuted: i % 2 == 0)
            let engine = VideoWallpaperEngine(item: item, delegate: del)
            engines.append(engine)
        }
        defer {
            for engine in engines { engine.terminate() }
        }

        // Start all 4
        for engine in engines { engine.play() }
        for (i, engine) in engines.enumerated() {
            XCTAssertTrue(engine.isPlaying)
            XCTAssertEqual(delegates[i].stateChanges.count, 1)
        }

        // Pause screen 2 only
        engines[1].pause()
        XCTAssertTrue(engines[0].isPlaying)
        XCTAssertFalse(engines[1].isPlaying)
        XCTAssertTrue(engines[2].isPlaying)
        XCTAssertTrue(engines[3].isPlaying)

        // Modify volume on screen 3 only
        engines[2].volume = 0.95
        XCTAssertEqual(engines[2].volume, 0.95)
        XCTAssertEqual(engines[0].volume, 0.2, accuracy: 0.01)

        // Terminate screen 4 only
        engines[3].terminate()
        XCTAssertTrue(engines[3].isTerminated)
        XCTAssertFalse(engines[0].isTerminated)
        XCTAssertFalse(engines[1].isTerminated)
        XCTAssertFalse(engines[2].isTerminated)
    }

    func testMemoryStabilityUnderRepeatedEngineInstantiation() {
        guard FileManager.default.fileExists(atPath: sampleVideoURL.path) else {
            XCTFail("Sample loop video missing at \(sampleVideoURL.path)")
            return
        }

        func getResidentMemoryBytes() -> UInt64 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return kerr == KERN_SUCCESS ? info.resident_size : 0
        }

        // Warm up
        for _ in 0..<5 {
            let item = WallpaperItem(title: "Warmup", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item)
            engine.play()
            engine.terminate()
        }

        let memoryBefore = getResidentMemoryBytes()

        // Create and terminate 100 engines
        for i in 1...100 {
            let item = WallpaperItem(title: "Stress_\(i)", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item)
            engine.play()
            engine.pause()
            engine.simulateLoopIteration()
            engine.terminate()
        }

        let memoryAfter = getResidentMemoryBytes()
        let growthMB = Double(Int64(memoryAfter) - Int64(memoryBefore)) / (1024 * 1024)
        print("Memory before: \(memoryBefore / (1024*1024)) MB, after: \(memoryAfter / (1024*1024)) MB, delta: \(growthMB) MB")

        // In macOS, resident memory growth over 100 engine creations should remain well under 25 MB
        XCTAssertLessThan(growthMB, 25.0, "Resident memory growth must not leak (> 25MB)")
    }

    // MARK: - 6. Specific M3 Challenge Task Verification Suite

    func testInvalidContainerHeadersFailSynchronouslyWithCorruptFile() throws {
        struct TestCase {
            let name: String
            let data: Data
        }

        let testCases: [TestCase] = [
            TestCase(name: "1-byte", data: Data([0x00])),
            TestCase(name: "6-byte header", data: Data([0x00, 0x00, 0x00, 0x06, 0x66, 0x74])),
            TestCase(name: "7-byte header", data: Data([0x00, 0x00, 0x00, 0x07, 0x66, 0x74, 0x79])),
            TestCase(name: "Invalid FourCC ABCD", data: Data([0x00, 0x00, 0x00, 0x08, 0x41, 0x42, 0x43, 0x44])),
            TestCase(name: "Invalid FourCC DEADBEEF", data: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])),
            TestCase(name: "Truncated ftyp boxSize 8 (< 16)", data: Data([0x00, 0x00, 0x00, 0x08, 0x66, 0x74, 0x79, 0x70])),
            TestCase(name: "Truncated ftyp boxSize 12 (< 16)", data: Data([0x00, 0x00, 0x00, 0x0C, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])),
            TestCase(name: "Truncated ftyp boxSize 24 in 10-byte file", data: Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73])),
            TestCase(name: "Illegal boxSize 5 in 2..<8 range", data: Data([0x00, 0x00, 0x00, 0x05, 0x66, 0x74, 0x79, 0x70]))
        ]

        for tc in testCases {
            let fileURL = tempDirectory.appendingPathComponent("invalid_hdr_\(UUID().uuidString).mp4")
            try tc.data.write(to: fileURL)

            let delegate = MockEngineDelegate()
            let item = WallpaperItem(title: tc.name, type: .video, pathOrURL: fileURL.path)
            let engine = VideoWallpaperEngine(item: item, delegate: delegate)
            defer { engine.terminate() }

            XCTAssertTrue(engine.hasError, "Case '\(tc.name)' must synchronously set hasError = true")
            XCTAssertFalse(engine.isPlaying, "Case '\(tc.name)' must not be playing")
            XCTAssertEqual(delegate.errors.count, 1, "Case '\(tc.name)' must notify delegate of exactly 1 error synchronously")
            XCTAssertEqual(
                delegate.errors.first?.error as? VideoEngineError,
                .corruptFile(fileURL),
                "Case '\(tc.name)' must fail with .corruptFile"
            )

            // Calling play() must remain a no-op
            engine.play()
            XCTAssertFalse(engine.isPlaying)
        }
    }

    func testRealMOVPlaybackAndLooping() async throws {
        let movURL = tempDirectory.appendingPathComponent("sample_\(UUID().uuidString).mov")

        // Generate a valid QuickTime MOV file using AVAssetWriter
        let writer = try AVAssetWriter(outputURL: movURL, fileType: .mov)
        let width = 320
        let height = 180
        let fps: Int32 = 24
        let duration: Double = 0.5
        let totalFrames = Int(Double(fps) * duration)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32ARGB,
                sourcePixelBufferAttributes as CFDictionary,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                XCTFail("Failed to allocate pixel buffer")
                return
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer),
               let ctx = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
               ) {
                ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let pt = CMTime(value: CMTimeValue(frame), timescale: fps)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: pt))
        }

        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, AVAssetWriter.Status.completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movURL.path))

        // Test real playback and looping with VideoWallpaperEngine
        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "RealMOV", type: .video, pathOrURL: movURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertFalse(engine.hasError, "Valid MOV file must not have error")
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNotNil(engine.looper, "AVPlayerLooper must be initialized for valid MOV")

        // Play
        engine.play()
        XCTAssertTrue(engine.isPlaying, "MOV engine must be playing after play()")
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, true)

        // Loop mechanics
        XCTAssertEqual(engine.loopCount, 0)
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 1, "Simulated loop must advance loopCount")

        // Pause
        engine.pause()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, false)

        // Terminate
        engine.terminate()
        XCTAssertTrue(engine.isTerminated)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(engine.looper)
    }

    func testExhaustiveExtremeVolumeMathFuzzing() {
        let item = WallpaperItem(title: "VolMath", type: .video, pathOrURL: sampleVideoURL.path)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        // 1. Explicit extreme values
        let explicitExtremes: [Float] = [
            Float.nan,
            -Float.nan,
            Float.infinity,
            -Float.infinity,
            -0.0,
            0.0,
            1.0,
            -1.0,
            2.0,
            -1e20,
            1e20,
            Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude,
            Float.leastNormalMagnitude,
            -Float.leastNormalMagnitude,
            Float.leastNonzeroMagnitude,
            -Float.leastNonzeroMagnitude
        ]

        for val in explicitExtremes {
            let clamped = VideoWallpaperEngine.clampVolume(val)
            XCTAssertFalse(clamped.isNaN, "Clamped value for \(val) must not be NaN")
            XCTAssertFalse(clamped.isInfinite, "Clamped value for \(val) must not be Infinite")
            XCTAssertGreaterThanOrEqual(clamped, 0.0, "Clamped value for \(val) must be >= 0.0")
            XCTAssertLessThanOrEqual(clamped, 1.0, "Clamped value for \(val) must be <= 1.0")

            if val.isNaN || val.isInfinite || val < 0.0 {
                XCTAssertEqual(clamped, 0.0, "Non-finite or negative value \(val) must clamp to 0.0")
            } else if val > 1.0 {
                XCTAssertEqual(clamped, 1.0, "Value \(val) > 1.0 must clamp to 1.0")
            }

            // Apply directly to engine volume setter
            engine.volume = val
            XCTAssertFalse(engine.volume.isNaN)
            XCTAssertFalse(engine.volume.isInfinite)
            XCTAssertGreaterThanOrEqual(engine.volume, 0.0)
            XCTAssertLessThanOrEqual(engine.volume, 1.0)
            XCTAssertEqual(engine.volume, clamped)
            XCTAssertEqual(engine.player.volume, clamped)
        }

        // 2. Fuzz 10,000 arbitrary bit patterns (including signaling NaNs, quiet NaNs, subnormals, denormals)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<10_000 {
            let bitPattern = rng.next() as UInt32
            let floatVal = Float(bitPattern: bitPattern)
            let clamped = VideoWallpaperEngine.clampVolume(floatVal)

            XCTAssertFalse(clamped.isNaN, "Fuzzed bitPattern 0x\(String(bitPattern, radix: 16)) produced NaN")
            XCTAssertFalse(clamped.isInfinite, "Fuzzed bitPattern 0x\(String(bitPattern, radix: 16)) produced Infinite")
            XCTAssertGreaterThanOrEqual(clamped, 0.0)
            XCTAssertLessThanOrEqual(clamped, 1.0)
        }
    }

    func testDeallocationInvarianceUnderActivePlaybackAndObservers() async throws {
        weak var weakEngineExplicit: VideoWallpaperEngine?
        weak var weakEngineAuto: VideoWallpaperEngine?

        // Scenario A: Active playback -> terminate -> deinit
        autoreleasepool {
            let delegate = MockEngineDelegate()
            let item = WallpaperItem(title: "DeallocA", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item, delegate: delegate)
            weakEngineExplicit = engine

            engine.play()
            XCTAssertTrue(engine.isPlaying)
            XCTAssertNotNil(engine.looper)

            engine.terminate()
            XCTAssertTrue(engine.isTerminated)
        }

        for _ in 0..<10 {
            if weakEngineExplicit == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(weakEngineExplicit, "Engine must deallocate cleanly after terminate()")

        // Scenario B: Active playback -> out of scope without terminate (automatic deinit teardown)
        autoreleasepool {
            let delegate = MockEngineDelegate()
            let item = WallpaperItem(title: "DeallocB", type: .video, pathOrURL: sampleVideoURL.path)
            let engine = VideoWallpaperEngine(item: item, delegate: delegate)
            weakEngineAuto = engine

            engine.play()
            XCTAssertTrue(engine.isPlaying)
            XCTAssertNotNil(engine.looper)
            // Leave scope without calling terminate(); deinit must clean up
        }

        for _ in 0..<10 {
            if weakEngineAuto == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(weakEngineAuto, "Engine must deallocate cleanly via deinit teardown without explicit terminate()")
    }
}


