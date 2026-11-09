import AppKit
import Foundation

// MARK: - Pause Reasons

/// Additive bitmask representing all active sources requesting live wallpaper rendering suspension.
///
/// Playback is paused whenever `!pauseReasons.isEmpty` (rawValue != 0).
/// Resumption occurs if and only if `pauseReasons.isEmpty` (rawValue == 0).
public struct PauseReasons: OptionSet, Sendable, CustomStringConvertible, Equatable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Explicit user manual pause via Menu Bar companion or SwiftUI Manager.
    public static let userPaused        = PauseReasons(rawValue: 1 << 0) // 1

    /// Occlusion by a full-screen application or game on an active display.
    public static let fullscreenApp     = PauseReasons(rawValue: 1 << 1) // 2

    /// macOS display sleep (display powered off or in standby).
    public static let displaySleeping   = PauseReasons(rawValue: 1 << 2) // 4

    /// macOS screen lock or screensaver engagement.
    public static let screenLocked      = PauseReasons(rawValue: 1 << 3) // 8

    /// Host running on battery power with battery saver mode enabled.
    public static let batterySaver      = PauseReasons(rawValue: 1 << 4) // 16

    /// All five pause reasons combined (rawValue = 31).
    public static let all: PauseReasons = [
        .userPaused,
        .fullscreenApp,
        .displaySleeping,
        .screenLocked,
        .batterySaver
    ]

    public var description: String {
        var elements: [String] = []
        if contains(.userPaused) { elements.append("userPaused") }
        if contains(.fullscreenApp) { elements.append("fullscreenApp") }
        if contains(.displaySleeping) { elements.append("displaySleeping") }
        if contains(.screenLocked) { elements.append("screenLocked") }
        if contains(.batterySaver) { elements.append("batterySaver") }
        return elements.isEmpty ? "none" : elements.joined(separator: ", ")
    }
}

// MARK: - Power Settings

/// User preferences controlling energy-saver auto-pause behavior.
public struct PowerSettings: Equatable, Sendable {
    public var pauseOnFullscreen: Bool
    public var pauseOnBattery: Bool
    public var pauseOnDisplaySleep: Bool
    public var pauseOnScreenLock: Bool
    public var pauseOnLowPowerMode: Bool

    public init(
        pauseOnFullscreen: Bool = true,
        pauseOnBattery: Bool = false,
        pauseOnDisplaySleep: Bool = true,
        pauseOnScreenLock: Bool = true,
        pauseOnLowPowerMode: Bool = true
    ) {
        self.pauseOnFullscreen = pauseOnFullscreen
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnDisplaySleep = pauseOnDisplaySleep
        self.pauseOnScreenLock = pauseOnScreenLock
        self.pauseOnLowPowerMode = pauseOnLowPowerMode
    }

    /// Convenience initializer bridging from observable `AppState`.
    @MainActor
    public init(from appState: AppState) {
        self.init(
            pauseOnFullscreen: appState.pauseOnFullscreen,
            pauseOnBattery: appState.pauseOnBattery,
            pauseOnDisplaySleep: appState.pauseOnDisplaySleep,
            pauseOnScreenLock: true,
            pauseOnLowPowerMode: true
        )
    }
}

// MARK: - Notification Center Protocol

/// Unified protocol abstracting notification subscription and dispatching.
/// Enables deterministic unit testing without posting to system DistributedNotificationCenter.
public protocol NotificationCenterProtocol: AnyObject, Sendable {
    func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> any NSObjectProtocol

    func removeObserver(_ observer: Any)

    func post(name aName: NSNotification.Name, object anObject: Any?, userInfo aUserInfo: [AnyHashable: Any]?)
}

extension NotificationCenterProtocol {
    public func post(name aName: NSNotification.Name, object anObject: Any? = nil) {
        post(name: aName, object: anObject, userInfo: nil)
    }
}

extension NotificationCenter: NotificationCenterProtocol {}

