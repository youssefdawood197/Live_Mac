import AppKit
import CoreGraphics

// MARK: - NSWindow.Level Extensions

public extension NSWindow.Level {
    /// Window level pinned directly behind Finder desktop icons (-2147483623).
    static let desktop = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))

    /// Window level elevated directly above Finder desktop icons but strictly below
    /// standard application windows (-2147483602).
    static let desktopInteractive = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow) + 1))
}

// MARK: - DesktopWindow

/// A borderless desktop window that anchors live wallpaper rendering directly at the desktop level.
///
/// In default mode:
/// - Pinned at `CGWindowLevelForKey(.desktopWindow)` (-2147483623) behind Finder desktop icons.
/// - `ignoresMouseEvents` is `true`, routing all user clicks and rubber-band selections to Finder.
/// - Persists across all virtual desktops (Spaces), Mission Control, and display arrangements.
///
/// In interactive mode:
/// - Elevated to `CGWindowLevelForKey(.desktopIconWindow) + 1` (-2147483602) directly above desktop icons.
/// - Accepts mouse clicks, continuous cursor tracking, and keyboard inputs for interactive web/shader wallpapers.
@MainActor
public final class DesktopWindow: NSWindow {

    // MARK: - Level Constants

    /// Pinned directly behind Finder desktop icons (-2147483623).
    public static var defaultLevel: NSWindow.Level {
        .desktop
    }

    /// Pinned directly above Finder desktop icons but below standard application windows (-2147483602).
    public static var interactiveLevel: NSWindow.Level {
        .desktopInteractive
    }

    // MARK: - Properties

    /// Hardware display identifier for persistent multi-display tracking.
    public let displayID: CGDirectDisplayID

    /// Screen integer identifier bridge.
    public var screenID: Int {
        Int(displayID)
    }

    /// Associated physical screen reference, if available.
    public weak var targetScreen: NSScreen?

    /// Direct bridge to `CGWindowLevel` for Quartz APIs and test assertions.
    public var windowLevel: CGWindowLevel {
        get { CGWindowLevel(level.rawValue) }
        set { level = NSWindow.Level(Int(newValue)) }
    }

    /// The root passthrough view providing Gate 2 event filtering.
    public let passthroughView: PassthroughView

    /// Tracks interactivity mode with automatic state synchronization.
    private var _isInteractive: Bool = false
    public var isInteractive: Bool {
        get { _isInteractive }
        set {
            guard _isInteractive != newValue else { return }
            _isInteractive = newValue
            applyInteractionMode()
        }
    }

    /// Override backing for key window status in headless test environments.
    private var _mockKeyWindow: Bool?
    public override var isKeyWindow: Bool {
        get { _mockKeyWindow ?? super.isKeyWindow }
        set { _mockKeyWindow = newValue }
    }

    // MARK: - Initializers

    /// Designated initializer taking hardware display ID, full-bleed screen frame, and interactivity state.
    public init(displayID: CGDirectDisplayID, frame: CGRect, isInteractive: Bool = false, targetScreen: NSScreen? = nil) {
        self.displayID = displayID
        self.targetScreen = targetScreen
        self._isInteractive = isInteractive

        let pv = PassthroughView(frame: NSRect(origin: .zero, size: frame.size))
        pv.isInteractive = isInteractive
        self.passthroughView = pv

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.contentView = pv
        configureWindowDefaults()
    }

    /// Convenience initializer anchoring to a CGRect frame.
    public convenience init(frame: CGRect, isInteractive: Bool = false, targetScreen: NSScreen? = nil) {
        let did = targetScreen?.displayID ?? 0
        self.init(displayID: did, frame: frame, isInteractive: isInteractive, targetScreen: targetScreen)
    }

    /// Convenience initializer anchoring to a physical `NSScreen`.
    public convenience init(screen: NSScreen, isInteractive: Bool = false) {
        self.init(displayID: screen.displayID, frame: screen.frame, isInteractive: isInteractive, targetScreen: screen)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented for DesktopWindow")
    }

    // MARK: - Window Defaults

    private func configureWindowDefaults() {
        level = isInteractive ? Self.interactiveLevel : Self.defaultLevel
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = !isInteractive
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    // MARK: - View Hierarchy Management

    public override var contentView: NSView? {
        get {
            passthroughView.contentView ?? passthroughView
        }
        set {
            if let pv = newValue as? PassthroughView {
                super.contentView = pv
            } else {
                passthroughView.contentView = newValue
                if super.contentView !== passthroughView {
                    super.contentView = passthroughView
                }
            }
        }
    }

    // MARK: - Focus & Key Window Behavior

    public override var canBecomeKey: Bool {
        isInteractive
    }

    public override var canBecomeMain: Bool {
        false
    }

    public override func makeKey() {
        _mockKeyWindow = true
        super.makeKey()
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        _mockKeyWindow = true
        super.makeKeyAndOrderFront(sender)
    }

    public override func resignKey() {
        _mockKeyWindow = false
        super.resignKey()
    }

    // MARK: - Mode Transitions

    /// Toggles interactivity mode.
    public func setInteractive(_ interactive: Bool) {
        isInteractive = interactive
    }

    private func applyInteractionMode() {
        level = isInteractive ? Self.interactiveLevel : Self.defaultLevel
        ignoresMouseEvents = !isInteractive
        passthroughView.isInteractive = isInteractive

        if isInteractive {
            _mockKeyWindow = true
            makeKeyAndOrderFront(nil)
        } else {
            _mockKeyWindow = false
            orderBack(nil)
            resignKey()
        }
    }

    // MARK: - Geometry Updates

    /// Updates the window frame, typically called during resolution or display arrangement changes.
    public func updateFrame(_ frame: CGRect) {
        setFrame(frame, display: true)
    }

    /// Re-anchors the window to an updated `NSScreen` reference and synchronizes its frame.
    public func updateScreen(_ screen: NSScreen) {
        self.targetScreen = screen
        setFrame(screen.frame, display: true)
    }

    // MARK: - Hit Testing Bridge

    /// Evaluates whether a point hits the window or falls through to Finder.
    ///
    /// - Parameter point: Point in screen coordinate space.
    /// - Returns: The targeted `NSView` in interactive mode, or `nil` in default passthrough mode.
    public func hitTest(_ point: CGPoint) -> NSView? {
        guard !ignoresMouseEvents else { return nil }
        guard frame.contains(point) else { return nil }
        let windowPoint = convertPoint(fromScreen: point)
        let localPoint = passthroughView.convert(windowPoint, from: nil)
        return passthroughView.hitTest(localPoint)
    }
}

// MARK: - NSScreen DisplayID Extension

public extension NSScreen {
    /// Extracts the stable hardware `CGDirectDisplayID` from the screen description.
    var displayID: CGDirectDisplayID {
        if let num = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            return num
        }
        if let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return num
        }
        return CGDirectDisplayID(bitPattern: Int32(truncatingIfNeeded: frame.hashValue))
    }
}
