import Foundation
import AppKit
import XCTest
import WebKit
import AVFoundation

final class Tier4_ScenarioTests: XCTestCase {
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

    // MARK: - Scenario 1: Full App Lifecycle (F8, F9)
    func testScenario1_fullAppLifecycle() {
        // Step 1: App initializes into menu bar companion with sparkles.tv icon
        XCTAssertEqual(env.statusItemController.iconName, "sparkles.tv")
        XCTAssertFalse(env.statusItemController.isTerminated)

        // Step 2: Library is initialized with default wallpapers
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let sampleItem = WallpaperItem(title: "Default Nature", type: .video, sourceURL: sampleMP4)
        try? env.library.add(sampleItem)
        XCTAssertEqual(env.library.items.count, 1)

        // Step 3: Summon SwiftUI Wallpaper Manager
        env.statusItemController.isManagerOpen = true
        XCTAssertTrue(env.statusItemController.isManagerOpen)

        // Step 4: User selects wallpaper from gallery
        env.setWallpaper(sampleItem)
        XCTAssertEqual(env.windowManager.activeWallpaper?.id, sampleItem.id)
        XCTAssertEqual(env.windowManager.windows.count, 1)
        XCTAssertEqual(env.windowManager.windows[0].windowLevel, CGWindowLevelForKey(.desktopWindow))

        // Step 5: Quit triggered from menu companion
        env.terminate()

        // Step 6: Verify full termination of windows and engines
        XCTAssertTrue(env.statusItemController.isTerminated)
        XCTAssertNil(env.windowManager.activeEngine)
        XCTAssertEqual(env.windowManager.windows.count, 0)
    }

    // MARK: - Scenario 2: Video Wallpaper Workflow (F3, F4, F8)
    func testScenario2_videoWallpaperWorkflow() {
        // Step 1: Ingest sample MP4
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let videoItem = try? env.library.importFile(url: sampleMP4)
        XCTAssertNotNil(videoItem)

        // Step 2: Set as active wallpaper
        env.setWallpaper(videoItem!)
        XCTAssertEqual(env.windowManager.windows[0].windowLevel, CGWindowLevelForKey(.desktopWindow))

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying)