// MARK: - Power Manager Delegate & Protocol

@MainActor
public protocol PowerManagerDelegate: AnyObject {
    func powerManagerDidChangePauseState(
        _ manager: PowerManagerProtocol,
        isPaused: Bool,
        reasons: PauseReasons
    )
}

@MainActor
public protocol PowerManagerProtocol: AnyObject {
    var delegate: PowerManagerDelegate? { get set }
    var currentPauseReasons: PauseReasons { get }
    var isPaused: Bool { get }
    var settings: PowerSettings { get set }
    var isMonitoring: Bool { get }

    func startMonitoring()
    func stopMonitoring()
    func updateSettings(_ newSettings: PowerSettings)

    // Reason manipulation
    func addPauseReason(_ reason: PauseReasons)
    func removePauseReason(_ reason: PauseReasons)
    func setPauseReason(_ reason: PauseReasons, active: Bool)
    func setUserPaused(_ paused: Bool)
    func setFullscreenOccluded(_ occluded: Bool)

    // Simulation & CI testing hooks (matching E2ETestHarness)
    func simulateFullscreenApp(isActive: Bool)
    func simulateFullscreen(isActive: Bool)
    func simulateDisplaySleep()
    func simulateDisplayWake()
    func simulateScreenLock()
    func simulateScreenUnlock()
    func simulateBatteryPower(saverActive: Bool)
    func simulateBatteryState(isOnBattery: Bool)
    func simulateUserPause(isPaused: Bool)
}

// MARK: - PowerManager

/// Central coordinator evaluating fullscreen occlusion, display sleep, screen lock, and battery states
/// using an additive `PauseReasons` state machine.
@MainActor
public final class PowerManager: PowerManagerProtocol, FullscreenDetectorDelegate, BatteryMonitorDelegate {

    // MARK: - Dependencies

    public weak var delegate: PowerManagerDelegate?
    public weak var windowManager: DesktopWindowManagerProtocol? {
        didSet {
            if isPaused {
                windowManager?.setPaused(true)
            }
        }
    }

    public let fullscreenDetector: FullscreenDetectorProtocol
    public let batteryMonitor: BatteryMonitorProtocol
    public let workspaceNotificationCenter: NotificationCenterProtocol
    public let distributedNotificationCenter: NotificationCenterProtocol

    // MARK: - Configuration & State

    public var settings: PowerSettings {
        didSet {
            guard oldValue != settings else { return }
            reapplySettings()
        }
    }

    public private(set) var currentPauseReasons: PauseReasons = []
    public private(set) var isMonitoring: Bool = false

    public var isPaused: Bool {
        !currentPauseReasons.isEmpty
    }

    public var onPauseStateChanged: (@MainActor (Bool, PauseReasons) -> Void)?

    // MARK: - Private Observer Tokens

    private var workspaceTokens: [any NSObjectProtocol] = []
    private var distributedTokens: [any NSObjectProtocol] = []

    // MARK: - Initializers

    public init(
        settings: PowerSettings = PowerSettings(),
        windowManager: DesktopWindowManagerProtocol? = nil,
        fullscreenDetector: FullscreenDetectorProtocol,
        batteryMonitor: BatteryMonitorProtocol,
        workspaceNotificationCenter: NotificationCenterProtocol = NSWorkspace.shared.notificationCenter,
        distributedNotificationCenter: NotificationCenterProtocol = DistributedNotificationCenter.default()
    ) {
        self.settings = settings
        self.windowManager = windowManager
        self.fullscreenDetector = fullscreenDetector
        self.batteryMonitor = batteryMonitor
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.distributedNotificationCenter = distributedNotificationCenter

        self.fullscreenDetector.delegate = self
        self.batteryMonitor.delegate = self
    }

