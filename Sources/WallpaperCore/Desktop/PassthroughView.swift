import AppKit

/// A specialized AppKit container view providing Gate 2 of the dual-gate
/// event passthrough architecture for macOS live wallpapers.
///
/// In default (non-interactive) mode:
/// - `hitTest(_:)` returns `nil`, ensuring Cocoa hit-testing queries bypass the wallpaper
///   and fall through directly to Finder desktop icons and the desktop click handler.
/// - Tracking areas and cursor rectangles are discarded, preventing mouse movement events
///   or cursor changes from waking the render loop and wasting CPU/battery power.
/// - Context menus are suppressed.
///
/// In interactive mode:
/// - `hitTest(_:)` delegates to `super.hitTest(point)` and delivers clicks, drags, hover events,
///   and scroll gestures to hosted child views (e.g. `WKWebView` or custom controls).
/// - Dynamically maintains an active `NSTrackingArea` with `.mouseMoved` options so WebGL shaders
///   and Canvas animations receive continuous cursor coordinates.
/// - Allows the view hierarchy to become first responder for keyboard input.
@MainActor
public final class PassthroughView: NSView {

    // MARK: - Properties

    /// Controls whether user interactions (mouse clicks, drags, hover, scrolls, keys)
    /// are accepted and routed to child views, or completely passed through to Finder.
    public var isInteractive: Bool = false {
        didSet {
            guard oldValue != isInteractive else { return }
            updateInteractionState()
        }
    }

    /// The active hosted child view (e.g., AVPlayerLayer hosting view, WKWebView, etc.).
    /// When set, it is automatically sized to fill the bounds of `PassthroughView`
    /// with flexible resizing masks, cleanly replacing any previous child view.
    public var contentView: NSView? {
        didSet {
            guard oldValue !== contentView else { return }
            oldValue?.removeFromSuperview()
            guard let view = contentView else { return }
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    /// Optional closure callback for monitoring mouse events (useful for tests and telemetry).
    public var onMouseEvent: ((NSEvent) -> Void)?

    /// Optional closure callback for monitoring keyboard events (useful for tests and telemetry).
    public var onKeyEvent: ((NSEvent) -> Void)?

    /// Internal reference to the active tracking area for mouseMoved / hover events.
    private var activeTrackingArea: NSTrackingArea?

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        autoresizingMask = [.width, .height]
    }

    // MARK: - Hit Testing (Gate 2)

    /// Overrides AppKit hit testing to implement Gate 2 of the event passthrough architecture.
    ///
    /// - Parameter point: The point in superview coordinates (or window coordinates if root).
    /// - Returns: `nil` if non-interactive (falling through to Finder); otherwise delegates
    ///   to `super.hitTest(point)` to locate the hit subview or self.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive else {
            return nil
        }
        if let hit = super.hitTest(point) {
            return hit
        }
        if bounds.contains(point) {
            return contentView ?? self
        }
        return nil
    }

    // MARK: - Tracking Areas & Continuous Cursor Tracking

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let area = activeTrackingArea {
            removeTrackingArea(area)
            activeTrackingArea = nil
        }

        guard isInteractive else { return }

        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        activeTrackingArea = area
    }

    // MARK: - Cursor Rectangles

    public override func resetCursorRects() {
        guard isInteractive else {
            discardCursorRects()
            return
        }
        super.resetCursorRects()
    }

    // MARK: - Context Menu Suppression

    public override func menu(for event: NSEvent) -> NSMenu? {
        // Suppress default Safari developer menus and desktop menus
        guard isInteractive else { return nil }
        return nil
    }

    // MARK: - First Responder Chain

    public override var acceptsFirstResponder: Bool {
        isInteractive
    }

    // MARK: - Mouse Event Handling

    public override func mouseDown(with event: NSEvent) {
        guard isInteractive else {
            super.mouseDown(with: event)
            return
        }
        onMouseEvent?(event)
        super.mouseDown(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isInteractive else {
            super.mouseUp(with: event)
            return
        }
        onMouseEvent?(event)
        super.mouseUp(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isInteractive else {
            super.mouseDragged(with: event)
            return
        }
        onMouseEvent?(event)
        super.mouseDragged(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard isInteractive else {
            super.rightMouseDown(with: event)
            return
        }
        onMouseEvent?(event)
        super.rightMouseDown(with: event)
    }

    public override func rightMouseUp(with event: NSEvent) {
        guard isInteractive else {
            super.rightMouseUp(with: event)
            return
        }
        onMouseEvent?(event)
        super.rightMouseUp(with: event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        guard isInteractive else {
            super.rightMouseDragged(with: event)
            return
        }
        onMouseEvent?(event)
        super.rightMouseDragged(with: event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        guard isInteractive else {
            super.otherMouseDown(with: event)
            return
        }
        onMouseEvent?(event)
        super.otherMouseDown(with: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        guard isInteractive else {
            super.otherMouseUp(with: event)
            return
        }
        onMouseEvent?(event)
        super.otherMouseUp(with: event)
    }

    public override func otherMouseDragged(with event: NSEvent) {
        guard isInteractive else {
            super.otherMouseDragged(with: event)
            return
        }
        onMouseEvent?(event)
        super.otherMouseDragged(with: event)
    }

    public override func mouseMoved(with event: NSEvent) {
        guard isInteractive else {
            super.mouseMoved(with: event)
            return
        }
        onMouseEvent?(event)
        super.mouseMoved(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard isInteractive else {
            super.scrollWheel(with: event)
            return
        }
        onMouseEvent?(event)
        super.scrollWheel(with: event)
    }

    // MARK: - Keyboard Event Handling

    public override func keyDown(with event: NSEvent) {
        guard isInteractive else {
            super.keyDown(with: event)
            return
        }
        onKeyEvent?(event)
        super.keyDown(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        guard isInteractive else {
            super.keyUp(with: event)
            return
        }
        onKeyEvent?(event)
        super.keyUp(with: event)
    }

    public override func flagsChanged(with event: NSEvent) {
        guard isInteractive else {
            super.flagsChanged(with: event)
            return
        }
        onKeyEvent?(event)
        super.flagsChanged(with: event)
    }

    // MARK: - Private State Sync

    private func updateInteractionState() {
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
        if !isInteractive {
            _ = resignFirstResponder()
        }
    }
}