        // Step 3: Verify seamless looping
        XCTAssertEqual(engine.loopCount, 0)
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 1)
        XCTAssertTrue(engine.isPlaying)

        // Step 4: Adjust volume to 0.7
        env.setVolume(0.7)
        XCTAssertEqual(engine.volume, 0.7, accuracy: 0.001)

        // Step 5: Toggle mute via companion menu
        env.toggleMute()
        XCTAssertTrue(engine.isMuted)
        XCTAssertEqual(env.statusItemController.muteTitle, "Unmute")

        // Step 6: Toggle unmute and verify volume restoration
        env.toggleMute()
        XCTAssertFalse(engine.isMuted)
        XCTAssertEqual(engine.volume, 0.7, accuracy: 0.001)
        XCTAssertEqual(env.statusItemController.muteTitle, "Mute")
    }

    // MARK: - Scenario 3: Interactive Web Wallpaper Workflow (F1, F2, F5)
    func testScenario3_interactiveWebWallpaperWorkflow() {
        // Step 1: Ingest local HTML5 folder
        let folder = env.assetHelper.createSampleWebFolder()
        let webItem = try? env.library.importFile(url: folder)
        XCTAssertNotNil(webItem)

        // Step 2: Set active wallpaper - verify default passthrough
        env.setWallpaper(webItem!)
        let window = env.windowManager.windows[0]
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertNil(window.hitTest(CGPoint(x: 300, y: 300)), "Clicks must pass through to Finder")

        // Step 3: Toggle interactive mode ON
        env.toggleInteractiveMode()
        XCTAssertTrue(env.windowManager.isInteractive)
        XCTAssertTrue(env.statusItemController.isInteractiveChecked)

        // Step 4: Verify elevated window level and interactive hit-testing
        let elevatedLevel = CGWindowLevelForKey(.desktopIconWindow) + 1
        XCTAssertEqual(window.windowLevel, elevatedLevel)
        XCTAssertFalse(window.ignoresMouseEvents)

        // Step 5: Simulate user mouse click handled by web view
        let hitView = window.hitTest(CGPoint(x: 300, y: 300))
        XCTAssertNotNil(hitView, "Interactive content view must receive mouse click")

        // Step 6: Toggle interactive mode OFF
        env.toggleInteractiveMode()
        XCTAssertFalse(env.windowManager.isInteractive)
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertNil(window.hitTest(CGPoint(x: 300, y: 300)))
    }

    // MARK: - Scenario 4: Energy Saver Auto-Pause Workflow (F3, F10)
    func testScenario4_energySaverAutoPauseWorkflow() {
        // Step 1: Active video wallpaper playing
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Energy Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying)

        // Step 2: Fullscreen app / game launches
        env.powerManager.simulateFullscreenApp(isActive: true)

        // Step 3: Auto-pause triggers
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertTrue(env.windowManager.isPaused)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(env.statusItemController.playPauseTitle, "Resume")

        // Step 4: Exit fullscreen app back to desktop
        env.powerManager.simulateFullscreenApp(isActive: false)

        // Step 5: Seamless automatic resume
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertFalse(env.windowManager.isPaused)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(env.statusItemController.playPauseTitle, "Pause")
    }

    // MARK: - Scenario 5: Display Sleep & Wake Workflow (F3, F5, F10)
    func testScenario5_displaySleepAndWakeWorkflow() {
        // Step 1: Web canvas wallpaper active and animating
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Canvas Sleep Test", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertFalse(engine.rafSuspended)
        XCTAssertFalse(engine.mediaSuspended)

        // Step 2: macOS dispatches display sleep notification
        env.powerManager.simulateDisplaySleep()

        // Step 3: Auto-pause engages and suspends web engine
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.displaySleeping))
        XCTAssertTrue(env.windowManager.isPaused)
        XCTAssertTrue(engine.rafSuspended, "RAF must suspend during display sleep")
        XCTAssertTrue(engine.mediaSuspended, "Media elements must suspend during display sleep")

        // Step 4: macOS dispatches display wake notification
        env.powerManager.simulateDisplayWake()

        // Step 5: Auto-pause clears and resumes web engine
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.displaySleeping))
        XCTAssertFalse(env.windowManager.isPaused)
        XCTAssertFalse(engine.rafSuspended, "RAF must resume after display wake")
        XCTAssertFalse(engine.mediaSuspended, "Media elements must resume after display wake")
    }

    // MARK: - Scenario 6: Hybrid Wallpaper Switcher Workflow (F2, F3, F4, F5, F6, F8)
    func testScenario6_hybridWallpaperSwitcherWorkflow() {
        // Step 1: Start with Video wallpaper playing at volume 0.8
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let videoItem = WallpaperItem(title: "Hybrid Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(videoItem)
        env.setVolume(0.8)

        guard let videoEngine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(videoEngine.isPlaying)
        XCTAssertEqual(videoEngine.volume, 0.8, accuracy: 0.001)

        // Step 2: Mute audio
        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)

        // Step 3: Switch to Local HTML5 canvas wallpaper
        let folder = env.assetHelper.createSampleWebFolder()
        let webItem = WallpaperItem(title: "Hybrid Canvas", type: .web, sourceURL: folder)
        env.setWallpaper(webItem)

        XCTAssertTrue(videoEngine.isTerminated, "Previous video engine must be terminated")
        guard let webEngine1 = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertTrue(webEngine1.isMuted, "Mute state preserved in web engine")
        XCTAssertEqual(webEngine1.navigationState, .loaded)

        // Step 4: Switch to Remote Live URL wallpaper
        let remoteURL = URL(string: "https://example.com/live-stream")!
        let urlItem = WallpaperItem(title: "Live Stream", type: .url, sourceURL: remoteURL)
        env.setWallpaper(urlItem)

        XCTAssertTrue(webEngine1.isTerminated, "Previous web engine must be terminated")
        guard let webEngine2 = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(webEngine2.navigationState, .loaded)

        // Step 5: Toggle interactive mode on remote wallpaper
        env.toggleInteractiveMode()
        XCTAssertTrue(env.windowManager.isInteractive)
        let window = env.windowManager.windows[0]
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)

        // Step 6: Switch back to Video wallpaper
        env.toggleInteractiveMode() // reset interactive
        env.setWallpaper(videoItem)

        guard let newVideoEngine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(newVideoEngine.isPlaying)
        XCTAssertTrue(newVideoEngine.isMuted, "Mute state remained active across multi-engine switching")
        XCTAssertEqual(newVideoEngine.volume, 0.8, accuracy: 0.001)
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))
    }
}