    /// Convenience initializer constructing default hardware subsystems with `ScreenProviderProtocol`.
    public convenience init(
        settings: PowerSettings = PowerSettings(),
        windowManager: DesktopWindowManagerProtocol? = nil,
        screenProvider: ScreenProviderProtocol = SystemScreenProvider(),
        workspaceNotificationCenter: NotificationCenterProtocol = NSWorkspace.shared.notificationCenter,
        distributedNotificationCenter: NotificationCenterProtocol = DistributedNotificationCenter.default()
    ) {
        let detector = FullscreenDetector(screenProvider: screenProvider)
        let monitor = BatteryMonitor()
        self.init(
            settings: settings,
            windowManager: windowManager,
            fullscreenDetector: detector,
            batteryMonitor: monitor,
            workspaceNotificationCenter: workspaceNotificationCenter,
            distributedNotificationCenter: distributedNotificationCenter
        )
    }

    isolated deinit {
        stopMonitoring()
    }

    // MARK: - Subsystem Delegates

    public func fullscreenDetectorDidChangeOcclusion(
        _ detector: FullscreenDetectorProtocol,
        isOccluded: Bool,
        occludedDisplayIDs: Set<CGDirectDisplayID>
    ) {
        if settings.pauseOnFullscreen {
            setPauseReason(.fullscreenApp, active: isOccluded)
        }
    }

    public func batteryMonitorDidChangePowerState(_ monitor: BatteryMonitorProtocol) {
        let shouldPause = (settings.pauseOnBattery && monitor.isOnBattery) ||
                          (settings.pauseOnLowPowerMode && monitor.isLowPowerMode)
        setPauseReason(.batterySaver, active: shouldPause)
    }

    // MARK: - Monitoring Lifecycle

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        fullscreenDetector.startMonitoring()
        batteryMonitor.startMonitoring()

        setupWorkspaceObservers()
        setupDistributedObservers()

        // Evaluate initial conditions
        if settings.pauseOnBattery && (batteryMonitor.isOnBattery || (settings.pauseOnLowPowerMode && batteryMonitor.isLowPowerMode)) {
            addPauseReason(.batterySaver)
        }
        if settings.pauseOnFullscreen && fullscreenDetector.isOccluded {
            addPauseReason(.fullscreenApp)
        }
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        fullscreenDetector.stopMonitoring()
        batteryMonitor.stopMonitoring()

        removeWorkspaceObservers()
        removeDistributedObservers()

