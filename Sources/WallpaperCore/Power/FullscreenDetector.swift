import AppKit
import CoreGraphics
import Foundation

// MARK: - Window Info Model

/// Strongly typed model representing an on-screen window entry from Quartz Window Services.
public struct WindowInfo: Equatable, Sendable {
    public let windowNumber: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    public let layer: Int
    public let bounds: CGRect
    public let alpha: CGFloat
    public let isOnScreen: Bool
    public let sharingState: Int

    /// Alias for windowNumber matching Quartz API nomenclature.
    public var windowID: CGWindowID { windowNumber }
    /// Alias for isOnScreen matching CoreGraphics dictionary key.
    public var isOnscreen: Bool { isOnScreen }

    public init(
        windowNumber: CGWindowID = 0,
        ownerPID: pid_t = 0,
        ownerName: String = "",
        bounds: CGRect,
        layer: Int = 0,
        alpha: CGFloat = 1.0,
        isOnScreen: Bool = true,
        sharingState: Int = 0
    ) {
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
        self.sharingState = sharingState
    }

    /// Convenience initializer decoding from `CGWindowListCopyWindowInfo` dictionaries.
    public init?(dictionary: [String: Any]) {
        guard let boundsDict = dictionary[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return nil
        }
        self.bounds = rect
        self.windowNumber = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
        self.ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        self.ownerName = dictionary[kCGWindowOwnerName as String] as? String ?? ""
        self.layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        self.alpha = CGFloat((dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0)
        self.isOnScreen = (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
        self.sharingState = (dictionary[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 0
    }
}

// MARK: - Window Info Provider Protocol

/// Abstract provider protocol supplying on-screen window lists without requiring TCC permissions.
public protocol WindowInfoProviderProtocol: AnyObject, Sendable {
    func copyWindowInfoList() -> [WindowInfo]
}

extension WindowInfoProviderProtocol {
    /// Convenience alias for copyWindowInfoList.
    public func getOnScreenWindows() -> [WindowInfo] {
        copyWindowInfoList()
    }
}

/// Production window info provider querying Quartz Window Services without triggering TCC permission prompts.
public final class SystemWindowInfoProvider: WindowInfoProviderProtocol, @unchecked Sendable {
    public init() {}

    public func copyWindowInfoList() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { WindowInfo(dictionary: $0) }
    }
}

/// Mock window info provider enabling deterministic fullscreen and occlusion testing.
public final class MockWindowInfoProvider: WindowInfoProviderProtocol, @unchecked Sendable {
    public var windows: [WindowInfo]

    public init(windows: [WindowInfo] = []) {
        self.windows = windows
    }

    public func copyWindowInfoList() -> [WindowInfo] {
        return windows
    }
}

// MARK: - Fullscreen Detector Delegate & Protocol

@MainActor
public protocol FullscreenDetectorDelegate: AnyObject {
    func fullscreenDetectorDidChangeOcclusion(
        _ detector: FullscreenDetectorProtocol,
        isOccluded: Bool,
        occludedDisplayIDs: Set<CGDirectDisplayID>
    )
}

@MainActor
public protocol FullscreenDetectorProtocol: AnyObject {
    var delegate: FullscreenDetectorDelegate? { get set }
    var isOccluded: Bool { get }
    var isAnyScreenOccluded: Bool { get }
    var isFullscreenActive: Bool { get }
    var occludedDisplayIDs: Set<CGDirectDisplayID> { get }
    var pollingInterval: TimeInterval { get set }
    var isMonitoring: Bool { get }
    var onFullscreenChanged: (@MainActor (Bool) -> Void)? { get set }

    func startMonitoring()
    func stopMonitoring()
    @discardableResult
    func checkFullscreenState() -> Bool
    func isScreenOccluded(displayID: CGDirectDisplayID) -> Bool
}

// MARK: - FullscreenDetector

/// Detects fullscreen applications and window occlusions across all connected macOS displays
/// using zero-TCC Quartz window enumeration, notification observation, and polling.
@MainActor
public final class FullscreenDetector: FullscreenDetectorProtocol {

    // MARK: - Constants (Swift 6 Nonisolated Sendable)

    public nonisolated static let defaultPollingInterval: TimeInterval = 1.0
    public nonisolated static let boundsTolerance: CGFloat = 5.0
    public nonisolated static let minimumOpaqueAlpha: CGFloat = 0.85

    /// Well-known system overlay layers to explicitly ignore:
    /// - Layer 20: macOS Dock (reports fullscreen bounds 1920x1080)
    /// - Layer 24/25: MenuBar & Status items
    /// - Negative layers: Desktop and icon levels
    public nonisolated static let ignoredLayers: Set<Int> = [
        20,             // Dock
        24, 25,         // Menu bar & Status items
        -2147483623,    // Desktop window level (kCGDesktopWindowLevel)
        -2147483602,    // Desktop interactive window level (kCGDesktopIconWindowLevel + 1)
        -2147483601     // Notification Center / Widgets
    ]

    // MARK: - Dependencies

    public let screenProvider: ScreenProviderProtocol
    public let windowInfoProvider: WindowInfoProviderProtocol
    public let currentProcessPID: pid_t

    // MARK: - State

    public weak var delegate: FullscreenDetectorDelegate?
    public private(set) var isOccluded: Bool = false
    public var isAnyScreenOccluded: Bool { isOccluded }
    public var isFullscreenActive: Bool { isOccluded }

    public private(set) var occludedDisplayIDs: Set<CGDirectDisplayID> = []
    public var pollingInterval: TimeInterval {
        didSet {
            if isMonitoring {
                restartTimer()
            }
        }
    }
    public private(set) var isMonitoring: Bool = false
    public var onFullscreenChanged: (@MainActor (Bool) -> Void)?

    // MARK: - Private Observers & Timer

    private var pollingTimer: Timer?
    private var workspaceObservers: [any NSObjectProtocol] = []

    // MARK: - Initializer

    public init(
        screenProvider: ScreenProviderProtocol,
        windowInfoProvider: WindowInfoProviderProtocol = SystemWindowInfoProvider(),
        pollingInterval: TimeInterval = FullscreenDetector.defaultPollingInterval,
        currentProcessPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.screenProvider = screenProvider
        self.windowInfoProvider = windowInfoProvider
        self.pollingInterval = pollingInterval
        self.currentProcessPID = currentProcessPID
    }

    isolated deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Lifecycle

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        setupNotificationObservers()
        startTimer()
        checkFullscreenState()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stopTimer()
        removeNotificationObservers()
    }

    // MARK: - Timer Management

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkFullscreenState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollingTimer = timer
    }

    private func stopTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func restartTimer() {
        stopTimer()
        startTimer()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        removeNotificationObservers()
        let center = NSWorkspace.shared.notificationCenter

        let activateObs = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkFullscreenState()
            }
        }
        workspaceObservers.append(activateObs)

