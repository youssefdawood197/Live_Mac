import AppKit
import SpriteKit

/// A transparent, borderless overlay window hovering above standard application windows
/// to render ambient falling snowflakes and window-accumulated snowdrifts.
@MainActor
public final class FlakeOverlayWindow: NSWindow {

    public let flakeScene: FlakeScene
    public let skView: SKView

    public init(
        frame: CGRect,
        config: FlakeConfiguration = FlakeConfiguration(),
        surfaceDetector: (any WindowSurfaceDetectorProtocol)? = nil
    ) {
        let scene = FlakeScene(size: frame.size)
        if let detector = surfaceDetector {
            scene.surfaceDetector = detector
        }
        scene.config = config

        let view = SKView(frame: NSRect(origin: .zero, size: frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.presentScene(scene)

        self.flakeScene = scene
        self.skView = view

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.contentView = view
        configureOverlayWindow()
    }

    private func configureOverlayWindow() {
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        // Default to pure click-through transparency
        updateMouseInteractivity()
    }

    public func updateMouseInteractivity() {
        // If an interactive clearing tool is active, accept cursor events
        if flakeScene.config.activeTool != .none {
            ignoresMouseEvents = false
            acceptsMouseMovedEvents = true
        } else {
            ignoresMouseEvents = true
            acceptsMouseMovedEvents = false
        }
    }

    public func updateFrame(_ newFrame: CGRect) {
        setFrame(newFrame, display: true)
        skView.frame = NSRect(origin: .zero, size: newFrame.size)
        flakeScene.size = newFrame.size
    }

    // MARK: - Mouse Event Handling for Mitten & Shovel Tools

    public override func mouseMoved(with event: NSEvent) {
        guard flakeScene.config.activeTool != .none else {
            super.mouseMoved(with: event)
            return
        }
        let location = event.locationInWindow
        flakeScene.clearSnowAtPoint(location, radius: flakeScene.config.activeTool == .shovel ? 60 : 40)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard flakeScene.config.activeTool != .none else {
            super.mouseDragged(with: event)
            return
        }
        let location = event.locationInWindow
        flakeScene.clearSnowAtPoint(location, radius: flakeScene.config.activeTool == .shovel ? 60 : 40)
    }
}
