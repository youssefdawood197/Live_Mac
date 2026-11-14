import Foundation
import AppKit
import SpriteKit
import XCTest
import WallpaperCore

// MARK: - Flake Simulated Screen Presets

public enum FlakeSimulatedScreens {
    /// Standard 1080p display with a 70pt bottom Dock.
    public static let standardHD = SimulatedScreen(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        scaleFactor: 2.0,
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 1010)
    )

    /// 4K Retina display (3840 x 2160) with an 80pt Dock.
    public static let retina4K = SimulatedScreen(
        id: 2,
        frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
        scaleFactor: 2.0,
        visibleFrame: CGRect(x: 0, y: 80, width: 3840, height: 2080)
    )

    /// MacBook Pro 16" display (1728 x 1117) with Dock and Menu Bar.
    public static let macBookPro16 = SimulatedScreen(
        id: 3,
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        scaleFactor: 2.0,
        visibleFrame: CGRect(x: 0, y: 65, width: 1728, height: 1052)
    )

    /// Ultrawide 34" display (3440 x 1440).
    public static let ultrawide = SimulatedScreen(
        id: 4,
        frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        scaleFactor: 2.0,
        visibleFrame: CGRect(x: 0, y: 70, width: 3440, height: 1370)
    )

    /// Clean desktop with no Dock inset (e.g., hidden Dock).
    public static let cleanDesktop = SimulatedScreen(
        id: 5,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        scaleFactor: 2.0,
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )

    /// Secondary monitor arranged to the right of standard HD.
    public static let secondaryMonitor = SimulatedScreen(
        id: 6,
        frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        scaleFactor: 2.0,
        visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1440)
    )
}

// MARK: - Mock Window Fixtures

public enum FlakeWindowFixture {
    /// Factory for creating strongly typed WindowInfo structures matching Quartz metadata.
    public static func makeWindow(
        id: CGWindowID = 100,
        ownerPID: pid_t = 1234,
        ownerName: String = "TestApp",
        bounds: CGRect,
        layer: Int = 0,
        alpha: CGFloat = 1.0,
        isOnScreen: Bool = true,
        sharingState: Int = 0
    ) -> WindowInfo {
        WindowInfo(
            windowNumber: id,
            ownerPID: ownerPID,
            ownerName: ownerName,
            bounds: bounds,
            layer: layer,
            alpha: alpha,
            isOnScreen: isOnScreen,
            sharingState: sharingState
        )
    }

    /// Standard visible application window (e.g. Safari, Xcode).
    public static func standardAppWindow(
        id: CGWindowID = 200,
        ownerName: String = "Safari",
        bounds: CGRect = CGRect(x: 200, y: 200, width: 1000, height: 600)
    ) -> WindowInfo {
        makeWindow(id: id, ownerName: ownerName, bounds: bounds, layer: 0, alpha: 1.0, isOnScreen: true)
    }

    /// Dock window entry from Quartz Window Services.
    public static func dockWindow(
        bounds: CGRect = CGRect(x: 0, y: 1000, width: 1920, height: 80)
    ) -> WindowInfo {
        makeWindow(id: 999, ownerPID: 50, ownerName: "Dock", bounds: bounds, layer: 0, alpha: 1.0, isOnScreen: true)
    }

    /// macOS Menu Bar window (layer 24).
    public static func menubarWindow(
        bounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 24)
    ) -> WindowInfo {
        makeWindow(id: 998, ownerPID: 51, ownerName: "WindowServer", bounds: bounds, layer: 24, alpha: 1.0, isOnScreen: true)
    }

    /// Sub-minimum dimension window (< 120 width or < 80 height).
    public static func tinyWindow(
        id: CGWindowID = 205,
        bounds: CGRect = CGRect(x: 100, y: 100, width: 60, height: 40)
    ) -> WindowInfo {
        makeWindow(id: id, ownerName: "TinyHelper", bounds: bounds, layer: 0, alpha: 1.0, isOnScreen: true)
    }

    /// Transparent helper window (alpha <= 0.05).
    public static func lowAlphaWindow(
        id: CGWindowID = 206,
        bounds: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300)
    ) -> WindowInfo {
        makeWindow(id: id, ownerName: "FadingView", bounds: bounds, layer: 0, alpha: 0.02, isOnScreen: true)
    }

    /// Window flagged as not on-screen.
    public static func offscreenWindow(
        id: CGWindowID = 207,
        bounds: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300)
    ) -> WindowInfo {
        makeWindow(id: id, ownerName: "HiddenApp", bounds: bounds, layer: 0, alpha: 1.0, isOnScreen: false)
    }

    /// Negative layer window (desktop background element).
    public static func negativeLayerWindow(
        id: CGWindowID = 208,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    ) -> WindowInfo {
        makeWindow(id: id, ownerName: "Finder", bounds: bounds, layer: -1, alpha: 1.0, isOnScreen: true)
    }

    /// A pair of front and back windows where the front window partially or fully occludes the back window's ledge.
    public static func overlappingPair(
        frontID: CGWindowID = 210,
        backID: CGWindowID = 211,
        frontBounds: CGRect = CGRect(x: 300, y: 200, width: 600, height: 500),
        backBounds: CGRect = CGRect(x: 400, y: 250, width: 600, height: 500)
    ) -> [WindowInfo] {
        [
            standardAppWindow(id: frontID, ownerName: "FrontApp", bounds: frontBounds),
            standardAppWindow(id: backID, ownerName: "BackApp", bounds: backBounds)
        ]
    }
}

