import SpriteKit
import AppKit
import CoreGraphics

/// High-performance SpriteKit scene driving the ambient snowfall simulation, physical
/// snow accumulation on window ledges, automated snowplow sweeps, and festive fairy lights.
@MainActor
public final class FlakeScene: SKScene {

    // MARK: - Configuration & State

    public var config: FlakeConfiguration = FlakeConfiguration() {
        didSet {
            applyConfiguration()
        }
    }

    public var surfaceDetector: any WindowSurfaceDetectorProtocol = WindowSurfaceDetector()

    public var surfaces: [CollisionSurface] {
        surfacesList
    }
    private var surfacesList: [CollisionSurface] = []

    /// Heightmap tracking per surface: [SurfaceID : SurfaceHeightmap]
    public var heightmaps: [CGWindowID: SurfaceHeightmap] = [:]

    /// Stored previous surfaces for window delta (dx, dy) re-anchoring
    private var previousSurfaces: [CGWindowID: CollisionSurface] = [:]

    /// Rendered snowbank shape nodes: [SurfaceID : SKShapeNode]
    private var snowbankNodes: [CGWindowID: SKShapeNode] = [:]

    /// Fairy light nodes: [SurfaceID : [SKNode]]
    private var fairyLightNodes: [CGWindowID: [SKNode]] = [:]

    /// Snow particle emitter node
    public private(set) var emitterNode: SKEmitterNode?

    /// Active snowplow sprite and state
    private var snowplowNode: SKNode?
    public private(set) var isSnowplowActive: Bool = false

    /// Last time window surfaces were polled (polled at 10 Hz for battery savings)
    private var lastSurfacePollTime: TimeInterval = 0

    /// Cached reusable snowflake texture
    private static let snowflakeTexture: SKTexture = {
        let diameter: CGFloat = 12
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        NSColor.white.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        path.fill()
        image.unlockFocus()
        return SKTexture(image: image)
    }()

    // MARK: - Initializers

