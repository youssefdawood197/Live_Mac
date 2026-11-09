import AppKit
import CoreGraphics

// MARK: - Display Descriptors & Screen Provider

/// Lightweight descriptor encapsulating display identity and bounds.
/// Decouples display management from live `NSScreen` instances, enabling safe unit testing
/// without triggering uncatchable Darwin kernel crashes (`SIGSEGV`).
public struct DisplayDescriptor: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let frame: CGRect

    public init(displayID: CGDirectDisplayID, frame: CGRect) {
        self.displayID = displayID
        self.frame = frame
    }

    public init(screen: NSScreen) {
        self.displayID = screen.displayID
        self.frame = screen.frame
    }
}

/// Abstract provider protocol supplying available displays to `DesktopWindowManager`.
@MainActor
public protocol ScreenProviderProtocol: AnyObject {
    var screens: [DisplayDescriptor] { get }
}

/// Production screen provider discovering hardware displays via AppKit `NSScreen.screens`.
@MainActor
public final class SystemScreenProvider: ScreenProviderProtocol {
    public init() {}

    public var screens: [DisplayDescriptor] {
        NSScreen.screens.map { DisplayDescriptor(screen: $0) }
    }
}

/// Mock screen provider enabling deterministic multi-display testing in headless environments.
@MainActor
public final class MockScreenProvider: ScreenProviderProtocol {
    public var screens: [DisplayDescriptor]

    public init(screens: [DisplayDescriptor] = []) {
        self.screens = screens
    }
}

// MARK: - DesktopWindowManagerProtocol

/// Contract for multi-display desktop wallpaper window coordination.
@MainActor
public protocol DesktopWindowManagerProtocol: AnyObject {
    var isInteractive: Bool { get set }
    var activeWallpaper: WallpaperItem? { get }
    var windows: [CGDirectDisplayID: DesktopWindow] { get }
    var engines: [CGDirectDisplayID: WallpaperEngine] { get }

    func setWallpaper(_ item: WallpaperItem)
    func setPaused(_ paused: Bool)
    func setMuted(_ muted: Bool)
    func setVolume(_ volume: Float)
    func reloadDisplays()
    func terminate()
}

// MARK: - DesktopWindowManager

/// Coordinates the lifecycle, geometry, and presentation states of live wallpaper windows
/// across all active macOS displays.
@MainActor
public final class DesktopWindowManager: DesktopWindowManagerProtocol, WallpaperEngineDelegate {

    public typealias EngineFactory = @MainActor (WallpaperItem) -> WallpaperEngine

    // MARK: - Dependencies

    public let screenProvider: ScreenProviderProtocol
    public let engineFactory: EngineFactory

    // MARK: - State Properties

    private var _isInteractive: Bool = false
    public var isInteractive: Bool {
        get { _isInteractive }
        set {
            guard _isInteractive != newValue else { return }
            _isInteractive = newValue
            for window in windows.values {
                window.isInteractive = newValue
            }
            for engine in engines.values {
                engine.isInteractive = newValue
            }
        }
    }

    public private(set) var activeWallpaper: WallpaperItem?
    public private(set) var isPaused: Bool = false
    public private(set) var isMuted: Bool = true
    public private(set) var volume: Float = 1.0

    /// Stable identity dictionary tracking active desktop windows by hardware display identifier.
    public private(set) var windows: [CGDirectDisplayID: DesktopWindow] = [:]

    /// Stable identity dictionary tracking active rendering engines by hardware display identifier.
    public private(set) var engines: [CGDirectDisplayID: WallpaperEngine] = [:]

    /// Convenience access to all managed desktop windows as an array.
    public var windowList: [DesktopWindow] {
        Array(windows.values)
    }

    // MARK: - Delegates and Callbacks

    public weak var engineDelegate: WallpaperEngineDelegate?
    public var onEngineError: ((WallpaperEngine, Error) -> Void)?
    public var onPlaybackStateChanged: ((WallpaperEngine, Bool) -> Void)?

    /// Internal token for screen parameter change notification observation.
    private var screenNotificationObserver: (any NSObjectProtocol)?

    // MARK: - Initialization

    public init(
        screenProvider: ScreenProviderProtocol = SystemScreenProvider(),
        engineFactory: @escaping EngineFactory = { WallpaperEngineFactory.createEngine(for: $0) }
    ) {
        self.screenProvider = screenProvider
        self.engineFactory = engineFactory
        setupNotificationObserver()
        reloadDisplays()
    }