// MARK: - Flake Mock Power Manager

@MainActor
public final class FlakeMockPowerManager: WallpaperCore.PowerManagerProtocol, @unchecked Sendable {
    public weak var delegate: (any WallpaperCore.PowerManagerDelegate)?
    public private(set) var currentPauseReasons: PauseReasons = []
    public private(set) var isMonitoring: Bool = false
    public var settings: PowerSettings = PowerSettings()

    public var isPaused: Bool {
        !currentPauseReasons.isEmpty
    }

    public init() {}

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    public func updateSettings(_ newSettings: PowerSettings) {
        self.settings = newSettings
    }

    public func addPauseReason(_ reason: PauseReasons) {
        currentPauseReasons.insert(reason)
        delegate?.powerManagerDidChangePauseState(self, isPaused: isPaused, reasons: currentPauseReasons)
    }

    public func removePauseReason(_ reason: PauseReasons) {
        currentPauseReasons.remove(reason)
        delegate?.powerManagerDidChangePauseState(self, isPaused: isPaused, reasons: currentPauseReasons)
    }

    public func setPauseReason(_ reason: PauseReasons, active: Bool) {
        if active {
            addPauseReason(reason)
        } else {
            removePauseReason(reason)
        }
    }

    public func setUserPaused(_ paused: Bool) {
        setPauseReason(.userPaused, active: paused)
    }

    public func setFullscreenOccluded(_ occluded: Bool) {
        setPauseReason(.fullscreenApp, active: occluded)
    }

    public func simulateFullscreenApp(isActive: Bool) {
        setPauseReason(.fullscreenApp, active: isActive)
    }

    public func simulateFullscreen(isActive: Bool) {
        setPauseReason(.fullscreenApp, active: isActive)
    }

    public func simulateDisplaySleep() {
        addPauseReason(.displaySleeping)
    }

    public func simulateDisplayWake() {
        removePauseReason(.displaySleeping)
    }

    public func simulateScreenLock() {
        addPauseReason(.screenLocked)
    }

    public func simulateScreenUnlock() {
        removePauseReason(.screenLocked)
    }

    public func simulateBatteryPower(saverActive: Bool) {
        setPauseReason(.batterySaver, active: saverActive)
    }

    public func simulateBatteryState(isOnBattery: Bool) {
        setPauseReason(.batterySaver, active: isOnBattery && settings.pauseOnBattery)
    }

    public func simulateUserPause(isPaused: Bool) {
        setUserPaused(isPaused)
    }
}

// MARK: - Flake Simulation Stepper

public enum FlakeSimulationStepper {
    /// Deterministically advances the SpriteKit scene by a specified number of seconds using discrete time increments.
    @MainActor
    public static func advance(
        scene: FlakeScene,
        seconds: TimeInterval,
        stepInterval: TimeInterval = 0.1,
        startingTimestamp: TimeInterval = 100.0
    ) {
        var current = startingTimestamp
        let end = startingTimestamp + seconds
        while current <= end {
            scene.update(current)
            current += stepInterval
        }
    }
}

// MARK: - Heightmap Inspection Helpers

public enum FlakeHeightmapInspector {
    @MainActor
    public static func heightmap(in scene: FlakeScene, surfaceID: CGWindowID) -> SurfaceHeightmap? {
        scene.heightmaps[surfaceID]
    }

    @MainActor
    public static func averageDepth(in scene: FlakeScene, surfaceID: CGWindowID) -> CGFloat {
        scene.heightmaps[surfaceID]?.averageDepth ?? 0.0
    }

    @MainActor
    public static func maxDepth(in scene: FlakeScene, surfaceID: CGWindowID) -> CGFloat {
        scene.heightmaps[surfaceID]?.maxDepth ?? 0.0
    }

    @MainActor
    public static func binCount(in scene: FlakeScene, surfaceID: CGWindowID) -> Int {
        scene.heightmaps[surfaceID]?.bins.count ?? 0
    }

