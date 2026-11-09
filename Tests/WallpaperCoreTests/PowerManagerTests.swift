import XCTest
import AppKit
import CoreGraphics
@testable import WallpaperCore

@MainActor
final class PowerManagerTests: XCTestCase {

    // MARK: - Test Doubles

    private final class MockDesktopWindowManager: DesktopWindowManagerProtocol {
        var isInteractive: Bool = false
        var activeWallpaper: WallpaperItem?
        var windows: [CGDirectDisplayID: DesktopWindow] = [:]
        var engines: [CGDirectDisplayID: WallpaperEngine] = [:]
        var isPaused: Bool = false
        var isMuted: Bool = false
        var volume: Float = 1.0
        var setPausedCallCount: Int = 0
        var lastPausedValue: Bool?

        func setWallpaper(_ item: WallpaperItem) { self.activeWallpaper = item }
        func setPaused(_ paused: Bool) {
            self.isPaused = paused
            self.lastPausedValue = paused
            self.setPausedCallCount += 1
        }
        func setMuted(_ muted: Bool) { self.isMuted = muted }
        func setVolume(_ volume: Float) { self.volume = volume }
        func reloadDisplays() {}
        func terminate() {}
    }

    private final class MockPowerManagerDelegate: PowerManagerDelegate {
        var changeCount: Int = 0
        var lastIsPaused: Bool?
        var lastReasons: PauseReasons?

        func powerManagerDidChangePauseState(_ manager: PowerManagerProtocol, isPaused: Bool, reasons: PauseReasons) {
            self.changeCount += 1
            self.lastIsPaused = isPaused
            self.lastReasons = reasons
        }
    }

    private final class MockFullscreenDelegate: FullscreenDetectorDelegate {
        var changeCount: Int = 0
        var lastIsOccluded: Bool?
        var lastOccludedIDs: Set<CGDirectDisplayID> = []

        func fullscreenDetectorDidChangeOcclusion(
            _ detector: FullscreenDetectorProtocol,
            isOccluded: Bool,
            occludedDisplayIDs: Set<CGDirectDisplayID>
        ) {
            self.changeCount += 1
            self.lastIsOccluded = isOccluded
            self.lastOccludedIDs = occludedDisplayIDs
        }
    }

    private final class MockBatteryDelegate: BatteryMonitorDelegate {
        var changeCount: Int = 0

        func batteryMonitorDidChangePowerState(_ monitor: BatteryMonitorProtocol) {
            self.changeCount += 1
        }
    }

    // MARK: - 1. PauseReasons OptionSet & Bitmask Tests

    func testPauseReasons_rawValuesAndAllBitsMath() {
        XCTAssertEqual(PauseReasons.userPaused.rawValue, 1)
        XCTAssertEqual(PauseReasons.fullscreenApp.rawValue, 2)
        XCTAssertEqual(PauseReasons.displaySleeping.rawValue, 4)
        XCTAssertEqual(PauseReasons.screenLocked.rawValue, 8)
        XCTAssertEqual(PauseReasons.batterySaver.rawValue, 16)

        let combined: PauseReasons = [.userPaused, .fullscreenApp, .displaySleeping, .screenLocked, .batterySaver]
        XCTAssertEqual(combined.rawValue, 31)
        XCTAssertEqual(combined, PauseReasons.all)
    }

    func testPauseReasons_descriptionReflectsActiveReasons() {
        let empty: PauseReasons = []
        XCTAssertEqual(empty.description, "none")

        let single: PauseReasons = .userPaused
        XCTAssertEqual(single.description, "userPaused")

        let two: PauseReasons = [.fullscreenApp, .batterySaver]
        XCTAssertTrue(two.description.contains("fullscreenApp"))
        XCTAssertTrue(two.description.contains("batterySaver"))

        let all = PauseReasons.all
        XCTAssertTrue(all.description.contains("userPaused"))
        XCTAssertTrue(all.description.contains("fullscreenApp"))
        XCTAssertTrue(all.description.contains("displaySleeping"))
        XCTAssertTrue(all.description.contains("screenLocked"))
        XCTAssertTrue(all.description.contains("batterySaver"))
    }

