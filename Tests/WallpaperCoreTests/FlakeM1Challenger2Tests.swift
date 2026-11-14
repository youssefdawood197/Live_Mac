import XCTest
import SpriteKit
@testable import WallpaperCore

/// Adversarial empirical test harness verifying Features 8-15 of Milestone 1.
final class FlakeM1Challenger2Tests: XCTestCase {

    // MARK: - Feature 8 & 9: Particle Dynamics & Intensity Budgets

    func testParticleDynamics_exactBudgetInvariants() {
        for intensity in SnowfallIntensity.allCases {
            let budget = intensity.maxParticles
            let rate = intensity.birthRate
            let lifetime = intensity.particleLifetime
            let calculatedBudget = rate * lifetime

            XCTAssertEqual(
                CGFloat(budget),
                calculatedBudget,
                accuracy: 0.001,
                "Intensity \(intensity.rawValue) must satisfy maxParticles == birthRate * particleLifetime"
            )
            XCTAssertTrue(rate > 0, "Birth rate must be positive for \(intensity)")
            XCTAssertTrue(lifetime > 0, "Lifetime must be positive for \(intensity)")
            XCTAssertTrue(intensity.fallSpeedMultiplier > 0, "Fall speed multiplier must be positive")
        }
    }

    func testParticleDynamics_monotonicIntensityScaling() {
        // Light < Steady < Blizzard
        let light = SnowfallIntensity.light
        let steady = SnowfallIntensity.steady
        let blizzard = SnowfallIntensity.blizzard

        XCTAssertLessThan(light.maxParticles, steady.maxParticles)
        XCTAssertLessThan(steady.maxParticles, blizzard.maxParticles)

        XCTAssertLessThan(light.birthRate, steady.birthRate)
        XCTAssertLessThan(steady.birthRate, blizzard.birthRate)

        XCTAssertLessThan(light.fallSpeedMultiplier, steady.fallSpeedMultiplier)
        XCTAssertLessThan(steady.fallSpeedMultiplier, blizzard.fallSpeedMultiplier)
    }

    @MainActor
    func testParticleDynamics_emitterStateOnDisabledAndEnabled() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        let view = SKView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        scene.didMove(to: view)

        guard let emitter = scene.emitterNode else {
            XCTFail("Emitter node must be initialized")
            return
        }

        // Disabled state: birth rate must be 0
        scene.config.isEnabled = false
        scene.applyConfiguration()
        XCTAssertEqual(emitter.particleBirthRate, 0.0, "Disabled scene must have 0 birth rate")

        // Enabled state: birth rate must match configured intensity
        scene.config.isEnabled = true
        scene.config.intensity = .blizzard
        scene.applyConfiguration()
        XCTAssertEqual(emitter.particleBirthRate, 120.0, "Blizzard must set birth rate to 120.0")
        XCTAssertEqual(emitter.particleLifetime, 7.5, accuracy: 0.001)
        XCTAssertEqual(emitter.particleSpeed, 60.0 * 1.4, accuracy: 0.001)

        // Switch to steady
        scene.config.intensity = .steady
        scene.applyConfiguration()
        XCTAssertEqual(emitter.particleBirthRate, 50.0)
        XCTAssertEqual(emitter.particleLifetime, 8.0, accuracy: 0.001)