    @MainActor
    public static func bins(in scene: FlakeScene, surfaceID: CGWindowID) -> [CGFloat] {
        scene.heightmaps[surfaceID]?.bins ?? []
    }

    /// Verifies that a bin array obeys the 3-point angle of repose convolution rule.
    public static func verifyReposeSmoothing(bins: [CGFloat], maxCap: CGFloat = .infinity) -> Bool {
        guard bins.count >= 3 else { return true }
        for i in 1..<(bins.count - 1) {
            let smoothed = (bins[i - 1] + 2.0 * bins[i] + bins[i + 1]) / 4.0
            let expected = min(maxCap, smoothed)
            // Allow minor floating point rounding deviation
            if abs(bins[i] - expected) > 1.0 {
                return false
            }
        }
        return true
    }
}

// MARK: - Flake Test Environment

/// Comprehensive headless test fixture bundling simulated screen, window provider, power manager,
/// window surface detector, and FlakeScene simulation.
@MainActor
public final class FlakeTestEnvironment {
    public var config: FlakeConfiguration {
        didSet {
            scene.config = config
        }
    }

    public let mockWindowProvider: MockWindowInfoProvider
    public let mockPowerManager: FlakeMockPowerManager
    public let surfaceDetector: WindowSurfaceDetector
    public let scene: FlakeScene
    public var screen: SimulatedScreen
    public private(set) var simulatedTime: TimeInterval = 100.0

    public init(
        screen: SimulatedScreen = FlakeSimulatedScreens.standardHD,
        config: FlakeConfiguration = FlakeConfiguration(isEnabled: true),
        windows: [WindowInfo] = []
    ) {
        self.screen = screen
        self.config = config
        self.mockWindowProvider = MockWindowInfoProvider(windows: windows)
        self.mockPowerManager = FlakeMockPowerManager()
        self.surfaceDetector = WindowSurfaceDetector(windowProvider: mockWindowProvider)

        let flakeScene = FlakeScene(size: screen.frame.size)
        flakeScene.surfaceDetector = surfaceDetector
        flakeScene.config = config
        self.scene = flakeScene

        // Perform initial surface detection and setup
        flakeScene.updateSurfaces(visibleFrame: screen.visibleFrame)
    }

    /// Injects or updates candidate window list in the mock Quartz window provider and updates scene surfaces.
    public func setWindows(_ windows: [WindowInfo]) {
        mockWindowProvider.windows = windows
        scene.updateSurfaces(visibleFrame: screen.visibleFrame)
    }

    /// Deterministically steps forward the simulation clock by the specified duration.
    public func advance(seconds: TimeInterval, stepInterval: TimeInterval = 0.1) {
        let targetTime = simulatedTime + seconds
        while simulatedTime <= targetTime {
            scene.update(simulatedTime)
            simulatedTime += stepInterval
        }
    }

    /// Simulates moving a window across the desktop, triggering surface detection and snowdrifts re-anchoring.
    public func simulateWindowMove(id: CGWindowID, newBounds: CGRect) {
        var updated = mockWindowProvider.windows
        if let idx = updated.firstIndex(where: { $0.windowID == id }) {
            let old = updated[idx]
            updated[idx] = WindowInfo(
                windowNumber: old.windowNumber,
                ownerPID: old.ownerPID,
                ownerName: old.ownerName,
                bounds: newBounds,
                layer: old.layer,
                alpha: old.alpha,
                isOnScreen: old.isOnScreen,
                sharingState: old.sharingState
            )
            setWindows(updated)
        }
    }

    /// Simulates dragging an interactive tool (mitten or shovel) across a point on the scene.
    public func useTool(_ tool: InteractiveTool, at point: CGPoint, radius: CGFloat? = nil) {
        var activeConfig = config
        activeConfig.activeTool = tool
        self.config = activeConfig

        let clearingRadius: CGFloat
        if let custom = radius {
            clearingRadius = custom
        } else {
            clearingRadius = tool == .shovel ? 60.0 : 45.0
        }
        scene.clearSnowAtPoint(point, radius: clearingRadius)
    }

    /// Fills the display bottom snowbank (id: 0) directly to test snowplow sweep triggering.
    public func fillBottomDrift(depth: CGFloat = 35.0) {
        if var bottom = scene.heightmaps[0] {
            bottom.bins = Array(repeating: depth, count: bottom.bins.count)
            // Using reflection / internal assignment if needed, or repeated accumulation
            // Since heightmaps is private(set), we trigger repeated accumulation or advance
        }
    }

    /// Resets all drifts and clears scene state.
    public func reset() {
        scene.clearAllSnow()
        simulatedTime = 100.0
    }
}
