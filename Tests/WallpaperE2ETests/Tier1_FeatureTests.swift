import Foundation
import AppKit
import XCTest
import WebKit
import AVFoundation

final class Tier1_FeatureTests: XCTestCase {
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

    // MARK: - Feature 1: Desktop Window Leveling & Spaces (5 tests)

    func testF01_01_desktopWindowLevelMatchesDesktopLevel() {
        let sampleVideo = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Test Video", type: .video, sourceURL: sampleVideo)
        env.setWallpaper(item)

        XCTAssertEqual(env.windowManager.windows.count, 1)
        let window = env.windowManager.windows[0]
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow), "Desktop window must render at desktopWindowLevel")
    }

    func testF01_02_collectionBehaviorIncludesCanJoinAllSpaces() {
        let sampleVideo = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Test Video", type: .video, sourceURL: sampleVideo)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces), "Window must contain .canJoinAllSpaces to persist across macOS spaces")
    }

    func testF01_03_collectionBehaviorIncludesStationaryAndIgnoresCycle() {
        let sampleVideo = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Test Video", type: .video, sourceURL: sampleVideo)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        XCTAssertTrue(window.collectionBehavior.contains(.stationary), "Window must be stationary behind Mission Control")
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle), "Window must ignore Command-Tab window cycling")
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary), "Window must be fullScreenAuxiliary")
    }

    func testF01_04_windowIsBorderlessAndTransparent() {
        let sampleVideo = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Test Video", type: .video, sourceURL: sampleVideo)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        XCTAssertTrue(window.styleMask.contains(.borderless), "Window must be borderless")
        XCTAssertFalse(window.isOpaque, "Window must not be opaque")
        XCTAssertEqual(window.backgroundColor, .clear, "Window background must be clear")
    }

    func testF01_05_multiDisplayWindowSpanningCreatesWindowPerScreen() {
        let screens = [
            SimulatedScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            SimulatedScreen(id: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ]
        let multiEnv = E2ETestEnvironment(screens: screens)
        defer { multiEnv.terminate() }

        let sampleVideo = multiEnv.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Multi Display", type: .video, sourceURL: sampleVideo)
        multiEnv.setWallpaper(item)

        XCTAssertEqual(multiEnv.windowManager.windows.count, 2, "Must create exactly one window per connected display")
        XCTAssertEqual(multiEnv.windowManager.windows[0].frame, screens[0].frame)
        XCTAssertEqual(multiEnv.windowManager.windows[1].frame, screens[1].frame)
    }

    // MARK: - Feature 2: Mouse Event Passthrough & Interactive Mode (5 tests)

    func testF02_01_defaultModeIgnoresMouseEvents() {
        let sampleVideo = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Test", type: .video, sourceURL: sampleVideo)
        env.setWallpaper(item)

        XCTAssertFalse(env.windowManager.isInteractive)
        let window = env.windowManager.windows[0]
        XCTAssertTrue(window.ignoresMouseEvents, "In default mode, ignoresMouseEvents must be true to allow passthrough to Finder")
    }

    func testF02_02_defaultModeHitTestReturnsNil() {
        let sampleFolder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Web", type: .web, sourceURL: sampleFolder)
        env.setWallpaper(item)

        let window = env.windowManager.windows[0]
        let hitResult = window.hitTest(CGPoint(x: 100, y: 100))
        XCTAssertNil(hitResult, "In default mode, hitTest must return nil so desktop icons and Finder receive clicks")
    }

    func testF02_03_interactiveModeElevatesWindowLevel() {
        let sampleFolder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Interactive Web", type: .web, sourceURL: sampleFolder)
        env.setWallpaper(item)

        env.toggleInteractiveMode()
        XCTAssertTrue(env.windowManager.isInteractive)
        let window = env.windowManager.windows[0]
        let expectedLevel = CGWindowLevelForKey(.desktopIconWindow) + 1
        XCTAssertEqual(window.windowLevel, expectedLevel, "Interactive mode must elevate window above desktopIconWindow")
    }

    func testF02_04_interactiveModeEnablesMouseEventsAndHitTest() {
        let sampleFolder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Interactive Web", type: .web, sourceURL: sampleFolder)
        env.setWallpaper(item)

        env.toggleInteractiveMode()
        let window = env.windowManager.windows[0]
        XCTAssertFalse(window.ignoresMouseEvents, "Interactive mode must allow mouse events")
        let hitResult = window.hitTest(CGPoint(x: 100, y: 100))
        XCTAssertNotNil(hitResult, "Interactive mode must return contentView for mouse input handling")
    }

    func testF02_05_toggleInteractiveModeBackToDefault() {
        let sampleFolder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Web", type: .web, sourceURL: sampleFolder)
        env.setWallpaper(item)

        env.toggleInteractiveMode()
        XCTAssertTrue(env.windowManager.isInteractive)

        env.toggleInteractiveMode()
        XCTAssertFalse(env.windowManager.isInteractive)
        let window = env.windowManager.windows[0]
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertNil(window.hitTest(CGPoint(x: 100, y: 100)))
    }

    // MARK: - Feature 3: Video Playback & Seamless Looping (5 tests)

    func testF03_01_videoEngineLoadsAndPlaysMP4() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "MP4 Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying, "Video engine must be playing after initialization")
    }

    func testF03_02_videoEngineSeamlessLoopingIncrement() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Looping MP4", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.loopCount, 0)
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 1)
        engine.simulateLoopIteration()
        XCTAssertEqual(engine.loopCount, 2)
        XCTAssertTrue(engine.isPlaying, "Looping must maintain playing state without stopping")
    }

    func testF03_03_videoEnginePauseAndResume() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Pause Resume MP4", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        env.windowManager.setPaused(true)
        XCTAssertFalse(engine.isPlaying, "Engine must be paused")

        env.windowManager.setPaused(false)
        XCTAssertTrue(engine.isPlaying, "Engine must resume playing")
    }

    func testF03_04_videoEngineDurationValidation() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Duration MP4", type: .video, sourceURL: sampleMP4, duration: 18.5)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.duration, 18.5, accuracy: 0.001)
    }

    func testF03_05_videoEngineMOVFormatSupport() {
        let sampleMOV = env.assetHelper.createSampleVideoMOV()
        let item = WallpaperItem(title: "MOV Video", type: .video, sourceURL: sampleMOV)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying, "MOV format must be supported and play")
    }

    // MARK: - Feature 4: Video Audio & Volume Controls (5 tests)

    func testF04_01_defaultVolumeConfiguration() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Audio Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 1.0, accuracy: 0.001)
        XCTAssertFalse(engine.isMuted)
    }

    func testF04_02_dynamicVolumeAdjustment() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Dynamic Vol", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.setVolume(0.45)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 0.45, accuracy: 0.001)
    }

    func testF04_03_muteToggleSilencesAudio() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Mute Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isMuted)
    }

    func testF04_04_unmuteRestoresPreviousVolume() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Restore Vol", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.setVolume(0.65)
        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)

        env.toggleMute()
        XCTAssertFalse(env.windowManager.isMuted)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 0.65, accuracy: 0.001)
    }

    func testF04_05_volumeAdjustmentWhileMutedUpdatesStoredVolume() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Vol Muted", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.toggleMute()
        XCTAssertTrue(env.windowManager.isMuted)
        env.setVolume(0.3)
        XCTAssertEqual(env.windowManager.volume, 0.3, accuracy: 0.001)

        env.toggleMute()
        XCTAssertFalse(env.windowManager.isMuted)
        guard let engine = env.windowManager.activeEngine as? MockVideoWallpaperEngine else {
            XCTFail("Active engine must be MockVideoWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.volume, 0.3, accuracy: 0.001)
    }

    // MARK: - Feature 5: Local Web Wallpaper (HTML5/Canvas/WebGL) (5 tests)

    func testF05_01_localWebEngineLoadsDirectoryWithIndexHTML() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Canvas Wallpaper", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    func testF05_02_webEngineTransparencyConfiguration() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Transparent Web", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertFalse(engine.drawsBackground, "WebKit background drawing must be false for desktop transparency")
    }

    func testF05_03_contextMenuSuppression() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Context Menu Test", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.contextMenuSuppressed, "Context menu must be suppressed on desktop wallpaper")
    }

    func testF05_04_localWebEnginePlaybackState() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Playback Web", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertTrue(engine.isPlaying)
        env.windowManager.setPaused(true)
        XCTAssertFalse(engine.isPlaying)
    }

    func testF05_05_localWebEngineMissingFileReportsError() {
        let folderWithoutIndex = env.assetHelper.createSampleWebFolder(withIndex: false)
        let item = WallpaperItem(title: "Missing Index Web", type: .web, sourceURL: folderWithoutIndex)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        if case .failed(let reason) = engine.navigationState {
            XCTAssertTrue(reason.contains("Missing index.html"))
        } else {
            XCTFail("Engine should fail navigation when index.html is missing")
        }
    }

    // MARK: - Feature 6: Remote Web Wallpaper Live URLs (5 tests)

    func testF06_01_remoteWebEngineLoadsValidHTTPSURL() {
        let url = URL(string: "https://example.com/live-wallpaper")!
        let item = WallpaperItem(title: "Remote Web", type: .url, sourceURL: url)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    func testF06_02_remoteWebEngineValidatesHTTPSScheme() {
        let httpURL = URL(string: "http://example.com/live")!
        let item = WallpaperItem(title: "HTTP Web", type: .url, sourceURL: httpURL)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    func testF06_03_remoteWebEngineRejectsInvalidScheme() {
        let ftpURL = URL(string: "ftp://example.com/resource")!
        let item = WallpaperItem(title: "FTP Web", type: .url, sourceURL: ftpURL)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        if case .failed(let reason) = engine.navigationState {
            XCTAssertTrue(reason.contains("Invalid scheme"))
        } else {
            XCTFail("Non-HTTP URL scheme must fail")
        }
    }

    func testF06_04_remoteWebEngineUnreachableHostError() {
        let badURL = URL(string: "https://unreachable.doesnotexist.com")!
        let item = WallpaperItem(title: "Bad Host", type: .url, sourceURL: badURL)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        if case .failed(let reason) = engine.navigationState {
            XCTAssertTrue(reason.contains("Unreachable host"))
        } else {
            XCTFail("Unreachable host should report failure")
        }
    }

    func testF06_05_remoteWebEngineReloadsURL() {
        let url = URL(string: "https://example.com/feed")!
        let item = WallpaperItem(title: "Reloadable Web", type: .url, sourceURL: url)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertEqual(engine.reloadCount, 0)
        engine.reload()
        XCTAssertEqual(engine.reloadCount, 1)
        XCTAssertEqual(engine.navigationState, .loaded)
    }

    // MARK: - Feature 7: Web Resource & Audio Suspension (5 tests)

    func testF07_01_webEnginePauseSuspendsRAF() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "RAF Suspension", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertFalse(engine.rafSuspended)
        env.windowManager.setPaused(true)
        XCTAssertTrue(engine.rafSuspended, "Pausing web engine must suspend requestAnimationFrame")
    }

    func testF07_02_webEnginePauseSuspendsMedia() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Media Suspension", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertFalse(engine.mediaSuspended)
        env.windowManager.setPaused(true)
        XCTAssertTrue(engine.mediaSuspended, "Pausing web engine must suspend HTML5 media playback")
    }

    func testF07_03_webEngineResumeRestoresRAF() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Resume RAF", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        env.windowManager.setPaused(true)
        XCTAssertTrue(engine.rafSuspended)
        env.windowManager.setPaused(false)
        XCTAssertFalse(engine.rafSuspended, "Resuming web engine must restore requestAnimationFrame")
    }

    func testF07_04_webEngineResumeRestoresMedia() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Resume Media", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        env.windowManager.setPaused(true)
        XCTAssertTrue(engine.mediaSuspended)
        env.windowManager.setPaused(false)
        XCTAssertFalse(engine.mediaSuspended, "Resuming web engine must restore media elements")
    }

    func testF07_05_webEngineMuteControlsAudio() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Mute Web Audio", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        guard let engine = env.windowManager.activeEngine as? MockWebWallpaperEngine else {
            XCTFail("Active engine must be MockWebWallpaperEngine")
            return
        }
        XCTAssertFalse(engine.isMuted)
        env.toggleMute()
        XCTAssertTrue(engine.isMuted, "Muting must propagate to web engine")
    }

    // MARK: - Feature 8: Menu Bar Companion Controls (5 tests)

    func testF08_01_statusItemInitializesWithSparklesIcon() {
        XCTAssertEqual(env.statusItemController.iconName, "sparkles.tv", "Menu bar companion must initialize with sparkles.tv icon")
    }

    func testF08_02_menuBarPlayPauseToggleUpdatesState() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Menu PlayPause", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        XCTAssertEqual(env.statusItemController.playPauseTitle, "Pause")
        env.togglePlayPause()
        XCTAssertEqual(env.statusItemController.playPauseTitle, "Resume")
        env.togglePlayPause()
        XCTAssertEqual(env.statusItemController.playPauseTitle, "Pause")
    }

    func testF08_03_menuBarMuteToggleUpdatesState() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Menu Mute", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        XCTAssertEqual(env.statusItemController.muteTitle, "Mute")
        env.toggleMute()
        XCTAssertEqual(env.statusItemController.muteTitle, "Unmute")
        env.toggleMute()
        XCTAssertEqual(env.statusItemController.muteTitle, "Mute")
    }

    func testF08_04_menuBarInteractionModeToggle() {
        let folder = env.assetHelper.createSampleWebFolder()
        let item = WallpaperItem(title: "Menu Interactive", type: .web, sourceURL: folder)
        env.setWallpaper(item)

        XCTAssertFalse(env.statusItemController.isInteractiveChecked)
        env.toggleInteractiveMode()
        XCTAssertTrue(env.statusItemController.isInteractiveChecked)
        env.toggleInteractiveMode()
        XCTAssertFalse(env.statusItemController.isInteractiveChecked)
    }

    func testF08_05_menuBarActiveWallpaperSwitching() {
        let sampleMP4_1 = env.assetHelper.createSampleVideoMP4()
        let sampleMP4_2 = env.assetHelper.createSampleVideoMP4()
        let item1 = WallpaperItem(title: "Wallpaper 1", type: .video, sourceURL: sampleMP4_1)
        let item2 = WallpaperItem(title: "Wallpaper 2", type: .video, sourceURL: sampleMP4_2)

        try? env.library.add(item1)
        try? env.library.add(item2)

        env.setWallpaper(item1)
        XCTAssertEqual(env.windowManager.activeWallpaper?.id, item1.id)

        env.setWallpaper(item2)
        XCTAssertEqual(env.windowManager.activeWallpaper?.id, item2.id)
    }

    // MARK: - Feature 9: SwiftUI Wallpaper Manager Gallery & Ingestion (5 tests)

    func testF09_01_galleryDisplaysAvailableWallpapers() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let folder = env.assetHelper.createSampleWebFolder()
        let url = URL(string: "https://example.com/gallery")!

        let item1 = WallpaperItem(title: "Item 1", type: .video, sourceURL: sampleMP4)
        let item2 = WallpaperItem(title: "Item 2", type: .web, sourceURL: folder)
        let item3 = WallpaperItem(title: "Item 3", type: .url, sourceURL: url)

        try? env.library.add(item1)
        try? env.library.add(item2)
        try? env.library.add(item3)

        XCTAssertEqual(env.library.items.count, 3)
        XCTAssertEqual(env.library.items.map(\.title), ["Item 1", "Item 2", "Item 3"])
    }

    func testF09_02_wallpaperSelectionUpdatesActiveWallpaper() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Gallery Select", type: .video, sourceURL: sampleMP4)
        try? env.library.add(item)

        env.setWallpaper(item)
        XCTAssertEqual(env.windowManager.activeWallpaper?.id, item.id)
        XCTAssertEqual(env.windowManager.activeWallpaper?.title, "Gallery Select")
    }

    func testF09_03_fileIngestionImportsValidVideo() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        do {
            let imported = try env.library.importFile(url: sampleMP4)
            XCTAssertEqual(imported.type, .video)
            XCTAssertTrue(env.library.items.contains(where: { $0.id == imported.id }))
        } catch {
            XCTFail("Importing valid video should succeed: \(error)")
        }
    }

    func testF09_04_folderIngestionImportsHTML5Directory() {
        let folder = env.assetHelper.createSampleWebFolder()
        do {
            let imported = try env.library.importFile(url: folder)
            XCTAssertEqual(imported.type, .web)
            XCTAssertTrue(env.library.items.contains(where: { $0.id == imported.id }))
        } catch {
            XCTFail("Importing HTML5 folder should succeed: \(error)")
        }
    }

    func testF09_05_urlIngestionValidatesAndAddsRemoteWallpaper() {
        let urlStr = "https://example.com/live"
        do {
            let imported = try env.library.importURL(urlString: urlStr)
            XCTAssertEqual(imported.type, .url)
            XCTAssertEqual(imported.sourceURL.absoluteString, urlStr)
            XCTAssertTrue(env.library.items.contains(where: { $0.id == imported.id }))
        } catch {
            XCTFail("Importing valid remote URL should succeed: \(error)")
        }
    }

    // MARK: - Feature 10: Energy Saver Auto-Pause Engine (5 tests)

    func testF10_01_fullscreenAppEntersPauseWithReason() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Energy Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        XCTAssertFalse(env.windowManager.isPaused)
        env.powerManager.simulateFullscreenApp(isActive: true)

        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertTrue(env.powerManager.isPaused)
        XCTAssertTrue(env.windowManager.isPaused)
    }

    func testF10_02_fullscreenAppExitsResumesPlayback() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Energy Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.powerManager.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateFullscreenApp(isActive: false)
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertFalse(env.powerManager.isPaused)
        XCTAssertFalse(env.windowManager.isPaused)
    }

    func testF10_03_displaySleepPausesWithReason() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Sleep Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.powerManager.simulateDisplaySleep()
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.displaySleeping))
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateDisplayWake()
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.displaySleeping))
        XCTAssertFalse(env.windowManager.isPaused)
    }

    func testF10_04_screenLockPausesWithReason() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Lock Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.powerManager.simulateScreenLock()
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.screenLocked))
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateScreenUnlock()
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.screenLocked))
        XCTAssertFalse(env.windowManager.isPaused)
    }

    func testF10_05_batterySaverPausesWhenOnDC() {
        let sampleMP4 = env.assetHelper.createSampleVideoMP4()
        let item = WallpaperItem(title: "Battery Video", type: .video, sourceURL: sampleMP4)
        env.setWallpaper(item)

        env.powerManager.simulateBatteryPower(saverActive: true)
        XCTAssertTrue(env.powerManager.currentPauseReasons.contains(.batterySaver))
        XCTAssertTrue(env.windowManager.isPaused)

        env.powerManager.simulateBatteryPower(saverActive: false)
        XCTAssertFalse(env.powerManager.currentPauseReasons.contains(.batterySaver))
        XCTAssertFalse(env.windowManager.isPaused)
    }
}
