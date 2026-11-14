import XCTest
@testable import WallpaperCore

// MARK: - Test Mocks

final class MockWindowSurfaceDetector: WindowSurfaceDetectorProtocol, @unchecked Sendable {
    var surfacesToReturn: [CollisionSurface]

    init(surfaces: [CollisionSurface] = []) {
        self.surfacesToReturn = surfaces
    }

    func detectSurfaces(screenRect: CGRect, visibleFrame: CGRect) -> [CollisionSurface] {
        return surfacesToReturn
    }

    func detectSurfaces(
        screenRect: CGRect,
        visibleFrame: CGRect,
        primaryScreenHeight: CGFloat?,
        config: FlakeConfiguration
    ) -> [CollisionSurface] {
        return surfacesToReturn
    }
}

@MainActor
final class MockPowerManager: PowerManagerProtocol {
    weak var delegate: (any PowerManagerDelegate)?
    var currentPauseReasons: PauseReasons = []
    var isPaused: Bool = false
    var settings: PowerSettings = PowerSettings()
    var isMonitoring: Bool = false

    func startMonitoring() { isMonitoring = true }
    func stopMonitoring() { isMonitoring = false }
    func updateSettings(_ newSettings: PowerSettings) { settings = newSettings }

    func addPauseReason(_ reason: PauseReasons) {
        currentPauseReasons.insert(reason)
        isPaused = !currentPauseReasons.isEmpty
        delegate?.powerManagerDidChangePauseState(self, isPaused: isPaused, reasons: currentPauseReasons)
    }

    func removePauseReason(_ reason: PauseReasons) {
        currentPauseReasons.remove(reason)
        isPaused = !currentPauseReasons.isEmpty
        delegate?.powerManagerDidChangePauseState(self, isPaused: isPaused, reasons: currentPauseReasons)
    }

    func setPauseReason(_ reason: PauseReasons, active: Bool) {
        if active { addPauseReason(reason) } else { removePauseReason(reason) }
    }

    func setUserPaused(_ paused: Bool) { setPauseReason(.userPaused, active: paused) }
    func setFullscreenOccluded(_ occluded: Bool) { setPauseReason(.fullscreenApp, active: occluded) }
    func simulateFullscreenApp(isActive: Bool) { setPauseReason(.fullscreenApp, active: isActive) }
    func simulateFullscreen(isActive: Bool) { setPauseReason(.fullscreenApp, active: isActive) }
    func simulateDisplaySleep() { addPauseReason(.displaySleeping) }
    func simulateDisplayWake() { removePauseReason(.displaySleeping) }
    func simulateScreenLock() { addPauseReason(.screenLocked) }
    func simulateScreenUnlock() { removePauseReason(.screenLocked) }
    func simulateBatteryPower(saverActive: Bool) { setPauseReason(.batterySaver, active: saverActive) }
    func simulateBatteryState(isOnBattery: Bool) { setPauseReason(.batterySaver, active: isOnBattery && settings.pauseOnBattery) }
    func simulateUserPause(isPaused: Bool) { setUserPaused(isPaused) }
}

// MARK: - Flake Milestone 1 Comprehensive Test Suite

final class FlakeTests: XCTestCase {

    // MARK: - 1. Configuration & Codable Tests (Features 8, 9, 10, 11)

