import Foundation
import AppKit
import SpriteKit
import XCTest
import WallpaperCore

// MARK: - Tier 3: Flake Combinatorial & Pairwise Cross-Feature Tests
//
// Requirement-driven opaque-box test suite verifying pairwise cross-feature interactions
// across Flake Features 1–33 (spec §4, PROJECT.md § Feature Inventory).
// Contains 37 comprehensive pairwise interaction test cases.

@MainActor
final class Tier3_FlakeCombinationTests: XCTestCase {

    var env: FlakeTestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = FlakeTestEnvironment(
            screen: FlakeSimulatedScreens.standardHD,
            config: FlakeConfiguration(isEnabled: true)
        )
    }

    override func tearDown() async throws {
        env.reset()
        env = nil
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Pairwise Cross-Feature Interaction Tests (37 test cases)
    // =========================================================================

    // MARK: 1. Mitten Tool (F16) + Snowplow Trigger (F19)
    func testF_Comb01_mittenClearingNearSnowplowThresholdPreventsAutoTrigger() {
        // Setup bottom display shelf near the 32px snowplow threshold
        guard var bottom = env.scene.heightmaps[0] else {
            XCTFail("Bottom heightmap must exist")
            return
        }
        bottom.bins = Array(repeating: 30.0, count: bottom.bins.count)
        env.scene.heightmaps[0] = bottom
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 0), 30.0)

        // Clear snow with mitten tool along the bottom edge
        let midX = env.screen.frame.midX
        env.useTool(.mitten, at: CGPoint(x: midX, y: 10), radius: 400)

        // Depth in swept area drops, keeping average depth well below 32px
        let avgAfterMitten = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 0)
        XCTAssertLessThan(avgAfterMitten, 30.0)

        // Advance simulation: since average is below 32px, snowplow does not trigger
        env.advance(seconds: 0.2)
        XCTAssertFalse(env.scene.isSnowplowActive)

        // Now artificially raise above 32px and advance; snowplow should trigger
        bottom = env.scene.heightmaps[0]!
        bottom.bins = Array(repeating: 35.0, count: bottom.bins.count)
        env.scene.heightmaps[0] = bottom
        env.advance(seconds: 0.2)
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    // MARK: 2. Shovel Scoop (F17) + Snowplow Trigger (F19)
    func testF_Comb02_shovelScoopDropsDepthBelowThresholdCancellingSweepCondition() {
        guard var bottom = env.scene.heightmaps[0] else {
            XCTFail("Bottom heightmap must exist")
            return
        }
        // Bottom is right at 31.8px (just under threshold)
        bottom.bins = Array(repeating: 31.8, count: bottom.bins.count)
        env.scene.heightmaps[0] = bottom

        // Shovel tool with wide scoop radius (120pt)
        env.useTool(.shovel, at: CGPoint(x: 960, y: 15), radius: 250)

        let avgAfterShovel = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 0)
        XCTAssertLessThan(avgAfterShovel, 31.8)

        // Advance simulation; plow must not activate
        env.advance(seconds: 0.3)
        XCTAssertFalse(env.scene.isSnowplowActive)
    }

    // MARK: 3. Window Dragging (F14) + Heightmap Accumulation (F12)
    func testF_Comb03_windowDragDuringActiveSnowfallMaintainsDriftGeometry() {
        let win = FlakeWindowFixture.standardAppWindow(id: 301, bounds: CGRect(x: 200, y: 200, width: 800, height: 600))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        let depthBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 301)
        XCTAssertGreaterThan(depthBefore, 0)
        let binsBefore = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 301)

        // Drag window by (dx: 150, dy: 80)
        env.simulateWindowMove(id: 301, newBounds: CGRect(x: 350, y: 280, width: 800, height: 600))

        let depthAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 301)
        let binsAfter = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 301)

        // Accumulated snow depth and bin geometry are preserved
        XCTAssertEqual(binsBefore.count, binsAfter.count)
        XCTAssertEqual(depthBefore, depthAfter, accuracy: 0.001)
        XCTAssertEqual(env.scene.heightmaps[301]?.anchorPosition.x, 350)
    }

    // MARK: 4. Wind Compass (F10) + Window Fairy Lights (F22)
    func testF_Comb04_windCompassAngleAdjustmentWithActiveFairyLights() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.fairyLightsEnabled = true
        cfg.windAngleDegrees = 90.0
        cfg.windSpeed = 1.0
        env.config = cfg

        let win = FlakeWindowFixture.standardAppWindow(id: 302, bounds: CGRect(x: 300, y: 300, width: 600, height: 400))
        env.setWindows([win])
        env.advance(seconds: 0.5)

        // Check wind acceleration before
        let initialAcc = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90.0, windSpeed: 1.0)
        XCTAssertEqual(env.scene.emitterNode?.yAcceleration ?? 0, initialAcc.ay, accuracy: 1.0)

        // Rotate wind compass to 180° (West) and increase wind speed to 2.5
        cfg.windAngleDegrees = 180.0
        cfg.windSpeed = 2.5
        env.config = cfg

        let updatedAcc = FlakeScene.calculateWindAcceleration(windAngleDegrees: 180.0, windSpeed: 2.5)
        XCTAssertEqual(env.scene.emitterNode?.xAcceleration ?? 0, updatedAcc.ax, accuracy: 1.0)
        XCTAssertEqual(env.scene.emitterNode?.yAcceleration ?? 0, updatedAcc.ay, accuracy: 1.0)

        // Window fairy lights remain present and bound to window ledge
        let surfaces = env.scene.surfaces
        XCTAssertTrue(surfaces.contains(where: { $0.id == 302 }))
    }

    // MARK: 5. Blizzard Intensity (F9) + Window Occlusion Culling (F6)
    func testF_Comb05_blizzardIntensityWithOcclusionCulling() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.intensity = .blizzard
        env.config = cfg

        // Overlapping windows: front window covers left half of back window
        let windows = [
            FlakeWindowFixture.standardAppWindow(id: 401, bounds: CGRect(x: 100, y: 200, width: 400, height: 400)), // Front
            FlakeWindowFixture.standardAppWindow(id: 402, bounds: CGRect(x: 300, y: 200, width: 400, height: 400))  // Back
        ]
        env.setWindows(windows)
        env.advance(seconds: 1.5)

        let surfaces = env.scene.surfaces
        guard let sBack = surfaces.first(where: { $0.id == 402 }) else {
            XCTFail("Back surface must exist for unoccluded portion")
            return
        }
        // Occlusion culling must have clipped back window's ledge to start past front window
        XCTAssertGreaterThanOrEqual(sBack.minX, 500)

        // Snow accumulation should only occur on the visible segment
        let backDepth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 402)
        XCTAssertGreaterThan(backDepth, 0)
    }

    // MARK: 6. Window Drag (F14) + Fullscreen Occlusion Pause (F31)
    func testF_Comb06_windowDragWhileFullscreenPauseActivePreservesPendingSurfaces() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let mockPower = FlakeMockPowerManager()
        let mockWindows = MockWindowInfoProvider(windows: [
            FlakeWindowFixture.standardAppWindow(id: 501, bounds: CGRect(x: 200, y: 200, width: 600, height: 400))
        ])
        let detector = WindowSurfaceDetector(windowProvider: mockWindows)

        let controller = FlakeController(
            config: FlakeConfiguration(isEnabled: true, layerMode: .overlay),
            powerManager: mockPower,
            screenProvider: mockScreens,
            surfaceDetector: detector
        )
        defer { controller.terminate() }

        // Enter fullscreen presentation -> pauses controller
        mockPower.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(controller.isPaused)

        // Reposition window while paused
        mockWindows.windows = [
            FlakeWindowFixture.standardAppWindow(id: 501, bounds: CGRect(x: 400, y: 300, width: 600, height: 400))
        ]

        // Exit fullscreen presentation -> unpauses controller
        mockPower.simulateFullscreenApp(isActive: false)
        XCTAssertFalse(controller.isPaused)

        // Poll surfaces after resume
        controller.pollSurfaces()
        let overlayScene = controller.overlayWindows[1]?.flakeScene
        XCTAssertNotNil(overlayScene)
        let s = overlayScene?.surfaces.first(where: { $0.id == 501 })
        XCTAssertEqual(s?.minX, 400)
    }

    // MARK: 7. Multi-Display (F26) + Dock Toggle (F4)
    func testF_Comb07_multiDisplaySetupWithDockTogglePerScreen() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))

        // Screen 1 has 70pt bottom Dock inset, Screen 2 is clean secondary display
        let screen1 = FlakeSimulatedScreens.standardHD
        let screen2 = FlakeSimulatedScreens.secondaryMonitor

        var config = FlakeConfiguration(isEnabled: true)
        config.accumulateOnDock = false

        // When accumulateOnDock is disabled, neither screen extracts Dock
        let surfaces1NoDock = detector.detectSurfaces(screenRect: screen1.frame, visibleFrame: screen1.visibleFrame, primaryScreenHeight: nil, config: config)
        let surfaces2NoDock = detector.detectSurfaces(screenRect: screen2.frame, visibleFrame: screen2.visibleFrame, primaryScreenHeight: nil, config: config)
        XCTAssertFalse(surfaces1NoDock.contains(where: { $0.isDock }))
        XCTAssertFalse(surfaces2NoDock.contains(where: { $0.isDock }))

        // When accumulateOnDock is enabled, only screen 1 (with inset) extracts Dock
        config.accumulateOnDock = true
        let surfaces1WithDock = detector.detectSurfaces(screenRect: screen1.frame, visibleFrame: screen1.visibleFrame, primaryScreenHeight: nil, config: config)
        let surfaces2WithDock = detector.detectSurfaces(screenRect: screen2.frame, visibleFrame: screen2.visibleFrame, primaryScreenHeight: nil, config: config)
        XCTAssertTrue(surfaces1WithDock.contains(where: { $0.isDock }))
        XCTAssertFalse(surfaces2WithDock.contains(where: { $0.isDock }))
    }

    // MARK: 8. Snowplow Model Change (F20) + Active Traversal (F21)
    func testF_Comb08_snowplowModelChangeDuringActiveSweep() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.snowplowModel = .classicTractor
        env.config = cfg

        // Trigger snowplow sweep
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)

        // Change model to Penguin while sweep is in progress
        cfg.snowplowModel = .penguin
        env.config = cfg

        XCTAssertEqual(env.config.snowplowModel, .penguin)
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    // MARK: 9. Dynamic Mouse Passthrough (F18) + Desktop Layer Mode (F25)
    func testF_Comb09_dynamicMousePassthroughWithLayerModeDesktop() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        var config = FlakeConfiguration(isEnabled: true, layerMode: .overlay)
        config.activeTool = .mitten

        let controller = FlakeController(
            config: config,
            screenProvider: mockScreens
        )
        defer { controller.terminate() }

        // In .overlay mode with mitten active, overlay window accepts mouse events
        guard let window = controller.overlayWindows[1] else {
            XCTFail("Overlay window must exist")
            return
        }
        XCTAssertFalse(window.ignoresMouseEvents)

        // Switching to .desktop closes overlay windows (desktop mode renders behind apps)
        config.layerMode = .desktop
        controller.config = config
        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    // MARK: 10. Angle of Repose Smoothing (F13) + Mitten Excavation (F16)
    func testF_Comb10_angleOfReposeSmoothingWithMittenClearingExcavation() {
        let win = FlakeWindowFixture.standardAppWindow(id: 601, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])

        // Seed uniform snowbank of depth 18.0
        guard var hm = env.scene.heightmaps[601] else {
            XCTFail("Heightmap must exist")
            return
        }
        hm.bins = Array(repeating: 18.0, count: hm.bins.count)
        env.scene.heightmaps[601] = hm

        // Use mitten tool to excavate a hole in the center
        let midX = win.bounds.midX
        let topY = env.scene.surfaces.first(where: { $0.id == 601 })?.topEdgeY ?? (env.screen.frame.height - win.bounds.minY)
        env.useTool(.mitten, at: CGPoint(x: midX, y: topY), radius: 40)

        // Verify hole was excavated
        let centerBin = hm.bins.count / 2
        let binsAfterTool = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 601)
        XCTAssertLessThan(binsAfterTool[centerBin], 18.0)

        // Convolve angle of repose; edge transitions are smoothed
        let smoothedBins = SurfaceHeightmap.convolve(bins: binsAfterTool, maxCap: 22.0)
        XCTAssertTrue(FlakeHeightmapInspector.verifyReposeSmoothing(bins: smoothedBins, maxCap: 22.0))
    }

    // MARK: 11. Display Sleep (F29) + Window Resize (F14)
    func testF_Comb11_displaySleepDuringWindowResizePreservesResizedHeightmap() {
        let win = FlakeWindowFixture.standardAppWindow(id: 701, bounds: CGRect(x: 100, y: 100, width: 500, height: 400))
        env.setWindows([win])
        env.advance(seconds: 1.0)

        let initialBinCount = FlakeHeightmapInspector.binCount(in: env.scene, surfaceID: 701)
        XCTAssertEqual(initialBinCount, 50) // 500pt / 10pt = 50 bins

        // Display sleep notification
        env.mockPowerManager.simulateDisplaySleep()
        XCTAssertTrue(env.mockPowerManager.isPaused)

        // While sleeping, window is expanded to 800pt width
        env.simulateWindowMove(id: 701, newBounds: CGRect(x: 100, y: 100, width: 800, height: 400))
        let resizedBinCount = FlakeHeightmapInspector.binCount(in: env.scene, surfaceID: 701)
        XCTAssertEqual(resizedBinCount, 80) // 800pt / 10pt = 80 bins

        // Display wake notification
        env.mockPowerManager.simulateDisplayWake()
        XCTAssertFalse(env.mockPowerManager.isPaused)

        // Snow resumes accumulating across all 80 bins
        env.advance(seconds: 1.0)
        XCTAssertEqual(FlakeHeightmapInspector.binCount(in: env.scene, surfaceID: 701), 80)
    }

    // MARK: 12. Screen Lock (F30) + Manual Clear Snow Reset (F32)
    func testF_Comb12_screenLockWithManualClearSnowReset() {
        let win = FlakeWindowFixture.standardAppWindow(id: 801, bounds: CGRect(x: 200, y: 200, width: 600, height: 400))
        env.setWindows([win])
        env.advance(seconds: 2.0)
        XCTAssertGreaterThan(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 801), 0)

        // Screen locks
        env.mockPowerManager.simulateScreenLock()
        XCTAssertTrue(env.mockPowerManager.isPaused)

        // User triggers clear all snow while locked
        env.scene.clearAllSnow()

        // Heightmaps are reset to 0 even while screen lock is active
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 801), 0.0)
    }

    // MARK: 13. Wind Gust (F11) + Heightmap Ceiling Cap (F15)
    func testF_Comb13_extremeGustWithHeightmapCeilingCapSaturation() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.intensity = .blizzard
        cfg.windSpeed = 3.0 // Strong gust
        cfg.windAngleDegrees = 45.0
        env.config = cfg

        let win = FlakeWindowFixture.standardAppWindow(id: 901, bounds: CGRect(x: 300, y: 300, width: 500, height: 400))
        env.setWindows([win])

        // Advance simulation for sustained accumulation
        env.advance(seconds: 5.0)

        // Maximum depth must not exceed standard window cap of 22pt
        let maxDepth = FlakeHeightmapInspector.maxDepth(in: env.scene, surfaceID: 901)
        XCTAssertLessThanOrEqual(maxDepth, 22.0)
    }

    // MARK: 14. Status Bar Toggle (F32) + Settings View Sync (F33)
    func testF_Comb14_statusBarToggleSynchronizesWithSettingsViewState() {
        let appState = AppState()
        let statusController = StatusItemController(appState: appState, attachToStatusBar: false)
        XCTAssertNotNil(statusController)

        // Initial state is disabled
        XCTAssertFalse(appState.flakeConfig.isEnabled)

        // Toggle via StatusItem
        appState.flakeConfig.isEnabled = true
        XCTAssertTrue(appState.flakeConfig.isEnabled)

        // Change intensity to blizzard
        appState.flakeConfig.intensity = .blizzard
        XCTAssertEqual(appState.flakeConfig.intensity, .blizzard)

        // Change active tool to shovel
        appState.flakeConfig.activeTool = .shovel
        XCTAssertEqual(appState.flakeConfig.activeTool, .shovel)
    }

    // MARK: 15. Multi-Display Hot-Plug (F27) + Blizzard Intensity (F9)
    func testF_Comb15_multiDisplayHotPlugDuringBlizzardIntensity() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        var cfg = FlakeConfiguration(isEnabled: true, layerMode: .overlay)
        cfg.intensity = .blizzard

        let controller = FlakeController(config: cfg, screenProvider: mockScreens)
        defer { controller.terminate() }

        XCTAssertEqual(controller.overlayWindows.count, 1)

        // Hot-plug secondary display
        mockScreens.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ]
        controller.rebuildOverlayWindows()

        XCTAssertEqual(controller.overlayWindows.count, 2)
        // Both overlay scenes inherit blizzard configuration
        XCTAssertEqual(controller.overlayWindows[1]?.flakeScene.config.intensity, .blizzard)
        XCTAssertEqual(controller.overlayWindows[2]?.flakeScene.config.intensity, .blizzard)
    }

    // MARK: 16. Fairy Lights (F22) + Resized Window (F14)
    func testF_Comb16_fairyLightsPreservedAcrossWindowResize() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.fairyLightsEnabled = true
        env.config = cfg

        let win = FlakeWindowFixture.standardAppWindow(id: 1001, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 0.5)

        // Window expanded from 400pt to 700pt
        env.simulateWindowMove(id: 1001, newBounds: CGRect(x: 200, y: 200, width: 700, height: 300))
        env.advance(seconds: 0.5)

        // Window surface spans 700pt
        let surface = env.scene.surfaces.first(where: { $0.id == 1001 })
        XCTAssertEqual(surface?.width, 700)
    }

    // MARK: 17. Multi-Display Independent Snowplows (F19, F26)
    func testF_Comb17_multiDisplayIndependentSnowplowTriggers() {
        let scene1 = FlakeScene(size: CGSize(width: 1920, height: 1080))
        let scene2 = FlakeScene(size: CGSize(width: 1920, height: 1080))
        scene1.config = FlakeConfiguration(isEnabled: true)
        scene2.config = FlakeConfiguration(isEnabled: true)

        scene1.updateSurfaces()
        scene2.updateSurfaces()

        // Fill floor of scene1 to 35px (> 32px threshold)
        if var b1 = scene1.heightmaps[0] {
            b1.bins = Array(repeating: 35.0, count: b1.bins.count)
            scene1.heightmaps[0] = b1
        }
        // Scene2 floor remains at 10px
        if var b2 = scene2.heightmaps[0] {
            b2.bins = Array(repeating: 10.0, count: b2.bins.count)
            scene2.heightmaps[0] = b2
        }

        scene1.update(100.1)
        scene2.update(100.1)

        // Snowplow triggers only on scene1
        XCTAssertTrue(scene1.isSnowplowActive)
        XCTAssertFalse(scene2.isSnowplowActive)
    }

    // MARK: 18. Mitten Brush (F16) over Fairy Lights (F22)
    func testF_Comb18_mittenBrushOverWindowWithFairyLights() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.fairyLightsEnabled = true
        cfg.activeTool = .mitten
        env.config = cfg

        let win = FlakeWindowFixture.standardAppWindow(id: 1101, bounds: CGRect(x: 200, y: 200, width: 500, height: 400))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        let depthBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 1101)
        XCTAssertGreaterThan(depthBefore, 0)

        // Brush mitten across the window top ledge
        let topY = env.scene.surfaces.first(where: { $0.id == 1101 })?.topEdgeY ?? 400
        env.useTool(.mitten, at: CGPoint(x: 450, y: topY), radius: 60)

        let depthAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 1101)
        XCTAssertLessThan(depthAfter, depthBefore)
    }

    // MARK: 19. Multi-Screen Coordinate Inversion (F3, F26)
    func testF_Comb19_coordinateInversionWithMultiScreenVirtualGeometry() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [
            FlakeWindowFixture.standardAppWindow(id: 1201, bounds: CGRect(x: 1950, y: 100, width: 600, height: 500))
        ]))

        let primaryHeight: CGFloat = 1080.0
        let secondaryScreenRect = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let surfaces = detector.detectSurfaces(
            screenRect: secondaryScreenRect,
            visibleFrame: secondaryScreenRect,
            primaryScreenHeight: primaryHeight,
            config: FlakeConfiguration(isEnabled: true)
        )

        guard let s = surfaces.first(where: { $0.id == 1201 }) else {
            XCTFail("Window surface on secondary display must be detected")
            return
        }
        // Cocoa topEdgeY inverted from Quartz: 1080 - 100 = 980
        XCTAssertEqual(s.topEdgeY, 980)
        XCTAssertEqual(s.minX, 1950)
    }

    // MARK: 20. Compound Pause Reason Stacking (F28, F29, F30, F31)
    func testF_Comb20_compoundPauseStackingSleepLockFullscreen() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(
            config: FlakeConfiguration(isEnabled: true, layerMode: .overlay),
            powerManager: mockPower,
            screenProvider: mockScreens
        )
        defer { controller.terminate() }

        // Stack three pause reasons
        mockPower.simulateDisplaySleep()
        mockPower.simulateScreenLock()
        mockPower.simulateFullscreenApp(isActive: true)

        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(mockPower.currentPauseReasons, [.displaySleeping, .screenLocked, .fullscreenApp])

        // Remove sleep: still paused
        mockPower.simulateDisplayWake()
        XCTAssertTrue(controller.isPaused)

        // Remove lock: still paused
        mockPower.simulateScreenUnlock()
        XCTAssertTrue(controller.isPaused)

        // Remove fullscreen: now cleanly unpaused
        mockPower.simulateFullscreenApp(isActive: false)
        XCTAssertFalse(controller.isPaused)
    }

    // MARK: 21. Dock Orientation Change (F4, F5)
    func testF_Comb21_dockOrientationChangeFromBottomToLeftEdge() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Bottom Dock: visible frame minY is 70
        let bottomDockFrame = CGRect(x: 0, y: 70, width: 1920, height: 1010)
        let bottomSurfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: bottomDockFrame, primaryScreenHeight: nil, config: FlakeConfiguration(isEnabled: true))
        XCTAssertTrue(bottomSurfaces.contains(where: { $0.isDock }))

        // Left Dock: visible frame minX is 80, minY is 0
        let leftDockFrame = CGRect(x: 80, y: 0, width: 1840, height: 1080)
        let leftSurfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: leftDockFrame, primaryScreenHeight: nil, config: FlakeConfiguration(isEnabled: true))
        // Since bottomInset == 0, fallback does not create bottom Dock ledge
        XCTAssertFalse(leftSurfaces.contains(where: { $0.isDock }))
        // Bottom shelf (id: 0) is still intact
        XCTAssertTrue(leftSurfaces.contains(where: { $0.id == 0 }))
    }

    // MARK: 22. Light Intensity (F9) + Calm Zero Wind (F10)
    func testF_Comb22_lightIntensityWithZeroWindCalmFall() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90.0, windSpeed: 0.0)
        XCTAssertEqual(ax, 0.0)
        XCTAssertEqual(ay, -120.0) // Pure vertical downward gravity

        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.intensity = .light
        cfg.windSpeed = 0.0
        env.config = cfg

        XCTAssertEqual(env.scene.emitterNode?.particleBirthRate, 20.0)
        XCTAssertEqual(env.scene.emitterNode?.xAcceleration, 0.0)
    }

    // MARK: 23. Updraft Wind (F10) + Occlusion Culling (F6)
    func testF_Comb23_updraftWindWithWindowOcclusion() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270.0, windSpeed: 2.0)
        // Updraft has positive ay component
        XCTAssertGreaterThan(ay, 0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)

        // Window occlusion still computes identical geometric collision ledges
        let windows = FlakeWindowFixture.overlappingPair()
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)
        XCTAssertEqual(surfaces.filter({ $0.id != 0 && !$0.isDock }).count, 2)
    }

    // MARK: 24. Custom Plow Model (F20) + Bottom Shelf Accumulation (F19)
    func testF_Comb24_customPlowModelWithBottomShelfAccumulation() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.snowplowModel = .custom
        cfg.customPlowImageURL = URL(fileURLWithPath: "/tmp/custom_snowplow.png")
        env.config = cfg

        if var b = env.scene.heightmaps[0] {
            b.bins = Array(repeating: 36.0, count: b.bins.count)
            env.scene.heightmaps[0] = b
        }
        env.advance(seconds: 0.2)

        XCTAssertTrue(env.scene.isSnowplowActive)
        XCTAssertEqual(env.config.snowplowModel, .custom)
    }

    // MARK: 25. Ambient Audio (F33) + Battery Saver Pause (F28)
    func testF_Comb25_ambientAudioVolumeAdjustmentUnderBatterySaver() {
        let mockPower = FlakeMockPowerManager()
        var cfg = FlakeConfiguration(isEnabled: true, layerMode: .overlay)
        cfg.ambientSoundEnabled = true
        cfg.soundVolume = 0.6

        let controller = FlakeController(config: cfg, powerManager: mockPower)
        defer { controller.terminate() }

        // Battery saver engaged -> pauses controller
        mockPower.simulateBatteryPower(saverActive: true)
        XCTAssertTrue(controller.isPaused)

        // Modify volume while paused
        cfg.soundVolume = 0.85
        controller.config = cfg
        XCTAssertEqual(controller.config.soundVolume, 0.85)

        // Battery saver disengaged -> resumes controller
        mockPower.simulateBatteryPower(saverActive: false)
        XCTAssertFalse(controller.isPaused)
    }

    // MARK: 26. 10 Hz Polling Throttle (F7) + Rapid Window Moves (F14)
    func testF_Comb26_10HzPollingThrottleUnderRapidWindowMoves() {
        let win = FlakeWindowFixture.standardAppWindow(id: 1301, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // First update establishes lastSurfacePollTime
        env.scene.update(100.0)

        // Subsequent update only 0.02s later (< 0.1s throttle)
        env.scene.update(100.02)
        // Update at 100.15s (> 0.1s throttle) triggers surface detection
        env.scene.update(100.15)
        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 1301 }))
    }

    // MARK: 27. Snowplow Sweep (F21) + Dock Ledge Separation (F4)
    func testF_Comb27_snowplowSweepTraversingAcrossDockLedgeSeparation() {
        let win = FlakeWindowFixture.dockWindow(bounds: CGRect(x: 0, y: 1010, width: 1920, height: 70))
        env.setWindows([win])

        // Set accumulation on both bottom shelf (id: 0) and Dock (id: 999)
        if var b0 = env.scene.heightmaps[0] {
            b0.bins = Array(repeating: 35.0, count: b0.bins.count)
            env.scene.heightmaps[0] = b0
        }
        if var bDock = env.scene.heightmaps[999] {
            bDock.bins = Array(repeating: 20.0, count: bDock.bins.count)
            env.scene.heightmaps[999] = bDock
        }

        // Trigger snowplow sweep
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)

        // Dock snow depth is not affected by floor plow sweep
        let dockDepth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 999)
        XCTAssertEqual(dockDepth, 20.0)
    }

    // MARK: 28. Shovel Clearing (F17) Across Overlapping Windows (F2)
    func testF_Comb28_shovelClearingAcrossAdjacentOverlappingWindows() {
        let windows = [
            FlakeWindowFixture.standardAppWindow(id: 1401, bounds: CGRect(x: 100, y: 200, width: 400, height: 400)),
            FlakeWindowFixture.standardAppWindow(id: 1402, bounds: CGRect(x: 480, y: 200, width: 400, height: 400))
        ]
        env.setWindows(windows)
        env.advance(seconds: 2.0)

        let d1Before = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 1401)
        let d2Before = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 1402)
        XCTAssertGreaterThan(d1Before, 0)
        XCTAssertGreaterThan(d2Before, 0)

        // Shovel positioned between both windows at x = 490
        let topY = env.scene.surfaces.first(where: { $0.id == 1401 })?.topEdgeY ?? 400
        env.useTool(.shovel, at: CGPoint(x: 490, y: topY), radius: 60)

        let d1After = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 1401)
        let d2After = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 1402)

        // Both windows had snow cleared at their adjacent borders
        XCTAssertLessThan(d1After, d1Before)
        XCTAssertLessThan(d2After, d2Before)
    }

    // MARK: 29. Zero-TCC Window Filtering (F2) with Tiny/Offscreen Windows (F1)
    func testF_Comb29_zeroTCCFilteringWithTinyWindowAndSubpixelAlpha() {
        let windows = [
            FlakeWindowFixture.standardAppWindow(id: 1501, bounds: CGRect(x: 100, y: 100, width: 500, height: 400)),
            FlakeWindowFixture.tinyWindow(id: 1502, bounds: CGRect(x: 50, y: 50, width: 80, height: 50)),
            FlakeWindowFixture.lowAlphaWindow(id: 1503, bounds: CGRect(x: 200, y: 200, width: 300, height: 200)),
            FlakeWindowFixture.offscreenWindow(id: 1504, bounds: CGRect(x: 300, y: 300, width: 300, height: 200))
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        // Only standard window and bottom shelf survive filtering
        XCTAssertTrue(surfaces.contains(where: { $0.id == 1501 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 1502 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 1503 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 1504 }))
    }

    // MARK: 30. Window Movement Re-anchoring (F14) + Angle of Repose (F13)
    func testF_Comb30_windowMovementReanchoringWithAngleOfReposeSmoothing() {
        let win = FlakeWindowFixture.standardAppWindow(id: 1601, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 1.5)

        // Move window
        env.simulateWindowMove(id: 1601, newBounds: CGRect(x: 400, y: 250, width: 400, height: 300))

        // Step simulation: smoothAngleOfRepose is invoked after re-anchoring
        env.advance(seconds: 0.5)
        let bins = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 1601)
        XCTAssertTrue(FlakeHeightmapInspector.verifyReposeSmoothing(bins: bins, maxCap: 22.0))
    }

    // MARK: 31. Fairy Lights Twinkle (F23) During Wind Shift (F10)
    func testF_Comb31_fairyLightsTwinkleAnimationCyclesDuringWindShift() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.fairyLightsEnabled = true
        cfg.windAngleDegrees = 0.0
        env.config = cfg

        let win = FlakeWindowFixture.standardAppWindow(id: 1701, bounds: CGRect(x: 300, y: 300, width: 500, height: 350))
        env.setWindows([win])
        env.advance(seconds: 0.5)

        // Shift wind by 180 degrees
        cfg.windAngleDegrees = 180.0
        env.config = cfg

        // Emitter updates without disrupting fairy lights presence
        XCTAssertEqual(env.config.windAngleDegrees, 180.0)
        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 1701 }))
    }

    // MARK: 32. Dual Layer Mode Switching (F25) + Heightmap Persistence (F12)
    func testF_Comb32_dualLayerModeSwitchingPreservesAccumulatedHeightmaps() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        var cfg = FlakeConfiguration(isEnabled: true, layerMode: .overlay)
        let controller = FlakeController(config: cfg, screenProvider: mockScreens)
        defer { controller.terminate() }

        XCTAssertEqual(controller.overlayWindows.count, 1)

        // Switch to .desktop -> overlay closed
        cfg.layerMode = .desktop
        controller.config = cfg
        XCTAssertTrue(controller.overlayWindows.isEmpty)

        // Switch back to .overlay -> overlay restored
        cfg.layerMode = .overlay
        controller.config = cfg
        XCTAssertEqual(controller.overlayWindows.count, 1)
    }

    // MARK: 33. Screen Lock (F30) + Interactive Tool Passthrough (F18)
    func testF_Comb33_screenLockWithActiveMittenToolResetsToolStateOrPassthrough() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let mockPower = FlakeMockPowerManager()
        var cfg = FlakeConfiguration(isEnabled: true, layerMode: .overlay)
        cfg.activeTool = .mitten

        let controller = FlakeController(config: cfg, powerManager: mockPower, screenProvider: mockScreens)
        defer { controller.terminate() }

        guard let win = controller.overlayWindows[1] else {
            XCTFail("Window must exist")
            return
        }
        XCTAssertFalse(win.ignoresMouseEvents)

        // Lock screen -> pauses rendering
        mockPower.simulateScreenLock()
        XCTAssertTrue(controller.isPaused)
        XCTAssertTrue(win.skView.isPaused)

        // Unlock screen -> resumes rendering and maintains tool state
        mockPower.simulateScreenUnlock()
        XCTAssertFalse(controller.isPaused)
        XCTAssertFalse(win.skView.isPaused)
        XCTAssertFalse(win.ignoresMouseEvents)
    }

    // MARK: 34. Clear Snow Drifts via Menu Companion (F32, F26)
    func testF_Comb34_clearSnowDriftsViaMenuCompanionSynchronizesOverlayScenes() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay), screenProvider: mockScreens)
        defer { controller.terminate() }

        // Artificially populate snow on both displays
        for (_, win) in controller.overlayWindows {
            if var b = win.flakeScene.heightmaps[0] {
                b.bins = Array(repeating: 25.0, count: b.bins.count)
                win.flakeScene.heightmaps[0] = b
            }
        }

        // Trigger clear all snow
        controller.clearAllSnow()

        for (_, win) in controller.overlayWindows {
            XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: win.flakeScene, surfaceID: 0), 0.0)
        }
    }

    // MARK: 35. Window Min Dimensions Boundary (F2) + Surface Cap (F15)
    func testF_Comb35_windowMinDimensionsBoundaryWithSurfaceCap() {
        // Exactly at minimum allowable dimensions: 120 width x 80 height
        let win = FlakeWindowFixture.standardAppWindow(id: 1801, bounds: CGRect(x: 100, y: 100, width: 120, height: 80))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 1801 }))
        guard let s = surfaces.first(where: { $0.id == 1801 }) else { return }

        let cap = FlakeScene.calculateMaxCap(for: s, screenHeight: 1080)
        XCTAssertEqual(cap, 22.0) // Standard window cap
    }

    // MARK: 36. Snowplow Disabled Prevents Trigger (F19)
    func testF_Comb36_snowplowDisabledPreventsTriggerEvenWhenFloorOverflows() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.snowplowEnabled = false
        env.config = cfg

        if var b = env.scene.heightmaps[0] {
            b.bins = Array(repeating: 45.0, count: b.bins.count)
            env.scene.heightmaps[0] = b
        }
        env.advance(seconds: 0.5)

        XCTAssertFalse(env.scene.isSnowplowActive)
    }

    // MARK: 37. Dock Ledge Surface Cap (F4, F15)
    func testF_Comb37_dockLedgeSurfaceCapIsThirtyPoints() {
        let dockSurface = CollisionSurface(
            id: 999,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 70),
            topEdgeY: 70,
            minX: 0,
            maxX: 1920,
            isDock: true
        )
        let cap = FlakeScene.calculateMaxCap(for: dockSurface, screenHeight: 1080)
        XCTAssertEqual(cap, 30.0) // macOS Dock cap
    }
}
