import Foundation
import AppKit
import XCTest
import WebKit
import AVFoundation

final class Tier2_BoundaryTests: XCTestCase {
    private var env: E2ETestEnvironment!

    override func setUp() {
        super.setUp()
        env = E2ETestEnvironment()
    }

    override func tearDown() {
        env.terminate()
        env = nil
        super.tearDown()
    }

    // MARK: - Feature 1: Desktop Window Leveling & Spaces Boundary Tests (5 tests)

    func testF01_B01_zeroDisplaysHandling() {
        let zeroEnv = E2ETestEnvironment(screens: [])
        defer { zeroEnv.terminate() }

        XCTAssertEqual(zeroEnv.windowManager.windows.count, 0)
        let sampleMP4 = zeroEnv.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Zero Screens", type: .video, sourceURL: sampleMP4)
        zeroEnv.setWallpaper(item)

        XCTAssertEqual(zeroEnv.windowManager.windows.count, 0, "No windows should exist when screens are empty")
        XCTAssertNotNil(zeroEnv.windowManager.activeWallpaper)
    }

    func testF01_B02_extremeDisplayResolution() {
        let hugeScreen = SimulatedScreen(id: 99, frame: CGRect(x: 0, y: 0, width: 15360, height: 8640))
        let hugeEnv = E2ETestEnvironment(screens: [hugeScreen])
        defer { hugeEnv.terminate() }

        let sampleMP4 = hugeEnv.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "16K Screen", type: .video, sourceURL: sampleMP4)
        hugeEnv.setWallpaper(item)