    func testFlakeConfigurationDefaults() {
        let config = FlakeConfiguration()
        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.layerMode, .overlay)
        XCTAssertEqual(config.intensity, .steady)
        XCTAssertEqual(config.windAngleDegrees, 90.0)
        XCTAssertEqual(config.windSpeed, 1.0)
        XCTAssertTrue(config.accumulateOnWindows)
        XCTAssertTrue(config.accumulateOnDock)
        XCTAssertTrue(config.accumulateOnScreenBottom)
        XCTAssertTrue(config.snowplowEnabled)
        XCTAssertEqual(config.snowplowModel, .classicTractor)
        XCTAssertFalse(config.fairyLightsEnabled)
        XCTAssertFalse(config.ambientSoundEnabled)
        XCTAssertEqual(config.soundVolume, 0.5)
        XCTAssertEqual(config.activeTool, .none)
    }

    func testSnowfallIntensityTuning() {
        XCTAssertEqual(SnowfallIntensity.light.maxParticles, 150)
        XCTAssertEqual(SnowfallIntensity.steady.maxParticles, 400)
        XCTAssertEqual(SnowfallIntensity.blizzard.maxParticles, 900)

        XCTAssertTrue(SnowfallIntensity.light.birthRate < SnowfallIntensity.steady.birthRate)
        XCTAssertTrue(SnowfallIntensity.steady.birthRate < SnowfallIntensity.blizzard.birthRate)
    }

    func testSnowfallIntensityTiers_particleAndBirthRates() {
        // Feature 8 & 9: Intensity Particle Budgets & Lifetimes
        let light = SnowfallIntensity.light
        XCTAssertEqual(light.maxParticles, 150)
        XCTAssertEqual(light.birthRate, 20.0)
        XCTAssertEqual(light.particleLifetime, 7.5, accuracy: 0.001)

        let steady = SnowfallIntensity.steady
        XCTAssertEqual(steady.maxParticles, 400)
        XCTAssertEqual(steady.birthRate, 50.0)
        XCTAssertEqual(steady.particleLifetime, 8.0, accuracy: 0.001)

        let blizzard = SnowfallIntensity.blizzard
        XCTAssertEqual(blizzard.maxParticles, 900)
        XCTAssertEqual(blizzard.birthRate, 120.0)
        XCTAssertEqual(blizzard.particleLifetime, 7.5, accuracy: 0.001)
    }

    func testFlakeConfigurationCodableRoundTrip() throws {
        var original = FlakeConfiguration()
        original.isEnabled = true
        original.layerMode = .desktop
        original.intensity = .blizzard
        original.windAngleDegrees = 135.0
        original.windSpeed = 2.5
        original.snowplowModel = .penguin
        original.fairyLightsEnabled = true
        original.ambientSoundEnabled = true
        original.soundVolume = 0.8
        original.activeTool = .mitten

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FlakeConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - 2. Collision Surface Model Tests

    func testCollisionSurfaceGeometry() {
        let surface = CollisionSurface(
            id: 101,
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            topEdgeY: 800,
            minX: 100,
            maxX: 900,
            isDock: false
        )

        XCTAssertEqual(surface.width, 800)
        XCTAssertTrue(surface.containsX(100))
        XCTAssertTrue(surface.containsX(500))
        XCTAssertTrue(surface.containsX(900))
        XCTAssertFalse(surface.containsX(99))
        XCTAssertFalse(surface.containsX(901))
    }

    // MARK: - 3. Window Surface Detector Tests (Features 1, 2, 3, 4, 5, 6)

    func testWindowSurfaceDetectorScreenBottom() {
        let mockProvider = MockWindowInfoProvider(windows: [])
        let detector = WindowSurfaceDetector(windowProvider: mockProvider)

        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = true

        let surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.first?.id, 0)
        XCTAssertEqual(surfaces.first?.topEdgeY, 0)
        XCTAssertEqual(surfaces.first?.width, 1920)
    }

    func testWindowSurfaceDetectorFiltersInvalidWindows() {
        let windows: [WindowInfo] = [
            // Valid app window
            WindowInfo(windowNumber: 1, ownerName: "Safari", bounds: CGRect(x: 200, y: 100, width: 800, height: 600), layer: 0, alpha: 1.0, isOnScreen: true),
            // Layer != 0 (e.g. status bar, notification center)
            WindowInfo(windowNumber: 2, ownerName: "SystemUI", bounds: CGRect(x: 0, y: 0, width: 1920, height: 30), layer: 25, alpha: 1.0, isOnScreen: true),
            // Offscreen
            WindowInfo(windowNumber: 3, ownerName: "Xcode", bounds: CGRect(x: 200, y: 100, width: 800, height: 600), layer: 0, alpha: 1.0, isOnScreen: false),
            // Too small
            WindowInfo(windowNumber: 4, ownerName: "Helper", bounds: CGRect(x: 200, y: 100, width: 50, height: 40), layer: 0, alpha: 1.0, isOnScreen: true),
            // Almost transparent
            WindowInfo(windowNumber: 5, ownerName: "Fader", bounds: CGRect(x: 200, y: 100, width: 500, height: 400), layer: 0, alpha: 0.02, isOnScreen: true)
        ]

        let mockProvider = MockWindowInfoProvider(windows: windows)
        let detector = WindowSurfaceDetector(windowProvider: mockProvider)
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.first?.id, 1)
        XCTAssertEqual(surfaces.first?.minX, 200)
        XCTAssertEqual(surfaces.first?.maxX, 1000)
        // In Quartz y=100, Cocoa top edge = 1080 - 100 = 980
        XCTAssertEqual(surfaces.first?.topEdgeY, 980)
    }

    func testWindowSurfaceDetectorDockFiltering() {
        let windows: [WindowInfo] = [
            WindowInfo(windowNumber: 10, ownerName: "Dock", bounds: CGRect(x: 400, y: 1000, width: 800, height: 80), layer: 0, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 20, ownerName: "Notes", bounds: CGRect(x: 100, y: 100, width: 500, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        ]

        let mockProvider = MockWindowInfoProvider(windows: windows)
        let detector = WindowSurfaceDetector(windowProvider: mockProvider)
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Case 1: Dock disabled, Windows enabled
        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = false
        config.accumulateOnWindows = true

        var surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.first?.id, 20)

        // Case 2: Dock enabled, Windows disabled
        config.accumulateOnDock = true
        config.accumulateOnWindows = false

        surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.first?.id, 10)
        XCTAssertTrue(surfaces.first?.isDock == true)
    }

    func testZeroTCCWindowQuerying_viaMockWindowInfoProvider() {
        // Feature 1: Zero-TCC Window Querying
        let windows: [WindowInfo] = [
            WindowInfo(windowNumber: 42, ownerName: "TextEdit", bounds: CGRect(x: 150, y: 100, width: 600, height: 450), layer: 0, alpha: 1.0, isOnScreen: true)
        ]
        let mockProvider = MockWindowInfoProvider(windows: windows)
        let detector = WindowSurfaceDetector(windowProvider: mockProvider)

        let surfaces = detector.detectSurfaces(screenRect: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertTrue(surfaces.contains(where: { $0.id == 42 }))
    }

    func testCoordinateSystemInversion_quartzToCocoa() {
        // Feature 3: Coordinate System Inversion (Quartz top-left to Cocoa bottom-left)
        let windows = [
            WindowInfo(windowNumber: 101, ownerName: "App", bounds: CGRect(x: 200, y: 50, width: 500, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        XCTAssertEqual(surfaces.count, 1)
        let s = surfaces[0]
        XCTAssertEqual(s.topEdgeY, 1030) // 1080 - 50 = 1030
        XCTAssertEqual(s.frame.minY, 730) // 1030 - 300 = 730
        XCTAssertEqual(s.minX, 200)
        XCTAssertEqual(s.maxX, 700)
    }

    func testDockSurfaceExtraction_fromWindowAndVisibleFrame() {
        // Feature 4: Dock extraction via visibleFrame inset fallback
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = CGRect(x: 0, y: 85, width: 1920, height: 970) // 85pt bottom Dock

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = true

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame, primaryScreenHeight: 1080, config: config)

        XCTAssertEqual(surfaces.count, 1)
        let dockSurface = surfaces[0]
        XCTAssertTrue(dockSurface.isDock)
        XCTAssertEqual(dockSurface.topEdgeY, 85)
        XCTAssertEqual(dockSurface.minX, 0)
        XCTAssertEqual(dockSurface.maxX, 1920)
    }

    func testBottomDisplayShelf_baselineLedge() {
        // Feature 5: Bottom display shelf (id: 0, spanning width)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = true
        config.accumulateOnWindows = false
        config.accumulateOnDock = false

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1440, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces[0].id, 0)
        XCTAssertEqual(surfaces[0].topEdgeY, 0)
        XCTAssertEqual(surfaces[0].minX, 0)
        XCTAssertEqual(surfaces[0].maxX, 2560)
        XCTAssertFalse(surfaces[0].isDock)
    }

    func testWindowOcclusionCulling_completeAndPartialOcclusion() {
        // Feature 6: Window Occlusion Culling via 1D interval subtraction algorithm
        // Window A: frontmost (z=0), frame (200, 100, 800, 600) in Quartz
        // Cocoa topEdge = 980, bottom = 380, X in [200, 1000]
        let winA = WindowInfo(windowNumber: 1, ownerName: "Front", bounds: CGRect(x: 200, y: 100, width: 800, height: 600), layer: 0, alpha: 1.0, isOnScreen: true)

        // Window B: behind A (z=1), frame (300, 200, 500, 400) in Quartz
        // Cocoa topEdge = 880, bottom = 480, X in [300, 800]. Completely inside A's bounds -> CULLED!
        let winB = WindowInfo(windowNumber: 2, ownerName: "Occluded", bounds: CGRect(x: 300, y: 200, width: 500, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)

        // Window C: behind A (z=2), frame (100, 250, 400, 400) in Quartz
        // Cocoa topEdge = 830, bottom = 430, X in [100, 500].
        // Window A overlaps X in [200, 500]. Unoccluded segment [100, 200] has width 100 >= 40 -> RETAINED!
        let winC = WindowInfo(windowNumber: 3, ownerName: "PartiallyVisible", bounds: CGRect(x: 100, y: 250, width: 400, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [winA, winB, winC]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        // Window B must be culled completely
        XCTAssertFalse(surfaces.contains(where: { $0.id == 2 }), "Completely occluded Window B must be culled")

        // Window A must be present in full
        guard let sA = surfaces.first(where: { $0.id == 1 }) else {
            XCTFail("Window A must be present")
            return
        }
        XCTAssertEqual(sA.minX, 200)
        XCTAssertEqual(sA.maxX, 1000)

        // Window C must be present with cropped ledge [100, 200]
        guard let sC = surfaces.first(where: { $0.id == 3 }) else {
            XCTFail("Partially occluded Window C must be present")
            return
        }
        XCTAssertEqual(sC.minX, 100)
        XCTAssertEqual(sC.maxX, 200)
    }

    // MARK: - 4. Directional Wind Acceleration & Speed Tests (Features 10, 11)

    func testDirectionalWindAcceleration_trigonometric360() {
        // Feature 10: 360° Directional Wind Acceleration Trigonometry
        let baseGravity: CGFloat = 120.0
        let speed: Double = 1.0 // 200 px/s²

        // 0° (East: +X, normal gravity)
        let (ax0, ay0) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(ax0, 200.0, accuracy: 0.001)
        XCTAssertEqual(ay0, -baseGravity, accuracy: 0.001)

        // 90° (Down / South: 0 X, boosted downward gravity)
        let (ax90, ay90) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(ax90, 0.0, accuracy: 0.001)
        XCTAssertEqual(ay90, -baseGravity - 200.0, accuracy: 0.001)

        // 180° (West: -X, normal gravity)
        let (ax180, ay180) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 180, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(ax180, -200.0, accuracy: 0.001)
        XCTAssertEqual(ay180, -baseGravity, accuracy: 0.001)

        // 270° (Up / North: 0 X, updraft opposing gravity)
        let (ax270, ay270) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(ax270, 0.0, accuracy: 0.001)
        XCTAssertEqual(ay270, -baseGravity + 200.0, accuracy: 0.001)
    }

    func testWindSpeedVariation_linearScaling() {
        // Feature 11: Wind Speed Variation from 0 to 600 px/s²
        let baseGravity: CGFloat = 100.0

        let (axMin, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0, windSpeed: 0.0, baseGravity: baseGravity)
        XCTAssertEqual(axMin, 0.0, accuracy: 0.001)

        let (axMid, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0, windSpeed: 1.5, baseGravity: baseGravity)
        XCTAssertEqual(axMid, 300.0, accuracy: 0.001)

        let (axMax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0, windSpeed: 3.0, baseGravity: baseGravity)
        XCTAssertEqual(axMax, 600.0, accuracy: 0.001)
    }

    // MARK: - 5. Heightmap Accumulation, Repose Smoothing & Caps (Features 12, 13, 14, 15)

    func testColumnBasedHeightmapAccumulation_10pxBins() {
        // Feature 12: Column-Based Heightmap Accumulation with 10px binning
        var heightmap = SurfaceHeightmap(surfaceID: 10, width: 800)
        XCTAssertEqual(heightmap.bins.count, 80)
        XCTAssertEqual(heightmap.averageDepth, 0)

        // Accumulate snow
        heightmap.accumulate(rate: 2.0, maxCap: 22.0)
        XCTAssertTrue(heightmap.averageDepth > 0)
        XCTAssertTrue(heightmap.maxDepth <= 22.0)

        // Resize window: preserves existing bins
        let oldFirst = heightmap.bins[0]
        heightmap.resize(to: 1000)
        XCTAssertEqual(heightmap.bins.count, 100)
        XCTAssertEqual(heightmap.bins[0], oldFirst)
    }

    func testAngleOfReposeSmoothing_symmetricThreePointConvolution() {
        // Feature 13: Angle of Repose Smoothing preserves symmetry via double-buffering
        let symmetricInput: [CGFloat] = [0.0, 10.0, 10.0, 10.0, 0.0]
        let smoothed = SurfaceHeightmap.convolve(bins: symmetricInput)

        XCTAssertEqual(smoothed.count, symmetricInput.count)
        // Check symmetry: left shoulder == right shoulder
        XCTAssertEqual(smoothed[1], smoothed[3], accuracy: 0.001, "Angle of repose convolution must be strictly symmetric")
        XCTAssertEqual(smoothed[0], smoothed[4], accuracy: 0.001, "Tapered edge boundaries must be strictly symmetric")
        XCTAssertEqual(smoothed[2], 10.0, accuracy: 0.001)
    }

    func testWindowMovementReanchoring_deltaTracking() {
        // Feature 14: Window Movement Re-anchoring via delta (dx, dy)
        var heightmap = SurfaceHeightmap(surfaceID: 55, width: 400, anchorPosition: CGPoint(x: 100, y: 500))
        heightmap.bins = Array(repeating: 15.0, count: 40)

        let delta = heightmap.reanchor(newAnchor: CGPoint(x: 160, y: 540))
        XCTAssertEqual(delta.dx, 60.0)
        XCTAssertEqual(delta.dy, 40.0)
        XCTAssertEqual(heightmap.anchorPosition, CGPoint(x: 160, y: 540))

        // Depth values remain preserved across movement
        XCTAssertEqual(heightmap.averageDepth, 15.0)
    }

    func testSurfaceAccumulationCap_windowAndBottomLedges() {
        // Feature 15: Surface Accumulation Caps
        let screenHeight: CGFloat = 1080

        let bottomLedge = CollisionSurface(id: 0, frame: .zero, topEdgeY: 0, minX: 0, maxX: 1920, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: bottomLedge, screenHeight: screenHeight), 50.0)

        let dockLedge = CollisionSurface(id: 1, frame: .zero, topEdgeY: 85, minX: 0, maxX: 1920, isDock: true)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: dockLedge, screenHeight: screenHeight), 30.0)

        let windowLedge = CollisionSurface(id: 2, frame: .zero, topEdgeY: 600, minX: 100, maxX: 800, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: windowLedge, screenHeight: screenHeight), 22.0)

        // Near screen ceiling: cap cannot exceed distance to top of screen
        let ceilingLedge = CollisionSurface(id: 3, frame: .zero, topEdgeY: 1075, minX: 100, maxX: 800, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: ceilingLedge, screenHeight: screenHeight), 5.0)
    }

    // MARK: - 6. Controller, Overlay Window & Lifecycle Tests (Features 7, 8, Multi-Monitor, Power)

    @MainActor
    func testCentralized10HzPollingThrottle() {
        // Feature 7: Centralized 10 Hz Polling Throttle
        var config = FlakeConfiguration()
        config.isEnabled = true
        config.layerMode = .overlay

        let mockDetector = MockWindowSurfaceDetector(surfaces: [])
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))])

        let controller = FlakeController(
            config: config,
            screenProvider: mockScreens,
            surfaceDetector: mockDetector
        )
        defer { controller.terminate() }

        XCTAssertEqual(controller.overlayWindows.count, 1)

        // Polling works
        controller.pollSurfaces()

        // Pause stops polling
        controller.setPaused(true)
        XCTAssertTrue(controller.isPaused)

        // Resume restarts polling
        controller.setPaused(false)
        XCTAssertFalse(controller.isPaused)
    }

    @MainActor
    func testFlakeController_multiMonitorLifecycleWithMockScreenProvider() {
        var config = FlakeConfiguration()
        config.isEnabled = true
        config.layerMode = .overlay

        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])

        let controller = FlakeController(
            config: config,
            screenProvider: mockScreens
        )
        defer { controller.terminate() }

        XCTAssertEqual(controller.overlayWindows.count, 2)

        // Simulate disconnecting screen 2
        mockScreens.screens = [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        controller.rebuildOverlayWindows()
        XCTAssertEqual(controller.overlayWindows.count, 1)
        XCTAssertNotNil(controller.overlayWindows[1])
        XCTAssertNil(controller.overlayWindows[2])

        // Simulate resolution change on screen 1
        mockScreens.screens = [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))]
        controller.rebuildOverlayWindows()
        XCTAssertEqual(controller.overlayWindows[1]?.frame.size, CGSize(width: 2560, height: 1440))
    }

    @MainActor
    func testFlakeController_powerManagerDelegateSync() {
        var config = FlakeConfiguration()
        config.isEnabled = true
        config.layerMode = .overlay

        let powerManager = MockPowerManager()
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))])

        let controller = FlakeController(
            config: config,
            powerManager: powerManager,
            screenProvider: mockScreens
        )
        defer { controller.terminate() }

        XCTAssertFalse(controller.isPaused)

        // Add display sleeping pause reason
        powerManager.addPauseReason(.displaySleeping)
        XCTAssertTrue(controller.isPaused)

        // Clear pause reason
        powerManager.removePauseReason(.displaySleeping)
        XCTAssertFalse(controller.isPaused)
    }

    @MainActor
    func testFlakeOverlayWindowProperties() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var config = FlakeConfiguration()
        config.isEnabled = true
        config.activeTool = .none

        let overlay = FlakeOverlayWindow(frame: frame, config: config)
        defer { overlay.close() }

        XCTAssertEqual(overlay.level, .floating)
        XCTAssertFalse(overlay.isOpaque)
        XCTAssertEqual(overlay.backgroundColor, .clear)
        XCTAssertTrue(overlay.ignoresMouseEvents, "Clicks must pass through by default when tool is none")

        // Switch to Mitten tool
        overlay.flakeScene.config.activeTool = .mitten
        overlay.updateMouseInteractivity()
        XCTAssertFalse(overlay.ignoresMouseEvents, "Window must accept mouse events when tool is active")

        // Revert back
        overlay.flakeScene.config.activeTool = .none
        overlay.updateMouseInteractivity()
        XCTAssertTrue(overlay.ignoresMouseEvents)
    }

    @MainActor
    func testFlakeSceneSnowClearingAndSnowplow() {
        let scene = FlakeScene(size: CGSize(width: 800, height: 600))
        var config = FlakeConfiguration()
        config.isEnabled = true
        scene.config = config

        XCTAssertFalse(scene.isPaused)

        // Clear all snow
        scene.clearAllSnow()

        // Trigger snowplow sweep
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    @MainActor
    func testFlakeControllerLifecycleAndPause() {
        var config = FlakeConfiguration()
        config.isEnabled = false // Headless mock safety

        let controller = FlakeController(config: config)
        XCTAssertTrue(controller.overlayWindows.isEmpty)

        // Toggle pause state
        controller.setPaused(true)
        XCTAssertTrue(controller.isPaused)
        controller.setPaused(false)
        XCTAssertFalse(controller.isPaused)
        controller.clearAllSnow()
    }
}