        let deactivateObs = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkFullscreenState()
            }
        }
        workspaceObservers.append(deactivateObs)

        let spaceObs = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.checkFullscreenState()
            }
        }
        workspaceObservers.append(spaceObs)
    }

    private func removeNotificationObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            center.removeObserver(obs)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - State Evaluation

    @discardableResult
    public func checkFullscreenState() -> Bool {
        let currentScreens = screenProvider.screens
        guard !currentScreens.isEmpty else {
            updateState(isOccluded: false, occludedIDs: [])
            return false
        }

        // Primary screen height in Cocoa coordinates (origin (0, 0) is primary display)
        let primaryHeight: CGFloat = {
            if let primary = currentScreens.first(where: { $0.frame.origin == .zero }) {
                return primary.frame.height
            }
            return currentScreens.first?.frame.height ?? 1080.0
        }()

        // Map Cocoa display descriptor coordinates to Quartz window server coordinates
        let screenQuartzBounds: [(displayID: CGDirectDisplayID, bounds: CGRect)] = currentScreens.map { screen in
            if CGDisplayIsActive(screen.displayID) != 0 {
                let cgBounds = CGDisplayBounds(screen.displayID)
                if cgBounds.width > 1 && cgBounds.height > 1 {
                    return (screen.displayID, cgBounds)
                }
            }
            let quartzY = primaryHeight - (screen.frame.origin.y + screen.frame.height)
            let quartzRect = CGRect(
                x: screen.frame.origin.x,
                y: quartzY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            return (screen.displayID, quartzRect)
        }

        let windows = windowInfoProvider.copyWindowInfoList()
        var newlyOccludedIDs = Set<CGDirectDisplayID>()

        for screen in screenQuartzBounds {
            for window in windows {
                // 1. Skip self windows (Wallpaper manager, settings, desktop windows)
                if window.ownerPID == currentProcessPID {
                    continue
                }
                // 2. Skip hidden or off-screen windows
                if !window.isOnScreen {
                    continue
                }
                // 3. Filter desktop levels (negative layers) and system overlay layers
                if window.layer < 0 || Self.ignoredLayers.contains(window.layer) {
                    continue
                }
                // 4. Must be standard application layer 0
                if window.layer != 0 {
                    continue
                }
                // 5. Must satisfy minimum opacity threshold
                if window.alpha < Self.minimumOpaqueAlpha {
                    continue
                }
                // 6. Check if window bounds cover the display within tolerance
                if windowCoversScreen(windowBounds: window.bounds, screenBounds: screen.bounds) {
                    newlyOccludedIDs.insert(screen.displayID)
                    break
                }
            }
        }

        let isAnyOccluded = !newlyOccludedIDs.isEmpty
        updateState(isOccluded: isAnyOccluded, occludedIDs: newlyOccludedIDs)
        return isAnyOccluded
    }

    private func windowCoversScreen(windowBounds: CGRect, screenBounds: CGRect) -> Bool {
        let tol = Self.boundsTolerance
        let coversX = (windowBounds.origin.x <= screenBounds.origin.x + tol) &&
                      (windowBounds.maxX >= screenBounds.maxX - tol)
        let coversY = (windowBounds.origin.y <= screenBounds.origin.y + tol) &&
                      (windowBounds.maxY >= screenBounds.maxY - tol)
        return coversX && coversY
    }

    private func updateState(isOccluded: Bool, occludedIDs: Set<CGDirectDisplayID>) {
        let changed = (self.isOccluded != isOccluded) || (self.occludedDisplayIDs != occludedIDs)
        self.isOccluded = isOccluded
        self.occludedDisplayIDs = occludedIDs

        if changed {
            delegate?.fullscreenDetectorDidChangeOcclusion(
                self,
                isOccluded: isOccluded,
                occludedDisplayIDs: occludedIDs
            )
            onFullscreenChanged?(isOccluded)
        }
    }

    public func isScreenOccluded(displayID: CGDirectDisplayID) -> Bool {
        occludedDisplayIDs.contains(displayID)
    }
}