    isolated deinit {
        terminate()
    }

    // MARK: - Notification Setup

    private func setupNotificationObserver() {
        screenNotificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadDisplays()
            }
        }
    }

    // MARK: - Window & Engine Lookup

    public func window(for displayID: CGDirectDisplayID) -> DesktopWindow? {
        windows[displayID]
    }

    public func engine(for displayID: CGDirectDisplayID) -> WallpaperEngine? {
        engines[displayID]
    }

    // MARK: - Protocol Methods

    public func setWallpaper(_ item: WallpaperItem) {
        self.activeWallpaper = item

        for (displayID, engine) in engines {
            engine.terminate()
            windows[displayID]?.contentView = nil
        }
        engines.removeAll()

        for (displayID, window) in windows {
            let engine = engineFactory(item)
            engine.isMuted = self.isMuted
            engine.volume = self.volume
            engine.isInteractive = self.isInteractive
            engine.delegate = self

            if self.isPaused {
                engine.pause()
            } else {
                engine.play()
            }

            window.contentView = engine.view
            engines[displayID] = engine
        }
    }

    public func setPaused(_ paused: Bool) {
        self.isPaused = paused
        for engine in engines.values {
            if paused {
                engine.pause()
            } else {
                engine.play()
            }
        }
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        for engine in engines.values {
            engine.isMuted = muted
        }
    }

    public func setVolume(_ volume: Float) {
        if volume.isNaN || volume.isInfinite {
            self.volume = 0.0
        } else {
            self.volume = max(0.0, min(1.0, volume))
        }
        for engine in engines.values {
            engine.volume = self.volume
        }
    }

    /// Reconciles the set of active `DesktopWindow` and `WallpaperEngine` instances with current screen topology.
    ///
    /// 1. Terminates engines and closes windows for detached displays.
    /// 2. Resizes existing windows whose display frame or resolution changed.
    /// 3. Creates, configures, and orders back new windows for newly attached displays, mounting engines if a wallpaper is active.
    public func reloadDisplays() {
        let currentScreens = screenProvider.screens
        let currentDisplayIDs = Set(currentScreens.map { $0.displayID })

        // 1. Remove disconnected displays
        for (displayID, window) in windows where !currentDisplayIDs.contains(displayID) {
            if let engine = engines.removeValue(forKey: displayID) {
                engine.terminate()
            }
            window.contentView = nil
            window.orderOut(nil)
            window.close()
            windows.removeValue(forKey: displayID)
        }

        // 2. Add or update displays
        for screen in currentScreens {
            if let existingWindow = windows[screen.displayID] {
                if existingWindow.frame != screen.frame {
                    existingWindow.updateFrame(screen.frame)
                }
            } else {
                let window = DesktopWindow(
                    displayID: screen.displayID,
                    frame: screen.frame,
                    isInteractive: self.isInteractive
                )
                window.orderBack(nil)
                windows[screen.displayID] = window

                if let item = activeWallpaper {
                    let engine = engineFactory(item)
                    engine.isMuted = self.isMuted
                    engine.volume = self.volume
                    engine.isInteractive = self.isInteractive
                    engine.delegate = self

                    if self.isPaused {
                        engine.pause()
                    } else {
                        engine.play()
                    }

                    window.contentView = engine.view
                    engines[screen.displayID] = engine
                }
            }
        }
    }

    /// Closes all managed desktop windows, terminates all engines, and releases notification observers.
    public func terminate() {
        if let observer = screenNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            screenNotificationObserver = nil
        }
        for (displayID, engine) in engines {
            engine.terminate()
            windows[displayID]?.contentView = nil
        }
        engines.removeAll()
        for (_, window) in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        activeWallpaper = nil
    }

    // MARK: - WallpaperEngineDelegate Conformance

    public func engineDidEncounterError(_ engine: WallpaperEngine, error: Error) {
        engineDelegate?.engineDidEncounterError(engine, error: error)
        onEngineError?(engine, error)
    }

    public func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool) {
        engineDelegate?.engineDidChangePlaybackState(engine, isPlaying: isPlaying)
        onPlaybackStateChanged?(engine, isPlaying)
    }
}