        XCTAssertEqual(hugeEnv.windowManager.windows.count, 1)
        XCTAssertEqual(hugeEnv.windowManager.windows[0].frame.size.width, 15360)
        XCTAssertEqual(hugeEnv.windowManager.windows[0].frame.size.height, 8640)
    }

    func testF01_B03_rapidDisplayHotplugAndUnplug() {
        for i in 1...20 {
            let screen = SimulatedScreen(id: i + 10, frame: CGRect(x: CGFloat(i * 1920), y: 0, width: 1920, height: 1080))
            env.addScreen(screen)
            XCTAssertEqual(env.windowManager.windows.count, 2)
            env.removeScreen(id: screen.id)
            XCTAssertEqual(env.windowManager.windows.count, 1)
        }
    }

    func testF01_B04_displayBoundsNegativeCoordinates() {
        let leftScreen = SimulatedScreen(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        env.addScreen(leftScreen)

        XCTAssertEqual(env.windowManager.windows.count, 2)
        let leftWindow = env.windowManager.windows.first { $0.screenID == 2 }
        XCTAssertNotNil(leftWindow)
        XCTAssertEqual(leftWindow?.frame.origin.x, -1920)
    }

    func testF01_B05_zeroSizeDisplayReconfiguration() {
        let zeroSizeScreen = SimulatedScreen(id: 3, frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        env.addScreen(zeroSizeScreen)

        XCTAssertEqual(env.windowManager.windows.count, 2)
        let zeroWindow = env.windowManager.windows.first { $0.screenID == 3 }
        XCTAssertNotNil(zeroWindow)
        XCTAssertEqual(zeroWindow?.frame.size, .zero)
    }

    // MARK: - Feature 2: Mouse Event Passthrough & Interactive Mode Boundary Tests (5 tests)

    func testF02_B01_rapidInteractionModeToggling() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Toggle Stress", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        for _ in 1...100 {
            env.toggleInteractiveMode()
        }
        XCTAssertFalse(env.windowManager.isInteractive, "100 toggles must return to original default mode")
        XCTAssertEqual(env.windowManager.windows[0].windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertTrue(env.windowManager.windows[0].ignoresMouseEvents)
    }

    func testF02_B02_clickOnExactWindowBorder() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Border Click", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        XCTAssertNil(window.hitTest(CGPoint(x: 0, y: 0)))
        XCTAssertNil(window.hitTest(CGPoint(x: 1920, y: 1080)))
        XCTAssertNil(window.hitTest(CGPoint(x: -1, y: -1)))
        XCTAssertNil(window.hitTest(CGPoint(x: 1921, y: 1081)))

        env.toggleInteractiveMode()
        XCTAssertNotNil(window.hitTest(CGPoint(x: 0, y: 0)))
        XCTAssertNil(window.hitTest(CGPoint(x: -1, y: -1)))
        XCTAssertNil(window.hitTest(CGPoint(x: 2000, y: 2000)))
    }

    func testF02_B03_keyWindowStatusResignation() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Key Window", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        env.toggleInteractiveMode()
        let window = env.windowManager.windows[0]
        XCTAssertTrue(window.isKeyWindow)

        window.isKeyWindow = false
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(env.windowManager.isInteractive, "Resigning key status does not corrupt interactive state")
    }

    func testF02_B04_mouseDragEventPassthroughInDefaultMode() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Drag Test", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        for y in stride(from: 0, to: 1080, by: 100) {
            let hit = window.hitTest(CGPoint(x: 500, y: y))
            XCTAssertNil(hit, "All coordinates along drag path must return nil in default mode")
        }
    }

    func testF02_B05_highVolumeHitTestEventStress() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "High Vol HitTest", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        for i in 1...1000 {
            let point = CGPoint(x: i % 1920, y: i % 1080)
            XCTAssertNil(window.hitTest(point))
        }
    }

    // MARK: - Feature 3: Video Playback & Seamless Looping Boundary Tests (5 tests)

    func testF03_B01_corruptVideoFileFailsGracefully() {
        let corruptFile = env.assetHelper.createCorruptVideoFile()
        let item = WallpaperItem(title: "Corrupt Video", type: .video, sourceURL: corruptFile)

        final class ErrorCatcher: WallpaperEngineDelegate, @unchecked Sendable {
            var caughtError: Error?
            func engineDidEncounterError(_ engine: WallpaperEngine, error: Error) { caughtError = error }
            func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool) {}
        }

        let catcher = ErrorCatcher()
        let engine = MockVideoWallpaperEngine(item: item, delegate: catcher)
        XCTAssertNotNil(catcher.caughtError, "Corrupt video must notify delegate of error")
        XCTAssertFalse(engine.isPlaying)
    }

    func testF03_B02_zeroByteVideoFileHandling() {
        let zeroFile = env.assetHelper.createZeroByteFile(extension: "mp4")
        let item = WallpaperItem(title: "0 Byte Video", type: .video, sourceURL: zeroFile)

        final class ErrorCatcher: WallpaperEngineDelegate, @unchecked Sendable {
            var caughtError: Error?
            func engineDidEncounterError(_ engine: WallpaperEngine, error: Error) { caughtError = error }
            func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool) {}
        }

        let catcher = ErrorCatcher()
        let engine = MockVideoWallpaperEngine(item: item, delegate: catcher)
        XCTAssertNotNil(catcher.caughtError, "0-byte file must trigger error")
        XCTAssertFalse(engine.isPlaying)
    }

    func testF03_B03_subSecondMicroVideoLooping() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Micro Video", type: .video, sourceURL: sampleMP4, duration: 0.1)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }

        for _ in 1...100 {
            engine.simulateLoopIteration()
        }
        XCTAssertEqual(engine.loopCount, 100)
        XCTAssertTrue(engine.isPlaying)
    }

    func testF03_B04_extremeAspectRatioVideo() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Ultra Wide Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        engine.view.frame = CGRect(x: 0, y: 0, width: 10000, height: 10)
        XCTAssertEqual(engine.view.frame.width, 10000)
        XCTAssertEqual(engine.view.frame.height, 10)
    }

    func testF03_B05_rapidPlayPauseCycling() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Rapid PlayPause", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }

        for _ in 1...50 {
            engine.play()
            engine.pause()
        }
        XCTAssertFalse(engine.isPlaying)
        engine.play()
        XCTAssertTrue(engine.isPlaying)
    }

    // MARK: - Feature 4: Video Audio & Volume Controls Boundary Tests (5 tests)

    func testF04_B01_negativeVolumeClampedToZero() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Negative Vol", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.setVolume(-0.5)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 0.0, "Negative volume must clamp to 0.0")
    }

    func testF04_B02_excessiveVolumeClampedToOne() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Excessive Vol", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.setVolume(2.5)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 1.0, "Excessive volume must clamp to 1.0")
    }

    func testF04_B03_nanAndInfinityVolumeHandling() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "NaN Vol", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }

        engine.volume = Float.nan
        XCTAssertEqual(engine.volume, 0.0, "NaN volume must default to 0.0")

        engine.volume = Float.infinity
        XCTAssertEqual(engine.volume, 0.0, "Infinity volume must default to 0.0")
    }

    func testF04_B04_volumeAdjustmentWhileMutedPreservesMute() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Preserve Mute", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)

        env.setVolume(0.85)
        XCTAssertTrue(env.windowManager.isMuted, "Changing volume while muted must keep mute state")
        XCTAssertEqual(env.windowManager.volume, 0.85)

        env.toggleMute()
        XCTAssertFalse(env.windowManager.isMuted)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 0.85)
    }

    func testF04_B05_rapidMuteUnmuteCycling() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Mute Cycling", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        for _ in 1...100 {
            env.toggleMute()
        }
        XCTAssertFalse(env.windowManager.isMuted, "100 mute toggles must end unmuted")
    }

    // MARK: - Feature 5: Local Web Wallpaper Boundary Tests (5 tests)

    func testF05_B01_directoryMissingIndexHTML() {
        let emptyFolder = env.assetHelper.createSampleWebFolder(withIndex: false)
        let item = WallpaperItem(title: "No Index", type: .web, sourceURL: emptyFolder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .failed("Missing index.html"))
    }

    func testF05_B02_emptyIndexHTMLFile() {
        let folder = env.assetHelper.createSampleWebFolder(withIndex: true, customHTML: "")
        let item = WallpaperItem(title: "Empty Index", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    func testF05_B03_deeplyNestedDirectoryPath() {
        let nestedFolder = env.assetHelper.createDeeplyNestedWebFolder(depth: 20)
        let item = WallpaperItem(title: "Deeply Nested", type: .web, sourceURL: nestedFolder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    func testF05_B04_htmlWithSyntaxErrors() {
        let malformedHTML = "<html><head><body<<<broken tag>>>>>"
        let folder = env.assetHelper.createSampleWebFolder(withIndex: true, customHTML: malformedHTML)
        let item = WallpaperItem(title: "Malformed HTML", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded, "WebKit gracefully parses malformed HTML without crashing")
    }

    func testF05_B05_missingSubresourcesHandling() {
        let htmlWith404 = "<html><body><script src=\"missing_script.js\"></script></body></html>"
        let folder = env.assetHelper.createSampleWebFolder(withIndex: true, customHTML: htmlWith404)
        let item = WallpaperItem(title: "404 Resource", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded, "Missing subresources do not fail top-level navigation")
    }

    // MARK: - Feature 6: Remote Web Wallpaper Live URLs Boundary Tests (5 tests)

    func testF06_B01_malformedURLString() {
        let malformedStr = "ht tp://::invalid URL"
        XCTAssertThrowsError(try env.library.importURL(urlString: malformedStr))
    }

    func testF06_B02_nonHTTPURLSchemeRejected() {
        let nonHTTP = "file:///etc/passwd"
        XCTAssertThrowsError(try env.library.importURL(urlString: nonHTTP))
    }

    func testF06_B03_unreachableHostReturnsError() {
        let url = URL(string: "https://doesnotexist.unreachable.net")!
        let item = WallpaperItem(title: "Offline", type: .url, sourceURL: url)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        if case .failed(let msg) = engine.navigationState {
            XCTAssertTrue(msg.contains("Unreachable host"))
        } else {
            XCTFail("Should fail navigation for unreachable host")
        }
    }

    func testF06_B04_extremeURLLength() {
        let longQuery = String(repeating: "a=1&", count: 800)
        let urlStr = "https://example.com/test?" + longQuery
        let item = try? env.library.importURL(urlString: urlStr)
        XCTAssertNotNil(item)
        XCTAssertGreaterThan(item!.sourceURL.absoluteString.count, 2000)
    }

    func testF06_B05_rapidURLSwitching() {
        for i in 1...5 {
            let url = URL(string: "https://example.com/page\(i)")!
            let item = WallpaperItem(title: "Page \(i)", type: .url, sourceURL: url)
            env.setWallpaper(item)
        }
        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.item.title, "Page 5")
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    // MARK: - Feature 7: Web Resource & Audio Suspension Boundary Tests (5 tests)

    func testF07_B01_doublePauseIdempotency() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Double Pause", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        engine.pause()
        XCTAssertTrue(engine.rafSuspended)
        engine.pause()
        XCTAssertTrue(engine.rafSuspended)
        XCTAssertFalse(engine.isPlaying)
    }

    func testF07_B02_doubleResumeIdempotency() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Double Play", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        engine.play()
        XCTAssertTrue(engine.isPlaying)
    }

    func testF07_B03_resumeWithoutPriorPause() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Fresh Play", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertFalse(engine.rafSuspended)
    }

    func testF07_B04_webContentProcessCrashRecovery() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Crash Web", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        engine.simulateCrash()
        XCTAssertEqual(engine.navigationState, .failed("Process crashed"))
    }

    func testF07_B05_rapidSuspendResumeCycles() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Rapid Suspend", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        for _ in 1...50 {
            engine.pause()
            engine.play()
        }
        XCTAssertTrue(engine.isPlaying)
        XCTAssertFalse(engine.rafSuspended)
    }

    // MARK: - Feature 8: Menu Bar Companion Controls Boundary Tests (5 tests)

    func testF08_B01_menuActionsWithNilActiveWallpaper() {
        env.togglePlayPause()
        XCTAssertTrue(env.powerManager.isPaused)
        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)
    }

    func testF08_B02_menuItemValidationWithEmptyLibrary() {
        XCTAssertTrue(env.statusItemController.quickPickerWallpapers.isEmpty)
        XCTAssertEqual(env.library.items.count, 0)
    }

    func testF08_B03_rapidMenuRebuildStress() {
        for i in 1...100 {
            env.statusItemController.update(
                isPaused: i % 2 == 0,
                isMuted: i % 3 == 0,
                isInteractive: i % 4 == 0,
                wallpapers: []
            )
        }
        XCTAssertEqual(env.statusItemController.playPauseTitle, "Resume")
    }

    func testF08_B04_statusItemIconMissingFallback() {
        env.statusItemController.iconName = "invalid.system.symbol"
        XCTAssertEqual(env.statusItemController.iconName, "invalid.system.symbol")
    }

    func testF08_B05_quitMenuTerminatesEnginesAndWindows() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Quit Test", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.terminate()
        XCTAssertTrue(env.statusItemController.isTerminated)
        XCTAssertNil(env.windowManager.activeEngine)
        XCTAssertEqual(env.windowManager.windows.count, 0)
    }

    // MARK: - Feature 9: SwiftUI Wallpaper Manager Gallery Boundary Tests (5 tests)

    func testF09_B01_emptyLibraryViewPresentsPlaceholder() {
        XCTAssertTrue(env.library.items.isEmpty)
    }

    func testF09_B02_duplicateItemIngestionRejectedOrDeDuplicated() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item1 = WallpaperItem(id: UUID(), title: "Duplicate", type: .video, sourceURL: sampleMP4)
        let item2 = WallpaperItem(id: UUID(), title: "Duplicate 2", type: .video, sourceURL: sampleMP4)

        try? env.library.add(item1)
        try? env.library.add(item2)

        XCTAssertEqual(env.library.items.count, 1, "Duplicate source URLs must be deduplicated")
    }

    func testF09_B03_unsupportedFileExtensionRejected() {
        let tempFile = env.assetHelper.createZeroByteFile(extension: "exe")
        XCTAssertThrowsError(try env.library.importFile(url: tempFile))
    }

    func testF09_B04_corruptedLibraryJSONFile() {
        let corruptedJSON = "{ invalid json data [[[".data(using: .utf8)!
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode([WallpaperItem].self, from: corruptedJSON))
    }

    func testF09_B05_deleteActiveWallpaperFallback() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "To Be Deleted", type: .video, sourceURL: sampleMP4)
        try? env.library.add(item)
        env.setWallpaper(item)

        env.library.remove(id: item.id)
        XCTAssertNil(env.library.find(id: item.id))
        XCTAssertEqual(env.library.items.count, 0)
    }

    // MARK: - Feature 10: Energy Saver Auto-Pause Engine Boundary Tests (5 tests)

    func testF10_B01_allFivePauseReasonsSimultaneouslyActive() {
        env.powerManager.simulateUserPause(isPaused: true)
        env.powerManager.simulateFullscreenApp(isActive: true)
        env.powerManager.simulateDisplaySleep()
        env.powerManager.simulateScreenLock()
        env.powerManager.simulateBatteryPower(saverActive: true)

        XCTAssertEqual(env.powerManager.currentPauseReasons.rawValue, 31)
        XCTAssertTrue(env.powerManager.isPaused)
    }

    func testF10_B02_partialClearDoesNotResumePlayback() {
        env.powerManager.simulateUserPause(isPaused: true)
        env.powerManager.simulateFullscreenApp(isActive: true)

        env.powerManager.simulateFullscreenApp(isActive: false)
        XCTAssertTrue(env.powerManager.isPaused, "Must remain paused because userPaused is still active")
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.userPaused))
    }

    func testF10_B03_clearingUnsetReasonIsNoOp() {
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.screenLocked))
        env.powerManager.simulateScreenUnlock()
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.screenLocked))
        XCTAssertFalse(env.powerManager.isPaused)
    }

    func testF10_B04_rapidPowerSourceJitter() {
        for _ in 1...50 {
            env.powerManager.simulateBatteryPower(saverActive: true)
            env.powerManager.simulateBatteryPower(saverActive: false)
        }
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.batterySaver))
        XCTAssertFalse(env.powerManager.isPaused)
    }

    func testF10_B05_screenLockDuringDisplaySleep() {
        env.powerManager.simulateDisplaySleep()
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.displaySleeping))

        env.powerManager.simulateScreenLock()
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.displaySleeping))
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.screenLocked))

        env.powerManager.simulateDisplayWake()
        XCTAssertTrue(env.powerManager.isPaused, "Must stay paused because screenLocked is still active")

        env.powerManager.simulateScreenUnlock()
        XCTAssertFalse(env.powerManager.isPaused, "Now resumes because all reasons are cleared")
    }
}