        // Switch to light
        scene.config.intensity = .light
        scene.applyConfiguration()
        XCTAssertEqual(emitter.particleBirthRate, 20.0)
        XCTAssertEqual(emitter.particleLifetime, 7.5, accuracy: 0.001)
    }

    // MARK: - Feature 10 & 11: 360° Wind Trigonometry Across All 4 Quadrants

    func testWindTrigonometry_allCardinalDirections() {
        let baseGravity: CGFloat = 120.0
        let windSpeed: Double = 1.5 // 300 px/s²

        // 0°: Due East (+X, gravity unchanged)
        let (ax0, ay0) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertEqual(ax0, 300.0, accuracy: 0.001)
        XCTAssertEqual(ay0, -baseGravity, accuracy: 0.001)

        // 90°: Straight Down (0 X, boosted gravity)
        let (ax90, ay90) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertEqual(ax90, 0.0, accuracy: 0.001)
        XCTAssertEqual(ay90, -baseGravity - 300.0, accuracy: 0.001)

        // 180°: Due West (-X, gravity unchanged)
        let (ax180, ay180) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 180, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertEqual(ax180, -300.0, accuracy: 0.001)
        XCTAssertEqual(ay180, -baseGravity, accuracy: 0.001)

        // 270°: Straight Up (0 X, updraft opposing gravity)
        let (ax270, ay270) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertEqual(ax270, 0.0, accuracy: 0.001)
        XCTAssertEqual(ay270, -baseGravity + 300.0, accuracy: 0.001)

        // 360°: Same as 0° (East)
        let (ax360, ay360) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 360, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertEqual(ax360, 300.0, accuracy: 0.001)
        XCTAssertEqual(ay360, -baseGravity, accuracy: 0.001)
    }

    func testWindTrigonometry_fourDiagonalQuadrants() {
        let baseGravity: CGFloat = 120.0
        let windSpeed: Double = 2.0 // 400 px/s²
        let expectedAcc: CGFloat = 400.0
        let diagonal = expectedAcc * (CGFloat.pi / 4).cosValue // ~282.8427

        // Quadrant I: 45° (South-East: +X, extra down)
        let (ax45, ay45) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 45, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertTrue(ax45 > 0, "45° must blow East (+X)")
        XCTAssertTrue(ay45 < -baseGravity, "45° must push downward")
        XCTAssertEqual(ax45, diagonal, accuracy: 0.01)
        XCTAssertEqual(ay45, -baseGravity - diagonal, accuracy: 0.01)

        // Quadrant II: 135° (South-West: -X, extra down)
        let (ax135, ay135) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 135, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertTrue(ax135 < 0, "135° must blow West (-X)")
        XCTAssertTrue(ay135 < -baseGravity, "135° must push downward")
        XCTAssertEqual(ax135, -diagonal, accuracy: 0.01)
        XCTAssertEqual(ay135, -baseGravity - diagonal, accuracy: 0.01)

        // Quadrant III: 225° (North-West: -X, updraft)
        let (ax225, ay225) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 225, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertTrue(ax225 < 0, "225° must blow West (-X)")
        XCTAssertTrue(ay225 > -baseGravity, "225° must create updraft")
        XCTAssertEqual(ax225, -diagonal, accuracy: 0.01)
        XCTAssertEqual(ay225, -baseGravity + diagonal, accuracy: 0.01)

        // Quadrant IV: 315° (North-East: +X, updraft)
        let (ax315, ay315) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 315, windSpeed: windSpeed, baseGravity: baseGravity)
        XCTAssertTrue(ax315 > 0, "315° must blow East (+X)")
        XCTAssertTrue(ay315 > -baseGravity, "315° must create updraft")
        XCTAssertEqual(ax315, diagonal, accuracy: 0.01)
        XCTAssertEqual(ay315, -baseGravity + diagonal, accuracy: 0.01)
    }

    func testWindTrigonometry_exhaustive360DegreesVectorNorm() {
        let baseGravity: CGFloat = 120.0
        let windSpeed: Double = 2.5 // 500 px/s²
        let expectedMagnitude: CGFloat = 500.0

        // Test every single degree from 0° to 359°
        for deg in 0..<360 {
            let (ax, ay) = FlakeScene.calculateWindAcceleration(
                windAngleDegrees: Double(deg),
                windSpeed: windSpeed,
                baseGravity: baseGravity
            )
            // Magnitude of wind contribution vector: sqrt(ax^2 + (ay - (-baseGravity))^2)
            let windY = ay - (-baseGravity)
            let calculatedMagnitude = sqrt(ax * ax + windY * windY)
            XCTAssertEqual(
                calculatedMagnitude,
                expectedMagnitude,
                accuracy: 0.001,
                "Wind acceleration vector magnitude at \(deg)° must equal \(expectedMagnitude)"
            )
        }
    }

    func testWindSpeed_maxCapAt600() {
        let baseGravity: CGFloat = 120.0
        // Test values up to and beyond 600 px/s²
        let speeds: [Double] = [0.0, 1.0, 2.0, 3.0, 300.0, 500.0, 600.0, 750.0, 1000.0]

        for s in speeds {
            let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0, windSpeed: s, baseGravity: baseGravity)
            XCTAssertLessThanOrEqual(ax, 600.0 + 0.001, "Wind acceleration must never exceed 600 px/s²")
        }
    }

    // MARK: - Feature 12: Column-Based Heightmap 10px Binning & Resizing

    func testHeightmap_binCountQuantization() {
        // 10px binning verification
        let testCases: [(width: CGFloat, expectedBins: Int)] = [
            (0.0, 1),      // degenerate 0 width clamped to 1 bin
            (1.0, 1),      // 1pt -> 1 bin
            (9.99, 1),    // < 10pt -> 1 bin
            (10.0, 1),     // 10pt -> 1 bin
            (10.01, 2),    // 10.01pt -> 2 bins
            (19.99, 2),    // < 20pt -> 2 bins
            (20.0, 2),     // 20pt -> 2 bins
            (20.1, 3),     // 20.1pt -> 3 bins
            (120.0, 12),   // min window width 120pt -> 12 bins
            (800.0, 80),   // 800pt -> 80 bins
            (1920.0, 192), // 1080p width -> 192 bins
            (2560.0, 256), // 1440p width -> 256 bins
            (3840.0, 384)  // 4k width -> 384 bins
        ]

        for (width, expected) in testCases {
            let map = SurfaceHeightmap(surfaceID: 1, width: width)
            XCTAssertEqual(map.bins.count, expected, "Width \(width) must produce \(expected) bins of 10px")
        }
    }

    func testHeightmap_resizingPreservesAccumulatedDepth() {
        var map = SurfaceHeightmap(surfaceID: 10, width: 200) // 20 bins
        XCTAssertEqual(map.bins.count, 20)

        // Seed distinctive depth pattern
        for i in 0..<20 {
            map.bins[i] = CGFloat(i + 1)
        }
        _ = map.averageDepth

        // 1. Expand to 300 (30 bins)
        map.resize(to: 300)
        XCTAssertEqual(map.bins.count, 30)
        // First 20 bins must be identical to original
        for i in 0..<20 {
            XCTAssertEqual(map.bins[i], CGFloat(i + 1), "Expanded map must preserve original bin \(i)")
        }
        // New 10 bins must be 0.0
        for i in 20..<30 {
            XCTAssertEqual(map.bins[i], 0.0, "New bins in expanded map must be initialized to 0")
        }

        // 2. Shrink to 100 (10 bins)
        map.resize(to: 100)
        XCTAssertEqual(map.bins.count, 10)
        for i in 0..<10 {
            XCTAssertEqual(map.bins[i], CGFloat(i + 1), "Shrunk map must preserve surviving prefix bin \(i)")
        }

        // 3. No-op resize to same width
        map.resize(to: 100)
        XCTAssertEqual(map.bins.count, 10)
    }

    func testHeightmap_emptyAndSingleBinSafety() {
        // Defensive check: empty bins array must not divide by zero
        let emptyMap = SurfaceHeightmap(surfaceID: 99, bins: [])
        XCTAssertEqual(emptyMap.averageDepth, 0.0)
        XCTAssertEqual(emptyMap.maxDepth, 0.0)

        // Single bin
        var singleMap = SurfaceHeightmap(surfaceID: 99, width: 5)
        XCTAssertEqual(singleMap.bins.count, 1)
        singleMap.bins[0] = 14.5
        XCTAssertEqual(singleMap.averageDepth, 14.5)
        XCTAssertEqual(singleMap.maxDepth, 14.5)

        // Single bin smoothing must be no-op and not crash
        singleMap.smoothAngleOfRepose(maxCap: 22.0)
        XCTAssertEqual(singleMap.bins[0], 14.5)
    }

    // MARK: - Feature 13: Angle of Repose Convolution Symmetry Stress Test

    func testAngleOfRepose_strictSymmetryOnImpulseOddLength() {
        // Delta impulse centered on an odd-length array (e.g. 15 bins, center = 7)
        var bins: [CGFloat] = Array(repeating: 0.0, count: 15)
        bins[7] = 50.0

        for step in 1...20 {
            bins = SurfaceHeightmap.convolve(bins: bins)
            XCTAssertEqual(bins.count, 15)

            // Test exact mirror symmetry: bins[i] == bins[14 - i]
            for i in 0..<7 {
                XCTAssertEqual(
                    bins[i],
                    bins[14 - i],
                    accuracy: 1e-12,
                    "Step \(step): Asymmetry detected between bin \(i) and bin \(14 - i)! Rightward drift violation."
                )
            }
        }
    }

    func testAngleOfRepose_strictSymmetryOnImpulseEvenLength() {
        // Twin central impulses on an even-length array (e.g. 16 bins, center = 7, 8)
        var bins: [CGFloat] = Array(repeating: 0.0, count: 16)
        bins[7] = 30.0
        bins[8] = 30.0

        for step in 1...20 {
            bins = SurfaceHeightmap.convolve(bins: bins)
            XCTAssertEqual(bins.count, 16)

            for i in 0..<8 {
                XCTAssertEqual(
                    bins[i],
                    bins[15 - i],
                    accuracy: 1e-12,
                    "Step \(step): Even impulse asymmetry between bin \(i) and bin \(15 - i)!"
                )
            }
        }
    }

    func testAngleOfRepose_strictSymmetryOnPlateauStepFunction() {
        // Step function / plateau in center
        var bins: [CGFloat] = Array(repeating: 0.0, count: 21)
        for i in 6...14 {
            bins[i] = 20.0
        }

        for step in 1...30 {
            bins = SurfaceHeightmap.convolve(bins: bins)
            for i in 0..<10 {
                XCTAssertEqual(
                    bins[i],
                    bins[20 - i],
                    accuracy: 1e-12,
                    "Step \(step): Plateau asymmetry between bin \(i) and bin \(20 - i)!"
                )
            }
        }
    }

    func testAngleOfRepose_preservesMonotonicityOnGradient() {
        // Monotonic ramp: [0, 5, 10, 15, 20, 25, 30, 35, 40]
        var bins: [CGFloat] = (0..<9).map { CGFloat($0 * 5) }

        for _ in 1...10 {
            bins = SurfaceHeightmap.convolve(bins: bins)
            for i in 0..<(bins.count - 1) {
                XCTAssertLessThanOrEqual(
                    bins[i],
                    bins[i + 1] + 1e-9,
                    "Smoothing of monotonic slope must remain monotonic"
                )
            }
        }
    }

    func testAngleOfRepose_clampingToMaxCapDuringConvolution() {
        let maxCap: CGFloat = 22.0
        let overflowBins: [CGFloat] = [25.0, 30.0, 28.0, 29.0, 35.0]
        let smoothed = SurfaceHeightmap.convolve(bins: overflowBins, maxCap: maxCap)

        for (i, val) in smoothed.enumerated() {
            XCTAssertLessThanOrEqual(val, maxCap + 1e-9, "Convolve must enforce maxCap at index \(i)")
        }
    }

    // MARK: - Feature 14: Window Movement Re-anchoring & Delta Tracking

    func testWindowMovementReanchoring_allDirectionalDeltas() {
        let testVectors: [CGPoint] = [
            CGPoint(x: 50, y: 30),    // Positive diagonal (Up-Right)
            CGPoint(x: -80, y: -45),  // Negative diagonal (Down-Left)
            CGPoint(x: 100, y: -60),  // Positive X, Negative Y
            CGPoint(x: -120, y: 75),  // Negative X, Positive Y
            CGPoint(x: 0, y: 0),      // Zero delta (stationary)
            CGPoint(x: 1920, y: -1080) // Cross-display large snap
        ]

        var currentAnchor = CGPoint(x: 300, y: 400)
        var map = SurfaceHeightmap(surfaceID: 77, width: 500, anchorPosition: currentAnchor)
        map.bins = Array(repeating: 18.0, count: 50)

        for delta in testVectors {
            let nextAnchor = CGPoint(x: currentAnchor.x + delta.x, y: currentAnchor.y + delta.y)
            let resultDelta = map.reanchor(newAnchor: nextAnchor)

            XCTAssertEqual(resultDelta.dx, delta.x, accuracy: 0.001)
            XCTAssertEqual(resultDelta.dy, delta.y, accuracy: 0.001)
            XCTAssertEqual(map.anchorPosition, nextAnchor)

            // Invariant: accumulated snow depth MUST NEVER be modified or reset by reanchoring
            XCTAssertEqual(map.averageDepth, 18.0, accuracy: 0.001)
            XCTAssertEqual(map.bins.count, 50)

            currentAnchor = nextAnchor
        }
    }

    @MainActor
    func testWindowMovementReanchoring_sceneSnowbankAndFairyLightsTracking() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        let view = SKView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        scene.didMove(to: view)
        scene.config.isEnabled = true
        scene.config.intensity = .blizzard
        scene.config.fairyLightsEnabled = true

        let mockDetector = MockWindowSurfaceDetector()
        scene.surfaceDetector = mockDetector

        // Initial window placement
        let initialSurface = CollisionSurface(
            id: 200,
            frame: CGRect(x: 200, y: 300, width: 600, height: 400),
            topEdgeY: 700,
            minX: 200,
            maxX: 800,
            isDock: false
        )
        mockDetector.surfacesToReturn = [initialSurface]
        scene.updateSurfaces()

        // Accumulate snow through simulation update loop
        for t in 1...20 {
            scene.update(Double(t) * 0.1)
        }
        guard let mapBeforeMove = scene.heightmaps[200] else {
            XCTFail("Heightmap for surface 200 must exist")
            return
        }
        let depthBeforeMove = mapBeforeMove.averageDepth
        XCTAssertGreaterThan(depthBeforeMove, 0.0, "Snow must accumulate before move")

        // Move window by dx = +150, dy = -80
        let movedSurface = CollisionSurface(
            id: 200,
            frame: CGRect(x: 350, y: 220, width: 600, height: 400),
            topEdgeY: 620,
            minX: 350,
            maxX: 950,
            isDock: false
        )
        mockDetector.surfacesToReturn = [movedSurface]
        scene.updateSurfaces()

        // Check heightmap anchor updated
        guard let updatedMap = scene.heightmaps[200] else {
            XCTFail("Heightmap for surface 200 must exist")
            return
        }
        XCTAssertEqual(updatedMap.anchorPosition, CGPoint(x: 350, y: 620))
        XCTAssertEqual(updatedMap.averageDepth, depthBeforeMove, accuracy: 0.001, "Snow depth must survive movement")
    }

    // MARK: - Feature 15: Surface Accumulation Caps & Boundaries

    func testSurfaceCaps_multiTierThresholds() {
        let screenHeight: CGFloat = 1080.0

        // Window surface cap: 22pt
        let windowSurface = CollisionSurface(id: 10, frame: .zero, topEdgeY: 500, minX: 100, maxX: 700, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: windowSurface, screenHeight: screenHeight), 22.0)

        // Dock surface cap: 30pt
        let dockSurface = CollisionSurface(id: 20, frame: .zero, topEdgeY: 80, minX: 0, maxX: 1920, isDock: true)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: dockSurface, screenHeight: screenHeight), 30.0)

        // Bottom display shelf (id: 0) cap: 50pt
        let bottomSurface = CollisionSurface(id: 0, frame: .zero, topEdgeY: 0, minX: 0, maxX: 1920, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: bottomSurface, screenHeight: screenHeight), 50.0)
    }

    func testSurfaceCaps_ceilingBoundaryClamping() {
        let screenHeight: CGFloat = 1080.0

        // 1. Margin = 15pt (< 22pt base cap) -> clamped to 15pt
        let highLedge = CollisionSurface(id: 11, frame: .zero, topEdgeY: 1065, minX: 100, maxX: 700, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: highLedge, screenHeight: screenHeight), 15.0)

        // 2. Exactly at top edge (1080) -> margin = 0pt
        let flushLedge = CollisionSurface(id: 12, frame: .zero, topEdgeY: 1080, minX: 100, maxX: 700, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: flushLedge, screenHeight: screenHeight), 0.0)

        // 3. Above top edge (> 1080) -> margin clamped to 0pt (never negative)
        let aboveLedge = CollisionSurface(id: 13, frame: .zero, topEdgeY: 1150, minX: 100, maxX: 700, isDock: false)
        XCTAssertEqual(FlakeScene.calculateMaxCap(for: aboveLedge, screenHeight: screenHeight), 0.0)
    }

    func testSurfaceCaps_accumulationStrictBoundStress() {
        // Stress test: 500 accumulation steps with large rate and wind drift
        var map = SurfaceHeightmap(surfaceID: 99, width: 400) // 40 bins
        let maxCap: CGFloat = 22.0

        for _ in 0..<500 {
            map.accumulate(
                rate: 5.0,
                maxCap: maxCap,
                windAngleDegrees: Double.random(in: 0...360),
                windSpeed: Double.random(in: 0...3)
            )
            map.smoothAngleOfRepose(maxCap: maxCap)

            for (binIndex, depth) in map.bins.enumerated() {
                XCTAssertLessThanOrEqual(
                    depth,
                    maxCap,
                    "Bin \(binIndex) exceeded maxCap \(maxCap) with depth \(depth)"
                )
            }
        }

        // At saturation, all bins should be at maxCap
        XCTAssertEqual(map.maxDepth, maxCap, accuracy: 0.001)
    }

    // MARK: - Integration: Interactive Clearing & Automated Snowplow

    @MainActor
    func testInteractiveClearing_mittenClearsWithinRadiusWithoutNegativeDepths() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        let mockDetector = MockWindowSurfaceDetector()
        let surface = CollisionSurface(id: 42, frame: CGRect(x: 100, y: 400, width: 400, height: 300), topEdgeY: 700, minX: 100, maxX: 500)
        mockDetector.surfacesToReturn = [surface]
        scene.surfaceDetector = mockDetector
        scene.config.isEnabled = true
        scene.config.intensity = .blizzard
        scene.updateSurfaces()

        // Accumulate snow
        for t in 1...30 {
            scene.update(Double(t) * 0.1)
        }

        guard let initialMap = scene.heightmaps[42] else {
            XCTFail("Heightmap must exist")
            return
        }
        let centerBin = initialMap.bins.count / 2
        let initialCenterDepth = initialMap.bins[centerBin]
        XCTAssertGreaterThan(initialCenterDepth, 0.0)

        // Clear at center of window ledge (x = 300, y = 700) with radius 45pt
        scene.clearSnowAtPoint(CGPoint(x: 300, y: 700), radius: 45)

        guard let clearedMap = scene.heightmaps[42] else {
            XCTFail("Heightmap must exist")
            return
        }
        // Center bins should have decreased
        XCTAssertLessThan(clearedMap.bins[centerBin], initialCenterDepth)

        // Multiple clears must not produce negative depths
        for _ in 0..<20 {
            scene.clearSnowAtPoint(CGPoint(x: 300, y: 700), radius: 45)
        }
        guard let fullyClearedMap = scene.heightmaps[42] else { return }
        for (idx, depth) in fullyClearedMap.bins.enumerated() {
            XCTAssertGreaterThanOrEqual(depth, 0.0, "Bin \(idx) cannot have negative depth")
        }
    }

    @MainActor
    func testSnowplow_triggerThreshold() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        let mockDetector = MockWindowSurfaceDetector()
        let bottomShelf = CollisionSurface(id: 0, frame: .zero, topEdgeY: 0, minX: 0, maxX: 1920)
        mockDetector.surfacesToReturn = [bottomShelf]
        scene.surfaceDetector = mockDetector
        scene.config.isEnabled = true
        scene.config.snowplowEnabled = true
        scene.updateSurfaces()

        // Trigger snowplow sweep
        XCTAssertFalse(scene.isSnowplowActive)
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive, "Snowplow sweep must be active when triggered")
    }
    // MARK: - Advanced Stress & Adversarial Edge Cases

    func testWindTrigonometry_periodicAndNegativeAngles() {
        let baseGravity: CGFloat = 120.0
        let speed: Double = 1.0 // 200 px/s²

        // Periodic wraparound: 450° == 90°
        let (ax450, ay450) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 450, windSpeed: speed, baseGravity: baseGravity)
        let (ax90, ay90) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(ax450, ax90, accuracy: 0.001)
        XCTAssertEqual(ay450, ay90, accuracy: 0.001)

        // Negative angle: -90° == 270° (Updraft)
        let (axNeg90, ayNeg90) = FlakeScene.calculateWindAcceleration(windAngleDegrees: -90, windSpeed: speed, baseGravity: baseGravity)
        let (ax270, ay270) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(axNeg90, ax270, accuracy: 0.001)
        XCTAssertEqual(ayNeg90, ay270, accuracy: 0.001)

        // Negative angle: -180° == 180° (West)
        let (axNeg180, ayNeg180) = FlakeScene.calculateWindAcceleration(windAngleDegrees: -180, windSpeed: speed, baseGravity: baseGravity)
        let (ax180, ay180) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 180, windSpeed: speed, baseGravity: baseGravity)
        XCTAssertEqual(axNeg180, ax180, accuracy: 0.001)
        XCTAssertEqual(ayNeg180, ay180, accuracy: 0.001)
    }

    func testWindTrigonometry_updraftSuspensionAndReversal() {
        let baseGravity: CGFloat = 120.0

        // Sub-critical updraft: windSpeed = 0.5 (100 px/s² < 120 px/s²) -> still falling slowly
        let (_, aySub) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270, windSpeed: 0.5, baseGravity: baseGravity)
        XCTAssertEqual(aySub, -20.0, accuracy: 0.001, "Sub-critical updraft must reduce downward acceleration to -20")

        // Critical equilibrium updraft: windSpeed = 0.6 (120 px/s² == 120 px/s²) -> zero net gravity (floating)
        let (_, ayCrit) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270, windSpeed: 0.6, baseGravity: baseGravity)
        XCTAssertEqual(ayCrit, 0.0, accuracy: 0.001, "Equilibrium updraft must yield exactly 0 net vertical acceleration")

        // Super-critical updraft: windSpeed = 2.0 (400 px/s² > 120 px/s²) -> rising into sky (+Y)
        let (_, aySuper) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270, windSpeed: 2.0, baseGravity: baseGravity)
        XCTAssertEqual(aySuper, 280.0, accuracy: 0.001, "Super-critical updraft must lift snow upward (+280 px/s²)")
    }

    func testAngleOfRepose_uniformFlatSurfaceStationaryState() {
        // A flat, uniform snowbank must be a fixed point / stationary state of the convolution
        let uniformBins: [CGFloat] = Array(repeating: 15.0, count: 20)
        let smoothed = SurfaceHeightmap.convolve(bins: uniformBins)

        for (i, val) in smoothed.enumerated() {
            XCTAssertEqual(val, 15.0, accuracy: 1e-12, "Flat uniform surface must be invariant under convolution at bin \(i)")
        }
    }

    func testAngleOfRepose_allZeroSurfaceStationaryState() {
        let zeroBins: [CGFloat] = Array(repeating: 0.0, count: 30)
        let smoothed = SurfaceHeightmap.convolve(bins: zeroBins)

        for (i, val) in smoothed.enumerated() {
            XCTAssertEqual(val, 0.0, accuracy: 1e-12, "Zero surface must remain 0 at bin \(i)")
        }
    }

    func testAngleOfRepose_largeScalePerformance() {
        // 500 bins (5000pt wide surface, e.g. multi-display panorama)
        let largeBins: [CGFloat] = (0..<500).map { CGFloat($0 % 25) }
        let startTime = CFAbsoluteTimeGetCurrent()

        var current = largeBins
        for _ in 0..<100 {
            current = SurfaceHeightmap.convolve(bins: current)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(elapsed, 0.5, "100 iterations of 500-bin convolution should execute in < 500ms")
    }

    func testHeightmap_shrinkThenExpandBinContinuity() {
        var map = SurfaceHeightmap(surfaceID: 88, width: 40) // 4 bins
        map.bins = [10.0, 20.0, 30.0, 40.0]

        // Shrink to 20pt (2 bins)
        map.resize(to: 20)
        XCTAssertEqual(map.bins.count, 2)
        XCTAssertEqual(map.bins, [10.0, 20.0])

        // Expand to 60pt (6 bins)
        map.resize(to: 60)
        XCTAssertEqual(map.bins.count, 6)
        XCTAssertEqual(map.bins[0], 10.0)
        XCTAssertEqual(map.bins[1], 20.0)
        XCTAssertEqual(map.bins[2], 0.0)
        XCTAssertEqual(map.bins[3], 0.0)
        XCTAssertEqual(map.bins[4], 0.0)
        XCTAssertEqual(map.bins[5], 0.0)
    }

    @MainActor
    func testClosedWindowSurfaceLifecycleCleanup() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        let mockDetector = MockWindowSurfaceDetector()
        scene.surfaceDetector = mockDetector
        scene.config.isEnabled = true

        let winSurface = CollisionSurface(id: 777, frame: CGRect(x: 200, y: 200, width: 400, height: 300), topEdgeY: 500, minX: 200, maxX: 600)
        mockDetector.surfacesToReturn = [winSurface]
        scene.updateSurfaces()

        XCTAssertNotNil(scene.heightmaps[777], "Heightmap must be created for open window")

        // Window closes
        mockDetector.surfacesToReturn = []
        scene.updateSurfaces()

        XCTAssertNil(scene.heightmaps[777], "Heightmap must be purged when window closes")

        // New window opens with same ID: must start with zero depth
        mockDetector.surfacesToReturn = [winSurface]
        scene.updateSurfaces()
        XCTAssertNotNil(scene.heightmaps[777])
        XCTAssertEqual(scene.heightmaps[777]?.averageDepth, 0.0, "New window must start fresh with 0 depth")
    }
}

private extension CGFloat {
    var cosValue: CGFloat {
        Darwin.cos(self)
    }
}