    func testPauseReasons_additivePropertiesAndRemoval() {
        var reasons: PauseReasons = []
        XCTAssertTrue(reasons.isEmpty)

        reasons.insert(.fullscreenApp)
        XCTAssertFalse(reasons.isEmpty)
        XCTAssertTrue(reasons.contains(.fullscreenApp))

        reasons.insert(.screenLocked)
        XCTAssertEqual(reasons, [.fullscreenApp, .screenLocked])

        reasons.remove(.fullscreenApp)
        XCTAssertEqual(reasons, [.screenLocked])
        XCTAssertFalse(reasons.isEmpty)

        reasons.remove(.screenLocked)
        XCTAssertTrue(reasons.isEmpty)
    }

    // MARK: - 2. FullscreenDetector Tests

    func testFullscreenDetector_emptyWindowList_notOccluded() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let windowProvider = MockWindowInfoProvider(windows: [])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertFalse(detector.checkFullscreenState())
        XCTAssertFalse(detector.isOccluded)
        XCTAssertFalse(detector.isAnyScreenOccluded)
        XCTAssertTrue(detector.occludedDisplayIDs.isEmpty)
    }

    func testFullscreenDetector_partialWindow_notOccluded() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let partialWindow = WindowInfo(
            windowNumber: 101,
            ownerPID: 1234,
            ownerName: "Safari",
            bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [partialWindow])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertFalse(detector.checkFullscreenState())
        XCTAssertFalse(detector.isOccluded)
        XCTAssertTrue(detector.occludedDisplayIDs.isEmpty)
    }

    func testFullscreenDetector_singleDisplayFullscreen_occluded() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let fullscreenWindow = WindowInfo(
            windowNumber: 202,
            ownerPID: 5678,
            ownerName: "GameApp",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [fullscreenWindow])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertTrue(detector.checkFullscreenState())
        XCTAssertTrue(detector.isOccluded)
        XCTAssertTrue(detector.isAnyScreenOccluded)
        XCTAssertEqual(detector.occludedDisplayIDs, [1])
        XCTAssertTrue(detector.isScreenOccluded(displayID: 1))
    }

    func testFullscreenDetector_dockLayer20FilteredOut() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        // Dock reports full screen bounds at Layer 20
        let dockWindow = WindowInfo(
            windowNumber: 999,
            ownerPID: 99,
            ownerName: "Dock",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 20,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [dockWindow])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertFalse(detector.checkFullscreenState())
        XCTAssertFalse(detector.isOccluded)
        XCTAssertTrue(detector.occludedDisplayIDs.isEmpty)
    }

    func testFullscreenDetector_menuBarLayersFilteredOut() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let menuBar24 = WindowInfo(
            windowNumber: 50,
            ownerPID: 1,
            ownerName: "WindowServer",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 24,
            alpha: 1.0,
            isOnScreen: true
        )
        let menuBar25 = WindowInfo(
            windowNumber: 51,
            ownerPID: 1,
            ownerName: "WindowServer",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 25,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [menuBar24, menuBar25])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertFalse(detector.checkFullscreenState())
        XCTAssertFalse(detector.isOccluded)
    }

    func testFullscreenDetector_selfPIDFilteredOut() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfWindow = WindowInfo(
            windowNumber: 301,
            ownerPID: selfPID,
            ownerName: "LivelyWallpaper",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [selfWindow])
        let detector = FullscreenDetector(
            screenProvider: screenProvider,
            windowInfoProvider: windowProvider,
            currentProcessPID: selfPID
        )

        XCTAssertFalse(detector.checkFullscreenState())
        XCTAssertFalse(detector.isOccluded)
        XCTAssertTrue(detector.occludedDisplayIDs.isEmpty)
    }

    func testFullscreenDetector_transparentOverlayFilteredOut() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        // Overlay with alpha 0.5 (< 0.85 threshold)
        let transparentOverlay = WindowInfo(
            windowNumber: 401,
            ownerPID: 777,
            ownerName: "Dimmer",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 0.5,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [transparentOverlay])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertFalse(detector.checkFullscreenState())

        // Now with opaque alpha 0.95
        let opaqueOverlay = WindowInfo(
            windowNumber: 402,
            ownerPID: 778,
            ownerName: "Game",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 0.95,
            isOnScreen: true
        )
        windowProvider.windows = [opaqueOverlay]
        XCTAssertTrue(detector.checkFullscreenState())
        XCTAssertTrue(detector.isOccluded)
    }

    func testFullscreenDetector_multiDisplayPartialOcclusion() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        // Fullscreen window only covering screen 1 in Quartz coordinates (0, 0, 1920, 1080)
        let screen1Window = WindowInfo(
            windowNumber: 601,
            ownerPID: 888,
            ownerName: "MovieApp",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [screen1Window])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertTrue(detector.checkFullscreenState())
        XCTAssertTrue(detector.isOccluded)
        XCTAssertEqual(detector.occludedDisplayIDs, [1])
        XCTAssertTrue(detector.isScreenOccluded(displayID: 1))
        XCTAssertFalse(detector.isScreenOccluded(displayID: 2))
    }

    func testFullscreenDetector_negativeOriginDisplay_calculatedProperly() {
        // Multi-display layout: Screen 2 is positioned to the left of Screen 1
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        ])
        // Fullscreen window covering Screen 2 (Quartz bounds: x: -1920, y: 0, w: 1920, h: 1080)
        let screen2Window = WindowInfo(
            windowNumber: 701,
            ownerPID: 999,
            ownerName: "SecondaryGame",
            bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [screen2Window])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertTrue(detector.checkFullscreenState())
        XCTAssertTrue(detector.isScreenOccluded(displayID: 2))
        XCTAssertFalse(detector.isScreenOccluded(displayID: 1))
    }

    func testFullscreenDetector_borderlessGame5ptTolerance() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        // Borderless game window offset by -1 pt and 2 pt larger than display
        let borderlessWindow = WindowInfo(
            windowNumber: 801,
            ownerPID: 1111,
            ownerName: "MetalGame",
            bounds: CGRect(x: -1, y: -1, width: 1922, height: 1082),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let windowProvider = MockWindowInfoProvider(windows: [borderlessWindow])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)

        XCTAssertTrue(detector.checkFullscreenState())
        XCTAssertTrue(detector.isOccluded)
        XCTAssertEqual(detector.occludedDisplayIDs, [1])
    }

    func testFullscreenDetector_delegateFiresOnlyOnStateChange() {
        let screenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let window = WindowInfo(
            windowNumber: 1001,
            ownerPID: 2222,
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            layer: 0,
            alpha: 1.0
        )
        let windowProvider = MockWindowInfoProvider(windows: [window])
        let detector = FullscreenDetector(screenProvider: screenProvider, windowInfoProvider: windowProvider)
        let mockDelegate = MockFullscreenDelegate()
        detector.delegate = mockDelegate

        XCTAssertEqual(mockDelegate.changeCount, 0)

        // First check -> changes state to true
        detector.checkFullscreenState()
        XCTAssertEqual(mockDelegate.changeCount, 1)
        XCTAssertEqual(mockDelegate.lastIsOccluded, true)
        XCTAssertEqual(mockDelegate.lastOccludedIDs, [1])

        // Second check with same windows -> no new delegate call
        detector.checkFullscreenState()
        XCTAssertEqual(mockDelegate.changeCount, 1)

        // Clear window -> state changes to false -> delegate fires once
        windowProvider.windows = []
        detector.checkFullscreenState()
        XCTAssertEqual(mockDelegate.changeCount, 2)
        XCTAssertEqual(mockDelegate.lastIsOccluded, false)
        XCTAssertTrue(mockDelegate.lastOccludedIDs.isEmpty)
    }

    // MARK: - 3. BatteryMonitor Tests

    func testBatteryMonitor_initialStateAndTransition() {
        let mockProvider = MockPowerSourceProvider(isOnBattery: false, isLowPowerMode: false)
        let monitor = BatteryMonitor(provider: mockProvider)
        let delegate = MockBatteryDelegate()
        monitor.delegate = delegate

        XCTAssertFalse(monitor.isOnBattery)
        XCTAssertFalse(monitor.isLowPowerMode)
        XCTAssertFalse(monitor.isBatteryActive)
        XCTAssertEqual(monitor.currentState, .acPower)

        monitor.startMonitoring()
        XCTAssertTrue(monitor.isMonitoring)

        // Trigger unplug event
        mockProvider.updatePowerState(isOnBattery: true)
        XCTAssertTrue(monitor.isOnBattery)
        XCTAssertTrue(monitor.isBatteryActive)
        XCTAssertEqual(monitor.currentState, .batteryPower)
        XCTAssertEqual(delegate.changeCount, 1)

        // Trigger plug-in event
        mockProvider.updatePowerState(isOnBattery: false)
        XCTAssertFalse(monitor.isOnBattery)
        XCTAssertFalse(monitor.isBatteryActive)
        XCTAssertEqual(monitor.currentState, .acPower)
        XCTAssertEqual(delegate.changeCount, 2)

        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testBatteryMonitor_lowPowerModeDetection() {
        let mockProvider = MockPowerSourceProvider(isOnBattery: false, isLowPowerMode: false)
        let monitor = BatteryMonitor(provider: mockProvider)
        let delegate = MockBatteryDelegate()
        monitor.delegate = delegate
        monitor.startMonitoring()

        XCTAssertFalse(monitor.isLowPowerMode)

        // Low power mode enabled on AC
        mockProvider.updatePowerState(isLowPowerMode: true)
        XCTAssertTrue(monitor.isLowPowerMode)
        XCTAssertTrue(monitor.isBatteryActive)
        XCTAssertEqual(delegate.changeCount, 1)

        monitor.stopMonitoring()
    }

    func testBatteryMonitor_snapshotValues() {
        let mockProvider = MockPowerSourceProvider(isOnBattery: true, isLowPowerMode: false)
        mockProvider.mockCapacity = 75
        mockProvider.mockMaxCapacity = 100
        mockProvider.mockIsCharging = false
        mockProvider.mockTimeToEmpty = 150

        let monitor = BatteryMonitor(provider: mockProvider)
        let snapshot = monitor.currentSnapshot

        XCTAssertEqual(snapshot.powerSourceState, .batteryPower)
        XCTAssertTrue(snapshot.isOnBattery)
        XCTAssertFalse(snapshot.isLowPowerMode)
        XCTAssertEqual(snapshot.currentCapacity, 75)
        XCTAssertEqual(snapshot.maxCapacity, 100)
        XCTAssertEqual(snapshot.isCharging, false)
        XCTAssertEqual(snapshot.timeToEmptyMinutes, 150)
    }

    // MARK: - 4. PowerManager Tests

    func testPowerManager_initialStateClean() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )

        XCTAssertTrue(manager.currentPauseReasons.isEmpty)
        XCTAssertFalse(manager.isPaused)
        XCTAssertFalse(manager.isMonitoring)
    }

    func testPowerManager_displaySleepAndWake() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        let delegate = MockPowerManagerDelegate()
        manager.delegate = delegate
        manager.startMonitoring()

        // Display sleep notification
        mockWS.post(name: NSWorkspace.screensDidSleepNotification)
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons, [.displaySleeping])
        XCTAssertEqual(delegate.lastIsPaused, true)
        XCTAssertEqual(delegate.lastReasons, [.displaySleeping])

        // Display wake notification
        mockWS.post(name: NSWorkspace.screensDidWakeNotification)
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)
        XCTAssertEqual(delegate.lastIsPaused, false)

        manager.stopMonitoring()
    }

    func testPowerManager_screenLockAndUnlock() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        // Screen lock notification
        mockDist.post(name: NSNotification.Name("com.apple.screenIsLocked"))
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons, [.screenLocked])

        // Screen unlock notification
        mockDist.post(name: NSNotification.Name("com.apple.screenIsUnlocked"))
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }

    func testPowerManager_screensaverLockAndUnlock() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        // Screensaver starts
        mockDist.post(name: NSNotification.Name("com.apple.screensaver.didstart"))
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons, [.screenLocked])

        // Screensaver stops
        mockDist.post(name: NSNotification.Name("com.apple.screensaver.didstop"))
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }

    func testPowerManager_concurrentAdditiveReasons_wakeDoesNotUnpauseWhileLocked() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        // 1. Screen lock
        mockDist.post(name: NSNotification.Name("com.apple.screenIsLocked"))
        XCTAssertEqual(manager.currentPauseReasons, [.screenLocked])

        // 2. Display sleep while locked
        mockWS.post(name: NSWorkspace.screensDidSleepNotification)
        XCTAssertEqual(manager.currentPauseReasons, [.screenLocked, .displaySleeping])

        // 3. User moves mouse -> Display wakes, but screen is STILL locked
        mockWS.post(name: NSWorkspace.screensDidWakeNotification)
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons, [.screenLocked])

        // 4. User unlocks with Touch ID / Password
        mockDist.post(name: NSNotification.Name("com.apple.screenIsUnlocked"))
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }

    func testPowerManager_allFiveReasonsSimultaneousAndReverseClear() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.settings.pauseOnBattery = true
        manager.startMonitoring()

        manager.setUserPaused(true)
        manager.simulateFullscreenApp(isActive: true)
        manager.simulateDisplaySleep()
        manager.simulateScreenLock()
        manager.simulateBatteryPower(saverActive: true)

        XCTAssertEqual(manager.currentPauseReasons.rawValue, 31)
        XCTAssertTrue(manager.isPaused)

        // Clear reasons one by one in reverse order
        manager.simulateBatteryPower(saverActive: false)
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons.rawValue, 15)

        manager.simulateScreenUnlock()
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons.rawValue, 7)

        manager.simulateDisplayWake()
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons.rawValue, 3)

        manager.simulateFullscreenApp(isActive: false)
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons.rawValue, 1)

        // Final reason cleared -> resumes playback
        manager.setUserPaused(false)
        XCTAssertFalse(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons.rawValue, 0)

        manager.stopMonitoring()
    }

    func testPowerManager_userPausePreservedAcrossMonitoringCycle() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        manager.setUserPaused(true)
        manager.simulateDisplaySleep()
        XCTAssertEqual(manager.currentPauseReasons, [.userPaused, .displaySleeping])

        // Stopping monitoring clears automatic environmental reasons, but userPaused MUST survive
        manager.stopMonitoring()
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons, [.userPaused])

        // User explicitly resumes
        manager.setUserPaused(false)
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)
    }

    func testPowerManager_duplicateReasonInsertionIsIdempotent() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        let delegate = MockPowerManagerDelegate()
        manager.delegate = delegate
        manager.startMonitoring()

        manager.addPauseReason(.fullscreenApp)
        XCTAssertEqual(delegate.changeCount, 1)

        // Duplicate insertion -> idempotent, no redundant delegate callback
        manager.addPauseReason(.fullscreenApp)
        XCTAssertEqual(delegate.changeCount, 1)

        manager.stopMonitoring()
    }

    func testPowerManager_clearingUnsetReasonIsNoOp() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        let delegate = MockPowerManagerDelegate()
        manager.delegate = delegate
        manager.startMonitoring()

        // Remove reason that was never inserted
        manager.removePauseReason(.batterySaver)
        XCTAssertEqual(delegate.changeCount, 0)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)
        XCTAssertFalse(manager.isPaused)

        manager.stopMonitoring()
    }

    func testPowerManager_settingsDisableFullscreenAutoPause() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        var settings = PowerSettings()
        settings.pauseOnFullscreen = false

        let manager = PowerManager(
            settings: settings,
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        // Fullscreen app becomes active, but preference is disabled
        mockDetector.setOccluded(true)
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }

    func testPowerManager_settingsDisableBatteryAutoPause() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        var settings = PowerSettings()
        settings.pauseOnBattery = false
        settings.pauseOnLowPowerMode = false

        let manager = PowerManager(
            settings: settings,
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        mockBattery.setBatteryActive(true)
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }

    func testPowerManager_dynamicSettingsUpdateReevaluatesImmediately() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector(isOccluded: false)
        let mockBattery = MockBatteryMonitor(isOnBattery: true)

        var settings = PowerSettings()
        settings.pauseOnBattery = false
        settings.pauseOnLowPowerMode = false

        let manager = PowerManager(
            settings: settings,
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        XCTAssertFalse(manager.isPaused)

        // User turns ON "Pause on Battery" in preferences while already on battery
        settings.pauseOnBattery = true
        manager.updateSettings(settings)

        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(manager.currentPauseReasons, [.batterySaver])

        // User turns OFF "Pause on Battery" in preferences
        settings.pauseOnBattery = false
        manager.updateSettings(settings)

        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }

    func testPowerManager_desktopWindowManagerCoordination() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()
        let mockWM = MockDesktopWindowManager()

        let manager = PowerManager(
            windowManager: mockWM,
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        XCTAssertFalse(mockWM.isPaused)
        XCTAssertEqual(mockWM.setPausedCallCount, 0)

        // Trigger pause via sleep
        mockWS.post(name: NSWorkspace.screensDidSleepNotification)
        XCTAssertTrue(mockWM.isPaused)
        XCTAssertEqual(mockWM.lastPausedValue, true)
        XCTAssertEqual(mockWM.setPausedCallCount, 1)

        // Trigger wake
        mockWS.post(name: NSWorkspace.screensDidWakeNotification)
        XCTAssertFalse(mockWM.isPaused)
        XCTAssertEqual(mockWM.lastPausedValue, false)
        XCTAssertEqual(mockWM.setPausedCallCount, 2)

        manager.stopMonitoring()
    }

    func testPowerManager_simulationAPIsMatchingE2E() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )

        manager.simulateFullscreen(isActive: true)
        XCTAssertTrue(manager.currentPauseReasons.contains(.fullscreenApp))
        manager.simulateFullscreen(isActive: false)
        XCTAssertFalse(manager.currentPauseReasons.contains(.fullscreenApp))

        manager.simulateDisplaySleep()
        XCTAssertTrue(manager.currentPauseReasons.contains(.displaySleeping))
        manager.simulateDisplayWake()
        XCTAssertFalse(manager.currentPauseReasons.contains(.displaySleeping))

        manager.simulateScreenLock()
        XCTAssertTrue(manager.currentPauseReasons.contains(.screenLocked))
        manager.simulateScreenUnlock()
        XCTAssertFalse(manager.currentPauseReasons.contains(.screenLocked))

        manager.simulateBatteryState(isOnBattery: true)
        XCTAssertTrue(manager.currentPauseReasons.contains(.batterySaver))
        manager.simulateBatteryState(isOnBattery: false)
        XCTAssertFalse(manager.currentPauseReasons.contains(.batterySaver))

        manager.simulateUserPause(isPaused: true)
        XCTAssertTrue(manager.currentPauseReasons.contains(.userPaused))
        manager.simulateUserPause(isPaused: false)
        XCTAssertFalse(manager.currentPauseReasons.contains(.userPaused))
    }

    func testPowerManager_rapidJitterResilience() {
        let mockWS = NotificationCenter()
        let mockDist = NotificationCenter()
        let mockDetector = MockFullscreenDetector()
        let mockBattery = MockBatteryMonitor()

        let manager = PowerManager(
            fullscreenDetector: mockDetector,
            batteryMonitor: mockBattery,
            workspaceNotificationCenter: mockWS,
            distributedNotificationCenter: mockDist
        )
        manager.startMonitoring()

        // 100 rapid lock/unlock cycles
        for _ in 0..<100 {
            mockDist.post(name: NSNotification.Name("com.apple.screenIsLocked"))
            mockDist.post(name: NSNotification.Name("com.apple.screenIsUnlocked"))
        }

        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        // 100 rapid sleep/wake cycles
        for _ in 0..<100 {
            mockWS.post(name: NSWorkspace.screensDidSleepNotification)
            mockWS.post(name: NSWorkspace.screensDidWakeNotification)
        }

        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(manager.currentPauseReasons.isEmpty)

        manager.stopMonitoring()
    }
}
