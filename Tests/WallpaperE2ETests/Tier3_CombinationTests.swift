import Foundation
import AppKit
import XCTest
import WebKit
import AVFoundation

final class Tier3_CombinationTests: XCTestCase {
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

    // MARK: - Pairwise Cross-Feature Interactions (10 tests)

    func testF_Comb01_videoLoopingUnderFullscreenOcclusion() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Looping Occlusion", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }

        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 1)
        XCTAssertTrue(engine.isPlaying)

        // Launch fullscreen application
        env.powerManager.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(env.windowManager.isPaused)
        XCTAssertFalse(engine.isPlaying)

        // Exit fullscreen application
        env.powerManager.simulateFullscreenApp(isActive: false)
        XCTAssertFalse(env.windowManager.isPaused)
        XCTAssertTrue(engine.isPlaying)

        // Continue looping seamlessly
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 2)
    }

    func testF_Comb02_interactiveWebWallpaperDuringDisplaySleep() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Interactive Web Sleep", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        // Enter interactive mode
        env.toggleInteractiveMode()
        XCTAssertTrue(env.windowManager.isInteractive)
        let window = env.windowManager.windows[0]
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)
        XCTAssertFalse(window.ignoresMouseEvents)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }

        // Display sleep
        env.powerManager.simulateDisplaySleep()
        XCTAssertTrue(env.windowManager.isPaused)
        XCTAssertTrue(engine.rafSuspended)
        XCTAssertTrue(engine.mediaSuspended)

        // Display wake
        env.powerManager.simulateDisplayWake()
        XCTAssertFalse(env.windowManager.isPaused)
        XCTAssertFalse(engine.rafSuspended)
        XCTAssertFalse(engine.mediaSuspended)
        XCTAssertTrue(env.windowManager.isInteractive, "Interactivity must be preserved across display sleep/wake")
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)
    }

    func testF_Comb03_muteStatePersistenceAcrossWallpaperEngineSwitch() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let videoItem = WallpaperItem(title: "Initial Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(videoItem)

        // Mute active video
        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)

        // Switch to web wallpaper
        let folder = env.assetHelper.createSampleWebFolder()
        let webItem = WallpaperItem(title: "Web Target", type: .web, sourceURL: folder)
        env.setWallpaper(webItem)

        // Verify web engine inherited mute state
        guard let webEngine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertTrue(webEngine.isMuted, "Mute state must persist across wallpaper switches")
        XCTAssertEqual(env.statusItemController.muteTitle, "Unmute")
    }

    func testF_Comb04_multiDisplayHotplugDuringVideoPlayback() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Hotplug Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        XCTAssertEqual(env.windowManager.windows.count, 1)

        // Connect secondary display
        let newScreen = SimulatedScreen(id: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        env.addScreen(newScreen)

        XCTAssertEqual(env.windowManager.windows.count, 2)
        let window2 = env.windowManager.windows.first { $0.screenID == 2 }
        XCTAssertNotNil(window2)
        XCTAssertEqual(window2?.windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertTrue(window2?.ignoresMouseEvents ?? false)
        XCTAssertNotNil(window2?.contentView)

        // Disconnect secondary display
        env.removeScreen(id: 2)
        XCTAssertEqual(env.windowManager.windows.count, 1)
        XCTAssertEqual(env.windowManager.windows[0].screenID, 1)
    }

    func testF_Comb05_userManualPauseMaintainedAcrossScreenLockUnlock() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Manual Pause", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        // User manually pauses
        env.togglePlayPause()
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.userPaused))
        XCTAssertTrue(env.windowManager.isPaused)

        // Screen locks
        env.powerManager.simulateScreenLock()
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.screenLocked))
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.userPaused))

        // Screen unlocks
        env.powerManager.simulateScreenUnlock()
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.screenLocked))
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.userPaused))
        XCTAssertTrue(env.windowManager.isPaused, "Engine must remain paused because user manually paused it")
    }

    func testF_Comb06_batterySaverEngagedWhileAdjustingVolume() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Battery Volume", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        // Switch to battery saver
        env.powerManager.simulateBatteryPower(saverActive: true)
        XCTAssertTrue(env.windowManager.isPaused)

        // Adjust volume while paused on battery
        env.setVolume(0.4)
        XCTAssertEqual(env.windowManager.volume, 0.4, accuracy: 0.001)

        // Reconnect AC power
        env.powerManager.simulateBatteryPower(saverActive: false)
        XCTAssertFalse(env.windowManager.isPaused)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 0.4, accuracy: 0.001, "New volume must apply upon resuming")
        XCTAssertTrue(engine.isPlaying)
    }

    func testF_Comb07_invalidURLIngestionWhileVideoPlaying() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Playing Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying)

        // Attempt ingestion of invalid URL
        XCTAssertThrowsError(try env.library.importURL(urlString: "invalid://bad_scheme"))

        // Active video playback continues unaffected
        XCTAssertTrue(engine.isPlaying, "Failed ingestion must not disrupt active wallpaper playback")
        XCTAssertEqual(env.windowManager.activeWallpaper?.id, item.id)
    }

    func testF_Comb08_interactiveModeToggleDuringFullscreenApp() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Fullscreen Interactive", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        // Fullscreen app launches
        env.powerManager.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(env.windowManager.isPaused)

        // User toggles interactive mode
        env.toggleInteractiveMode()
        XCTAssertTrue(env.windowManager.isInteractive)

        // Fullscreen app exits
        env.powerManager.simulateFullscreenApp(isActive: false)
        XCTAssertFalse(env.windowManager.isPaused)

        let window = env.windowManager.windows[0]
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)
        XCTAssertFalse(window.ignoresMouseEvents)
    }

    func testF_Comb09_rapidSleepWakeCyclingWithWebWallpaper() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Stress Sleep Web", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }

        for _ in 1...20 {
            env.powerManager.simulateDisplaySleep()
            XCTAssertTrue(engine.rafSuspended)
            env.powerManager.simulateDisplayWake()
            XCTAssertFalse(engine.rafSuspended)
        }
        XCTAssertTrue(engine.isPlaying)
        XCTAssertFalse(env.windowManager.isPaused)
    }

    func testF_Comb10_additivePauseMatrixExhaustiveTransitions() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Additive Matrix", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying)

        // Step 1: Add userPaused
        env.powerManager.simulateUserPause(isPaused: true)
        XCTAssertTrue(env.windowManager.isPaused)
        XCTAssertFalse(engine.isPlaying)

        // Step 2: Add fullscreenApp
        env.powerManager.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(env.windowManager.isPaused)

        // Step 3: Add displaySleeping
        env.powerManager.simulateDisplaySleep()
        XCTAssertTrue(env.windowManager.isPaused)

        // Step 4: Add screenLocked
        env.powerManager.simulateScreenLock()
        XCTAssertTrue(env.windowManager.isPaused)

        // Step 5: Add batterySaver
        env.powerManager.simulateBatteryPower(saverActive: true)
        XCTAssertEqual(env.powerManager.currentPauseReasons.rawValue, 31)
        XCTAssertTrue(env.windowManager.isPaused)

        // Remove in reverse order
        env.powerManager.simulateBatteryPower(saverActive: false)
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateScreenUnlock()
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateDisplayWake()
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateFullscreenApp(isActive: false)
        XCTAssertTrue(env.windowManager.isPaused)

        // Final removal: user resumes
        env.powerManager.simulateUserPause(isPaused: false)
        XCTAssertEqual(env.powerManager.currentPauseReasons.rawValue, 0)
        XCTAssertFalse(env.windowManager.isPaused)
        XCTAssertTrue(engine.isPlaying, "Engine must resume only when the very last pause reason is cleared")
    }
}