        // Clear automatic environmental reasons while preserving explicit userPaused
        let userWasPaused = currentPauseReasons.contains(.userPaused)
        let oldReasons = currentPauseReasons
        currentPauseReasons = userWasPaused ? [.userPaused] : []
        notifyStateChange(oldReasons: oldReasons)
    }

    // MARK: - Notification Observers Setup & Teardown

    private func setupWorkspaceObservers() {
        removeWorkspaceObservers()

        addWorkspaceObserver(NSWorkspace.screensDidSleepNotification) { [weak self] in
            guard let self, self.settings.pauseOnDisplaySleep else { return }
            self.addPauseReason(.displaySleeping)
        }

        addWorkspaceObserver(NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.removePauseReason(.displaySleeping)
        }

        addWorkspaceObserver(NSWorkspace.willSleepNotification) { [weak self] in
            guard let self, self.settings.pauseOnDisplaySleep else { return }
            self.addPauseReason(.displaySleeping)
        }

        addWorkspaceObserver(NSWorkspace.didWakeNotification) { [weak self] in
            self?.removePauseReason(.displaySleeping)
        }

        addWorkspaceObserver(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            guard let self, self.settings.pauseOnScreenLock else { return }
            self.addPauseReason(.screenLocked)
        }

        addWorkspaceObserver(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.removePauseReason(.screenLocked)
        }
    }

    private func removeWorkspaceObservers() {
        for token in workspaceTokens {
            workspaceNotificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
    }

    private func addWorkspaceObserver(_ name: NSNotification.Name, handler: @escaping @MainActor () -> Void) {
        let token = workspaceNotificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { handler() }
            } else {
                Task { @MainActor in handler() }
            }
        }
        workspaceTokens.append(token)
    }

    private func setupDistributedObservers() {
        removeDistributedObservers()

        addDistributedObserver(NSNotification.Name("com.apple.screenIsLocked")) { [weak self] in
            guard let self, self.settings.pauseOnScreenLock else { return }
            self.addPauseReason(.screenLocked)
        }

        addDistributedObserver(NSNotification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.removePauseReason(.screenLocked)
        }

        addDistributedObserver(NSNotification.Name("com.apple.screensaver.didstart")) { [weak self] in
            guard let self, self.settings.pauseOnScreenLock else { return }
            self.addPauseReason(.screenLocked)
        }

        addDistributedObserver(NSNotification.Name("com.apple.screensaver.didstop")) { [weak self] in
            self?.removePauseReason(.screenLocked)
        }
    }

    private func removeDistributedObservers() {
        for token in distributedTokens {
            distributedNotificationCenter.removeObserver(token)
        }
        distributedTokens.removeAll()
    }

    private func addDistributedObserver(_ name: NSNotification.Name, handler: @escaping @MainActor () -> Void) {
        let token = distributedNotificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { handler() }
            } else {
                Task { @MainActor in handler() }
            }
        }
        distributedTokens.append(token)
    }

    // MARK: - Settings Management

    public func updateSettings(_ newSettings: PowerSettings) {
        self.settings = newSettings
    }

    private func reapplySettings() {
        if !settings.pauseOnFullscreen && currentPauseReasons.contains(.fullscreenApp) {
            removePauseReason(.fullscreenApp)
        } else if settings.pauseOnFullscreen && fullscreenDetector.isOccluded {
            addPauseReason(.fullscreenApp)
        }

        let shouldPauseBatt = (settings.pauseOnBattery && batteryMonitor.isOnBattery) ||
                              (settings.pauseOnLowPowerMode && batteryMonitor.isLowPowerMode)
        if shouldPauseBatt {
            addPauseReason(.batterySaver)
        } else if currentPauseReasons.contains(.batterySaver) {
            removePauseReason(.batterySaver)
        }

        if !settings.pauseOnDisplaySleep && currentPauseReasons.contains(.displaySleeping) {
            removePauseReason(.displaySleeping)
        }

        if !settings.pauseOnScreenLock && currentPauseReasons.contains(.screenLocked) {
            removePauseReason(.screenLocked)
        }
    }

    // MARK: - Pause Reason Operations

    public func addPauseReason(_ reason: PauseReasons) {
        guard !reason.isEmpty else { return }
        let oldReasons = currentPauseReasons
        currentPauseReasons.insert(reason)
        notifyStateChange(oldReasons: oldReasons)
    }

    public func removePauseReason(_ reason: PauseReasons) {
        guard !reason.isEmpty else { return }
        guard currentPauseReasons.contains(reason) else { return }
        let oldReasons = currentPauseReasons
        currentPauseReasons.remove(reason)
        notifyStateChange(oldReasons: oldReasons)
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

    private func notifyStateChange(oldReasons: PauseReasons) {
        guard oldReasons != currentPauseReasons else { return }
        let currentPaused = self.isPaused

        windowManager?.setPaused(currentPaused)
        delegate?.powerManagerDidChangePauseState(self, isPaused: currentPaused, reasons: currentPauseReasons)
        onPauseStateChanged?(currentPaused, currentPauseReasons)
    }

    // MARK: - Simulation & Testing API (matching E2ETestHarness)

    public func simulateFullscreenApp(isActive: Bool) {
        setPauseReason(.fullscreenApp, active: isActive)
    }

    public func simulateFullscreen(isActive: Bool) {
        simulateFullscreenApp(isActive: isActive)
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
        simulateBatteryPower(saverActive: isOnBattery)
    }

    public func simulateUserPause(isPaused: Bool) {
        setUserPaused(isPaused)
    }
}