    public override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        setupEmitter()
        applyConfiguration()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundColor = .clear
        scaleMode = .resizeFill
        setupEmitter()
        applyConfiguration()
    }

    // MARK: - Scene Lifecycle

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = .clear
        scaleMode = .resizeFill
        view.allowsTransparency = true

        if emitterNode == nil {
            setupEmitter()
        }
        applyConfiguration()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        emitterNode?.position = CGPoint(x: size.width / 2, y: size.height + 20)
        emitterNode?.particlePositionRange = CGVector(dx: size.width * 1.4, dy: 30)
    }

    // MARK: - Emitter Setup & Particle Dynamics

    private func setupEmitter() {
        emitterNode?.removeFromParent()

        let emitter = SKEmitterNode()
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 20)
        emitter.particlePositionRange = CGVector(dx: max(100, size.width * 1.4), dy: 30)
        emitter.particleBirthRate = config.isEnabled ? config.intensity.birthRate : 0
        emitter.numParticlesToEmit = 0 // Continuous
        emitter.particleLifetime = config.intensity.particleLifetime
        emitter.particleSpeed = 60 * config.intensity.fallSpeedMultiplier
        emitter.particleSpeedRange = 30
        emitter.particleAlpha = 0.85
        emitter.particleAlphaRange = 0.25
        emitter.particleScale = 0.25
        emitter.particleScaleRange = 0.15
        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 1.0
        emitter.particleTexture = Self.snowflakeTexture

        updateWindVectors(emitter: emitter)

        addChild(emitter)
        self.emitterNode = emitter
    }

    // MARK: - 360° Directional Wind Acceleration Trigonometry

    public nonisolated static func calculateWindAcceleration(
        windAngleDegrees: Double,
        windSpeed: Double,
        baseGravity: CGFloat = 120.0
    ) -> (ax: CGFloat, ay: CGFloat) {
        let rad = CGFloat(windAngleDegrees) * .pi / 180.0
        let windAcc: CGFloat = windSpeed <= 3.0 ? CGFloat(windSpeed) * 200.0 : CGFloat(min(600.0, windSpeed))
        let ax = windAcc * cos(rad)
        let ay = -baseGravity - windAcc * sin(rad)
        return (ax, ay)
    }

    private func updateWindVectors(emitter: SKEmitterNode) {
        let (ax, ay) = Self.calculateWindAcceleration(
            windAngleDegrees: config.windAngleDegrees,
            windSpeed: config.windSpeed
        )
        emitter.xAcceleration = ax
        emitter.yAcceleration = ay
    }

    // MARK: - Configuration Application

    public func applyConfiguration() {
        guard let emitter = emitterNode else { return }

        let intensity = config.intensity
        emitter.particleBirthRate = config.isEnabled ? intensity.birthRate : 0
        emitter.particleSpeed = 60 * intensity.fallSpeedMultiplier
        emitter.particleLifetime = intensity.particleLifetime

        updateWindVectors(emitter: emitter)

        if !config.fairyLightsEnabled {
            clearFairyLights()
        }

        if !config.isEnabled {
            clearAllSnow()
        }
    }

    // MARK: - Simulation Update Loop

    public override func update(_ currentTime: TimeInterval) {
        guard config.isEnabled else { return }

        // Centralized / fallback throttle: 10 Hz window surface query
        if currentTime - lastSurfacePollTime >= 0.1 {
            lastSurfacePollTime = currentTime
            updateSurfaces()
        }

        // Accumulate snow on visible surfaces
        accumulateSnow(deltaTime: 0.1)

        // Check snowplow sweep condition
        checkSnowplowTrigger()
    }

    // MARK: - Window Surface Synchronization & Movement Re-anchoring

    public func updateSurfaces(visibleFrame: CGRect? = nil) {
        let screenRect = CGRect(origin: .zero, size: size)
        let visible = visibleFrame ?? screenRect
        let newSurfaces = surfaceDetector.detectSurfaces(
            screenRect: screenRect,
            visibleFrame: visible,
            primaryScreenHeight: nil,
            config: config
        )
        self.surfacesList = newSurfaces

        let activeIDs = Set(newSurfaces.map { $0.id })

        // Remove snowbanks and fairy lights for closed windows
        let closedIDs = Set(heightmaps.keys).union(snowbankNodes.keys).union(fairyLightNodes.keys).filter { !activeIDs.contains($0) }
        for id in closedIDs {
            snowbankNodes[id]?.removeFromParent()
            snowbankNodes.removeValue(forKey: id)
            heightmaps.removeValue(forKey: id)
            previousSurfaces.removeValue(forKey: id)
            fairyLightNodes[id]?.forEach { $0.removeFromParent() }
            fairyLightNodes.removeValue(forKey: id)
        }

        // Initialize or reposition heightmaps and fairy lights
        for surface in newSurfaces {
            let anchor = CGPoint(x: surface.minX, y: surface.topEdgeY)

            if var existing = heightmaps[surface.id] {
                // Feature 14: Window Movement Re-anchoring via delta (dx, dy)
                if let prev = previousSurfaces[surface.id] {
                    let dx = surface.minX - prev.minX
                    let dy = surface.topEdgeY - prev.topEdgeY

                    if dx != 0 || dy != 0 {
                        _ = existing.reanchor(newAnchor: anchor)
                        snowbankNodes[surface.id]?.position = anchor

                        if let lights = fairyLightNodes[surface.id] {
                            for light in lights {
                                light.position.x += dx
                                light.position.y += dy
                            }
                        }
                    }
                }

                // Resize width if changed, preserving existing accumulated depth
                existing.resize(to: surface.width)
                heightmaps[surface.id] = existing
            } else {
                heightmaps[surface.id] = SurfaceHeightmap(
                    surfaceID: surface.id,
                    width: surface.width,
                    anchorPosition: anchor
                )
            }

            previousSurfaces[surface.id] = surface

            if config.fairyLightsEnabled && surface.id != 0 {
                updateFairyLights(for: surface)
            }
        }
    }

    // MARK: - Snow Accumulation Physics & Surface Caps

    public nonisolated static func calculateMaxCap(for surface: CollisionSurface, screenHeight: CGFloat) -> CGFloat {
        let baseCap: CGFloat
        if surface.id == 0 {
            baseCap = 50.0 // Bottom display shelf
        } else if surface.isDock {
            baseCap = 30.0 // macOS Dock
        } else {
            baseCap = 22.0 // Standard application window
        }
        let ceilingMargin = max(0, screenHeight - surface.topEdgeY)
        return min(baseCap, ceilingMargin)
    }

    private func accumulateSnow(deltaTime: CGFloat) {
        let rate = config.intensity.birthRate * 0.00035

        for surface in surfacesList {
            guard var heightmap = heightmaps[surface.id] else { continue }

            let maxCap = Self.calculateMaxCap(for: surface, screenHeight: size.height)

            // Feature 12: Column-Based Heightmap Accumulation (10px binning)
            heightmap.accumulate(
                rate: rate,
                maxCap: maxCap,
                windAngleDegrees: config.windAngleDegrees,
                windSpeed: config.windSpeed
            )

            // Feature 13: Double-buffered Angle of Repose Smoothing
            heightmap.smoothAngleOfRepose(maxCap: maxCap)

            heightmaps[surface.id] = heightmap
            renderSnowbank(for: surface, heightmap: heightmap)
        }
    }

    private func renderSnowbank(for surface: CollisionSurface, heightmap: SurfaceHeightmap) {
        let bins = heightmap.bins
        guard !bins.isEmpty else { return }

        let path = CGMutablePath()
        let binWidth: CGFloat = surface.width / CGFloat(bins.count)

        // Draw in local coordinates anchored to (0, 0)
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: bins[0]))

        for i in 0..<(bins.count - 1) {
            let p0 = CGPoint(x: CGFloat(i) * binWidth + binWidth / 2, y: bins[i])
            let p1 = CGPoint(x: CGFloat(i + 1) * binWidth + binWidth / 2, y: bins[i + 1])
            let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            path.addQuadCurve(to: mid, control: p0)
        }

        if let last = bins.last {
            path.addLine(to: CGPoint(x: surface.width, y: last))
        }
        path.addLine(to: CGPoint(x: surface.width, y: 0))
        path.closeSubpath()

        let anchor = CGPoint(x: surface.minX, y: surface.topEdgeY)
        let shapeNode: SKShapeNode
        if let existing = snowbankNodes[surface.id] {
            shapeNode = existing
            shapeNode.path = path
            shapeNode.position = anchor
        } else {
            shapeNode = SKShapeNode(path: path)
            shapeNode.position = anchor
            shapeNode.fillColor = NSColor.white.withAlphaComponent(0.92)
            shapeNode.strokeColor = NSColor.white.withAlphaComponent(0.5)
            shapeNode.lineWidth = 1
            shapeNode.zPosition = 10
            addChild(shapeNode)
            snowbankNodes[surface.id] = shapeNode
        }
    }

    // MARK: - Automated Snowplow

    private func checkSnowplowTrigger() {
        guard config.snowplowEnabled, !isSnowplowActive else { return }

        // Trigger snowplow when bottom drift (id = 0) exceeds 32px average
        if let bottomHeightmap = heightmaps[0], !bottomHeightmap.bins.isEmpty {
            if bottomHeightmap.averageDepth > 32 {
                triggerSnowplowSweep()
            }
        }
    }

    public func triggerSnowplowSweep() {
        guard !isSnowplowActive else { return }
        isSnowplowActive = true

        let plow = createPlowNode()

        plow.position = CGPoint(x: -60, y: 16)
        plow.zPosition = 30
        addChild(plow)
        self.snowplowNode = plow

        let moveRight = SKAction.moveTo(x: size.width + 60, duration: 4.5)
        let remove = SKAction.run { [weak self] in
            plow.removeFromParent()
            self?.isSnowplowActive = false
            if var bottom = self?.heightmaps[0] {
                bottom.bins = Array(repeating: 0.0, count: bottom.bins.count)
                self?.heightmaps[0] = bottom
                if let surface = self?.surfacesList.first(where: { $0.id == 0 }) {
                    self?.renderSnowbank(for: surface, heightmap: bottom)
                }
            }
        }

        plow.run(SKAction.sequence([moveRight, remove]))
    }

    private func createPlowNode() -> SKNode {
        let plow = SKNode()

        switch config.snowplowModel {
        case .custom:
            if let url = config.customPlowImageURL,
               let image = NSImage(contentsOf: url) {
                let texture = SKTexture(image: image)
                let sprite = SKSpriteNode(texture: texture)
                let targetHeight: CGFloat = 36
                let scale = targetHeight / max(image.size.height, 1)
                sprite.size = CGSize(width: image.size.width * scale, height: targetHeight)
                plow.addChild(sprite)
                return plow
            }
            fallthrough

        case .classicTractor:
            let bodyNode = SKShapeNode(rectOf: CGSize(width: 44, height: 26), cornerRadius: 5)
            bodyNode.fillColor = NSColor.systemYellow
            bodyNode.strokeColor = NSColor.black.withAlphaComponent(0.4)
            plow.addChild(bodyNode)

            let cab = SKShapeNode(rectOf: CGSize(width: 18, height: 14), cornerRadius: 2)
            cab.fillColor = NSColor.systemBlue.withAlphaComponent(0.7)
            cab.position = CGPoint(x: -6, y: 5)
            plow.addChild(cab)

            let blade = SKShapeNode(rectOf: CGSize(width: 8, height: 28), cornerRadius: 2)
            blade.fillColor = NSColor.darkGray
            blade.position = CGPoint(x: 22, y: -2)
            plow.addChild(blade)

        case .vintageTractor:
            let bodyNode = SKShapeNode(rectOf: CGSize(width: 46, height: 24), cornerRadius: 6)
            bodyNode.fillColor = NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.2, alpha: 1.0)
            bodyNode.strokeColor = NSColor.black.withAlphaComponent(0.4)
            plow.addChild(bodyNode)

            let chimney = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
            chimney.fillColor = NSColor.black
            chimney.position = CGPoint(x: 14, y: 14)
            plow.addChild(chimney)

            let blade = SKShapeNode(rectOf: CGSize(width: 8, height: 28), cornerRadius: 2)
            blade.fillColor = NSColor.systemRed
            blade.position = CGPoint(x: 23, y: -2)
            plow.addChild(blade)

        case .snowmobile:
            let chassis = SKShapeNode(rectOf: CGSize(width: 48, height: 18), cornerRadius: 8)
            chassis.fillColor = NSColor.systemRed
            chassis.strokeColor = NSColor.black.withAlphaComponent(0.4)
            plow.addChild(chassis)

            let ski = SKShapeNode(rectOf: CGSize(width: 24, height: 4), cornerRadius: 2)
            ski.fillColor = NSColor.lightGray
            ski.position = CGPoint(x: 16, y: -10)
            plow.addChild(ski)

            let windshield = SKShapeNode(rectOf: CGSize(width: 12, height: 12), cornerRadius: 3)
            windshield.fillColor = NSColor.cyan.withAlphaComponent(0.6)
            windshield.position = CGPoint(x: 4, y: 8)
            plow.addChild(windshield)

        case .penguin:
            let body = SKShapeNode(ellipseOf: CGSize(width: 24, height: 32))
            body.fillColor = NSColor.black
            plow.addChild(body)

            let belly = SKShapeNode(ellipseOf: CGSize(width: 14, height: 22))
            belly.fillColor = NSColor.white
            belly.position = CGPoint(x: 2, y: -2)
            plow.addChild(belly)

            let beak = SKShapeNode(rectOf: CGSize(width: 8, height: 4), cornerRadius: 1)
            beak.fillColor = NSColor.systemOrange
            beak.position = CGPoint(x: 12, y: 8)
            plow.addChild(beak)

            let shovel = SKShapeNode(rectOf: CGSize(width: 6, height: 24), cornerRadius: 2)
            shovel.fillColor = NSColor.systemBlue
            shovel.position = CGPoint(x: 16, y: -4)
            plow.addChild(shovel)
        }

        return plow
    }

    // MARK: - Window Fairy Lights

    private func updateFairyLights(for surface: CollisionSurface) {
        if let existing = fairyLightNodes[surface.id], !existing.isEmpty {
            return
        }

        var lights: [SKNode] = []
        let lightSpacing: CGFloat = 28
        let count = max(1, Int(surface.width / lightSpacing))
        let colors: [NSColor] = [.systemYellow, .systemRed, .systemGreen, .systemBlue, .systemOrange]

        for i in 0..<count {
            let x = surface.minX + CGFloat(i) * lightSpacing + 14
            let y = surface.topEdgeY - 2

            let light = SKShapeNode(circleOfRadius: 3.5)
            let color = colors[i % colors.count]
            light.fillColor = color
            light.strokeColor = color.withAlphaComponent(0.8)
            light.glowWidth = 2.5
            light.position = CGPoint(x: x, y: y)
            light.zPosition = 15

            let pulseUp = SKAction.fadeAlpha(to: 1.0, duration: Double.random(in: 0.6...1.2))
            let pulseDown = SKAction.fadeAlpha(to: 0.3, duration: Double.random(in: 0.6...1.2))
            let sequence = SKAction.sequence([pulseDown, pulseUp])
            light.run(SKAction.repeatForever(sequence))

            addChild(light)
            lights.append(light)
        }

        fairyLightNodes[surface.id] = lights
    }

    private func clearFairyLights() {
        for (_, nodes) in fairyLightNodes {
            nodes.forEach { $0.removeFromParent() }
        }
        fairyLightNodes.removeAll()
    }

    // MARK: - Interactive Mitten & Shovel Clearing

    public func clearSnowAtPoint(_ point: CGPoint, radius: CGFloat = 45) {
        for (id, var heightmap) in heightmaps {
            guard let surface = surfacesList.first(where: { $0.id == id }) else { continue }
            guard abs(point.y - surface.topEdgeY) < radius + 20 else { continue }

            let binWidth = surface.width / CGFloat(heightmap.bins.count)
            for i in 0..<heightmap.bins.count {
                let binX = surface.minX + CGFloat(i) * binWidth + binWidth / 2
                if abs(point.x - binX) < radius {
                    heightmap.bins[i] = max(0, heightmap.bins[i] - 12)
                }
            }
            heightmaps[id] = heightmap
            renderSnowbank(for: surface, heightmap: heightmap)
        }
    }

    public func clearAllSnow() {
        for (_, shapeNode) in snowbankNodes {
            shapeNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.4),
                SKAction.removeFromParent()
            ]))
        }
        snowbankNodes.removeAll()
        for (id, var map) in heightmaps {
            map.bins = Array(repeating: 0.0, count: map.bins.count)
            heightmaps[id] = map
        }
    }
}