// MARK: - Mock Fullscreen Detector

/// Mock fullscreen detector for testing PowerManager in isolation.
@MainActor
public final class MockFullscreenDetector: FullscreenDetectorProtocol {
    public weak var delegate: FullscreenDetectorDelegate?
    public var isOccluded: Bool = false
    public var isAnyScreenOccluded: Bool { isOccluded }
    public var isFullscreenActive: Bool { isOccluded }
    public var occludedDisplayIDs: Set<CGDirectDisplayID> = []
    public var pollingInterval: TimeInterval = 1.0
    public private(set) var isMonitoring: Bool = false
    public var onFullscreenChanged: (@MainActor (Bool) -> Void)?

    public init(isOccluded: Bool = false, occludedDisplayIDs: Set<CGDirectDisplayID> = []) {
        self.isOccluded = isOccluded
        self.occludedDisplayIDs = occludedDisplayIDs
    }

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    @discardableResult
    public func checkFullscreenState() -> Bool {
        return isOccluded
    }

    public func isScreenOccluded(displayID: CGDirectDisplayID) -> Bool {
        occludedDisplayIDs.contains(displayID)
    }

    public func setOccluded(_ occluded: Bool, displayIDs: Set<CGDirectDisplayID> = [1]) {
        self.isOccluded = occluded
        self.occludedDisplayIDs = occluded ? displayIDs : []
        delegate?.fullscreenDetectorDidChangeOcclusion(self, isOccluded: isOccluded, occludedDisplayIDs: self.occludedDisplayIDs)
        onFullscreenChanged?(isOccluded)
    }
}
