import XCTest
@testable import WallpaperCore

final class ChallengerM1Tests: XCTestCase {

    // MARK: - 1. Window Occlusion Culling Adversarial Scenarios (Feature 6)

    func testOcclusion_pillarPunchingHole_splitLedgeWidestSegment() {
        // Candidate Window: Quartz (x: 100, y: 300, width: 600, height: 300) -> Cocoa top = 780, X in [100, 700]
        // Pillar Occluder in front: Quartz (x: 300, y: 200, width: 140, height: 400) -> Cocoa top = 880, bottom = 480, X in [300, 440]
        // Pillar has width 140 >= 120 (valid window).
        // Pillar covers Y=780 across X in [300, 440], splitting [100, 700] into [100, 300] (width 200) and [440, 700] (width 260).
        let pillar = WindowInfo(windowNumber: 1, ownerName: "PillarApp", bounds: CGRect(x: 300, y: 200, width: 140, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let candidate = WindowInfo(windowNumber: 2, ownerName: "CandidateApp", bounds: CGRect(x: 100, y: 300, width: 600, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [pillar, candidate]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        // Pillar should be retained with full width 140
        guard let pillarSurface = surfaces.first(where: { $0.id == 1 }) else {
            XCTFail("Pillar window must be present")
            return
        }
        XCTAssertEqual(pillarSurface.minX, 300)
        XCTAssertEqual(pillarSurface.maxX, 440)
        XCTAssertEqual(pillarSurface.width, 140)

        // Candidate should survive with widest segment [440, 700] (width 260)
        guard let candidateSurface = surfaces.first(where: { $0.id == 2 }) else {
            XCTFail("Candidate window must survive hole punch")
            return
        }
        XCTAssertEqual(candidateSurface.minX, 440)
        XCTAssertEqual(candidateSurface.maxX, 700)
        XCTAssertEqual(candidateSurface.width, 260)
    }

    func testOcclusion_pillarLeavingSub40Fragment_filtersSmallFragment() {
        // Candidate: X in [100, 500] (width 400).
        // Pillar covers X in [120, 300] (width 180 >= 120).
        // Left fragment: [100, 120] (width 20 < 40pt) -> MUST BE FILTERED OUT.
        // Right fragment: [300, 500] (width 200 >= 40pt) -> MUST BE RETAINED.
        let pillar = WindowInfo(windowNumber: 1, ownerName: "Pillar", bounds: CGRect(x: 120, y: 200, width: 180, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let candidate = WindowInfo(windowNumber: 2, ownerName: "Candidate", bounds: CGRect(x: 100, y: 300, width: 400, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [pillar, candidate]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        guard let candidateSurface = surfaces.first(where: { $0.id == 2 }) else {
            XCTFail("Candidate surface should survive with right segment")
            return
        }
        XCTAssertEqual(candidateSurface.minX, 300)
        XCTAssertEqual(candidateSurface.maxX, 500)
        XCTAssertEqual(candidateSurface.width, 200)
    }

    func testOcclusion_pillarLeavingAllSub40Fragments_entireWindowCulled() {
        // Candidate: bounds width 180, height 100 at X in [100, 280] (>= 120x80).
        // Pillar in front: X in [130, 250] (width 120 >= 120).
        // Left fragment: [100, 130] (width 30 < 40pt) -> culled.
        // Right fragment: [250, 280] (width 30 < 40pt) -> culled.
        // No segment >= 40pt remains -> Candidate window MUST BE CULLED ENTIRELY.
        let pillar = WindowInfo(windowNumber: 1, ownerName: "WidePillar", bounds: CGRect(x: 130, y: 200, width: 120, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let candidate = WindowInfo(windowNumber: 2, ownerName: "Candidate", bounds: CGRect(x: 100, y: 300, width: 180, height: 100), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [pillar, candidate]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 1 }), "Pillar must exist")
        XCTAssertFalse(surfaces.contains(where: { $0.id == 2 }), "Candidate window with all sub-40pt fragments must be culled")
    }

    func testOcclusion_multiplePillars_swissCheesePattern() {
        // Candidate: X in [100, 1100] (width 1000).
        // Pillar 1: [250, 370] (width 120)
        // Pillar 2: [550, 680] (width 130)
        // Pillar 3: [850, 970] (width 120)
        // Surviving fragments:
        // [100, 250] (width 150)
        // [370, 550] (width 180) -> WIDEST
        // [680, 850] (width 170)
        // [970, 1100] (width 130)
        let p1 = WindowInfo(windowNumber: 1, ownerName: "P1", bounds: CGRect(x: 250, y: 200, width: 120, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let p2 = WindowInfo(windowNumber: 2, ownerName: "P2", bounds: CGRect(x: 550, y: 200, width: 130, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let p3 = WindowInfo(windowNumber: 3, ownerName: "P3", bounds: CGRect(x: 850, y: 200, width: 120, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let candidate = WindowInfo(windowNumber: 4, ownerName: "Candidate", bounds: CGRect(x: 100, y: 300, width: 1000, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [p1, p2, p3, candidate]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        guard let candidateSurface = surfaces.first(where: { $0.id == 4 }) else {
            XCTFail("Candidate window must survive multiple pillars")
            return
        }
        XCTAssertEqual(candidateSurface.minX, 370)
        XCTAssertEqual(candidateSurface.maxX, 550)
        XCTAssertEqual(candidateSurface.width, 180, "Widest surviving segment of multi-pillar punch must be width 180")
    }

    func testOcclusion_cascadingThreeWindowsFrontToBack() {
        // W1 (z=0, front): Quartz (100, 180, 300, 400) -> Cocoa top = 900, bottom = 500, X in [100, 400]
        // W2 (z=1, middle): Quartz (300, 280, 300, 400) -> Cocoa top = 800, bottom = 400, X in [300, 600]
        //   - W1 occludes W2's ledge (y=800) for X in [300, 400]. Surviving W2: [400, 600] (width 200).
        // W3 (z=2, back): Quartz (200, 380, 500, 400) -> Cocoa top = 700, bottom = 300, X in [200, 700]
        //   - W1 occludes W3's ledge (y=700) for X in [200, 400]
        //   - W2 occludes W3's ledge (y=700) for X in [400, 600]
        //   - Surviving W3: [600, 700] (width 100 >= 40)
        let w1 = WindowInfo(windowNumber: 10, ownerName: "Front", bounds: CGRect(x: 100, y: 180, width: 300, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let w2 = WindowInfo(windowNumber: 20, ownerName: "Mid", bounds: CGRect(x: 300, y: 280, width: 300, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let w3 = WindowInfo(windowNumber: 30, ownerName: "Back", bounds: CGRect(x: 200, y: 380, width: 500, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [w1, w2, w3]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        let s1 = surfaces.first(where: { $0.id == 10 })
        XCTAssertNotNil(s1)
        XCTAssertEqual(s1?.minX, 100)
        XCTAssertEqual(s1?.maxX, 400)

        let s2 = surfaces.first(where: { $0.id == 20 })
        XCTAssertNotNil(s2)
        XCTAssertEqual(s2?.minX, 400)
        XCTAssertEqual(s2?.maxX, 600)

        let s3 = surfaces.first(where: { $0.id == 30 })
        XCTAssertNotNil(s3)
        XCTAssertEqual(s3?.minX, 600)
        XCTAssertEqual(s3?.maxX, 700)
        XCTAssertEqual(s3?.width, 100)
    }

    func testOcclusion_culledWindowBodyStillOccludesSubsequentWindow() {
        // W1 (z=0, front): Quartz (100, 100, 500, 300) -> Cocoa top = 980, bottom = 680, X in [100, 600]
        // W2 (z=1, middle): Quartz (150, 150, 400, 600) -> Cocoa top = 930, bottom = 330, X in [150, 550]
        //   - W1 completely covers W2's top edge (y=930 is inside [680, 980] and [150, 550] is inside [100, 600]).
        //   - W2's top ledge is CULLED (surviving intervals = empty).
        //   - BUT W2's body extends down to Cocoa y=330.
        // W3 (z=2, back): Quartz (150, 500, 400, 400) -> Cocoa top = 580, bottom = 180, X in [150, 550]
        //   - W1 does NOT cover y=580 (W1 ends at y=680).
        //   - BUT W2's body covers y=580 (W2 spans [330, 930]).
        //   - Therefore, W3's top ledge at y=580 MUST be occluded by W2!
        let w1 = WindowInfo(windowNumber: 1, ownerName: "W1", bounds: CGRect(x: 100, y: 100, width: 500, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let w2 = WindowInfo(windowNumber: 2, ownerName: "W2", bounds: CGRect(x: 150, y: 150, width: 400, height: 600), layer: 0, alpha: 1.0, isOnScreen: true)
        let w3 = WindowInfo(windowNumber: 3, ownerName: "W3", bounds: CGRect(x: 150, y: 500, width: 400, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [w1, w2, w3]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 1 }), "W1 must exist")
        XCTAssertFalse(surfaces.contains(where: { $0.id == 2 }), "W2's top edge must be culled")
        XCTAssertFalse(surfaces.contains(where: { $0.id == 3 }), "W3 must be occluded by W2's surviving body")
    }

    func testOcclusion_verticalToleranceBoundaries() {
        // Occluder: Quartz (100, 280, 500, 400) -> Cocoa top = 800, bottom = 400, X in [100, 600]
        let occluder = WindowInfo(windowNumber: 1, ownerName: "Occluder", bounds: CGRect(x: 100, y: 280, width: 500, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)

        // Case A: Window topEdge at 800.5 (Quartz y = 1080 - 800.5 = 279.5) -> within +0.5 tolerance -> OCCLUDED
        let wA = WindowInfo(windowNumber: 2, ownerName: "WA", bounds: CGRect(x: 150, y: 279.5, width: 300, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let detA = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [occluder, wA]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let surfsA = detA.detectSurfaces(for: screen, primaryScreenHeight: 1080)
        XCTAssertFalse(surfsA.contains(where: { $0.id == 2 }), "Window at topEdge 800.5 must be occluded within tolerance")

        // Case B: Window topEdge at 800.6 (Quartz y = 1080 - 800.6 = 279.4) -> outside +0.5 tolerance -> NOT OCCLUDED
        let wB = WindowInfo(windowNumber: 3, ownerName: "WB", bounds: CGRect(x: 150, y: 279.4, width: 300, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let detB = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [occluder, wB]))
        let surfsB = detB.detectSurfaces(for: screen, primaryScreenHeight: 1080)
        XCTAssertTrue(surfsB.contains(where: { $0.id == 3 }), "Window at topEdge 800.6 must not be occluded")

        // Case C: Window topEdge at 399.5 (Quartz y = 1080 - 399.5 = 680.5) -> within -0.5 tolerance -> OCCLUDED
        let wC = WindowInfo(windowNumber: 4, ownerName: "WC", bounds: CGRect(x: 150, y: 680.5, width: 300, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let detC = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [occluder, wC]))
        let surfsC = detC.detectSurfaces(for: screen, primaryScreenHeight: 1080)
        XCTAssertFalse(surfsC.contains(where: { $0.id == 4 }), "Window at topEdge 399.5 must be occluded within tolerance")

        // Case D: Window topEdge at 399.4 (Quartz y = 1080 - 399.4 = 680.6) -> outside -0.5 tolerance -> NOT OCCLUDED
        let wD = WindowInfo(windowNumber: 5, ownerName: "WD", bounds: CGRect(x: 150, y: 680.6, width: 300, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let detD = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [occluder, wD]))
        let surfsD = detD.detectSurfaces(for: screen, primaryScreenHeight: 1080)
        XCTAssertTrue(surfsD.contains(where: { $0.id == 5 }), "Window at topEdge 399.4 must not be occluded")
    }

    func testOcclusion_abuttingEdgesExactBoundaries() {
        // Candidate: X in [100, 300]
        // Occluder touches exact right boundary: X in [300, 500] (occMin == interval.upperBound)
        // Should NOT occlude candidate at all!
        let occluder = WindowInfo(windowNumber: 1, ownerName: "RightTouch", bounds: CGRect(x: 300, y: 200, width: 200, height: 400), layer: 0, alpha: 1.0, isOnScreen: true)
        let candidate = WindowInfo(windowNumber: 2, ownerName: "Candidate", bounds: CGRect(x: 100, y: 250, width: 200, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [occluder, candidate]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        guard let candSurf = surfaces.first(where: { $0.id == 2 }) else {
            XCTFail("Touching window must not be culled")
            return
        }
        XCTAssertEqual(candSurf.minX, 100)
        XCTAssertEqual(candSurf.maxX, 300)
        XCTAssertEqual(candSurf.width, 200)
    }

    // MARK: - 2. Coordinate Inversion Math Across Displays (Feature 3)

    func testCoordinateInversion_standardResolutions() {
        let testScreens: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("1080p FHD", 1920, 1080),
            ("1440p QHD", 2560, 1440),
            ("4K UHD", 3840, 2160),
            ("5K Studio Display", 5120, 2880),
            ("6K Pro Display XDR", 6016, 3384),
            ("Ultrawide 21:9", 3440, 1440),
            ("Super Ultrawide 32:9", 5120, 1440),
            ("Vertical Monitor 9:16", 1080, 1920),
            ("MacBook Air 13-inch", 1440, 900)
        ]

        for screen in testScreens {
            let winQuartzBounds = CGRect(x: 150, y: 100, width: 500, height: 400)
            let win = WindowInfo(windowNumber: 99, ownerName: "App", bounds: winQuartzBounds, layer: 0, alpha: 1.0, isOnScreen: true)
            let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))

            let screenRect = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
            var config = FlakeConfiguration()
            config.accumulateOnScreenBottom = false
            config.accumulateOnWindows = true

            let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: screenRect, primaryScreenHeight: screen.height, config: config)

            XCTAssertEqual(surfaces.count, 1, "Failed on resolution \(screen.name)")
            let surf = surfaces[0]

            // Cocoa top = refHeight - quartzY
            let expectedTop = screen.height - 100
            // Cocoa bottom = expectedTop - height = screen.height - 500
            let expectedBottom = expectedTop - 400

            XCTAssertEqual(surf.topEdgeY, expectedTop, "topEdgeY mismatch on \(screen.name)")
            XCTAssertEqual(surf.frame.minY, expectedBottom, "frame.minY mismatch on \(screen.name)")
            XCTAssertEqual(surf.frame.maxY, expectedTop, "frame.maxY mismatch on \(screen.name)")
            XCTAssertEqual(surf.minX, 150, "minX mismatch on \(screen.name)")
            XCTAssertEqual(surf.maxX, 650, "maxX mismatch on \(screen.name)")
            XCTAssertEqual(surf.width, 500, "width mismatch on \(screen.name)")
        }
    }

    func testCoordinateInversion_topEdgeAtScreenCeiling() {
        let win = WindowInfo(windowNumber: 1, ownerName: "Ceiling", bounds: CGRect(x: 200, y: 0, width: 400, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces[0].topEdgeY, 1080) // 1080 - 0 = 1080
        XCTAssertEqual(surfaces[0].frame.minY, 780) // 1080 - 300 = 780
    }

    func testCoordinateInversion_bottomEdgeAtScreenFloor() {
        // Window bottom touches y=0 in Cocoa -> Quartz y = 1080 - 300 = 780
        let win = WindowInfo(windowNumber: 1, ownerName: "Floor", bounds: CGRect(x: 200, y: 780, width: 400, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces[0].topEdgeY, 300) // 1080 - 780 = 300
        XCTAssertEqual(surfaces[0].frame.minY, 0) // 300 - 300 = 0
    }

    func testCoordinateInversion_horizontalEdgeClamping() {
        // Window extends beyond left edge: minX = -100, width = 500 -> maxX = 400.
        // Clamped: minX = 0, maxX = 400, width = 400.
        let winLeft = WindowInfo(windowNumber: 1, ownerName: "LeftOverlap", bounds: CGRect(x: -100, y: 200, width: 500, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        // Window extends beyond right edge of 1920 display: minX = 1700, width = 500 -> maxX = 2200.
        // Clamped: minX = 1700, maxX = 1920, width = 220.
        let winRight = WindowInfo(windowNumber: 2, ownerName: "RightOverlap", bounds: CGRect(x: 1700, y: 200, width: 500, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        // Window extends beyond right edge with surviving segment < 40: minX = 1900, width = 100 -> maxX = 2000.
        // Clamped: minX = 1900, maxX = 1920, width = 20 (< 40) -> CULLED!
        let winTooSmall = WindowInfo(windowNumber: 3, ownerName: "TooSmallClamped", bounds: CGRect(x: 1900, y: 200, width: 120, height: 100), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [winLeft, winRight, winTooSmall]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(screenRect: screen, visibleFrame: screen, primaryScreenHeight: 1080, config: config)

        let sLeft = surfaces.first(where: { $0.id == 1 })
        XCTAssertNotNil(sLeft)
        XCTAssertEqual(sLeft?.minX, 0)
        XCTAssertEqual(sLeft?.maxX, 400)
        XCTAssertEqual(sLeft?.width, 400)

        let sRight = surfaces.first(where: { $0.id == 2 })
        XCTAssertNotNil(sRight)
        XCTAssertEqual(sRight?.minX, 1700)
        XCTAssertEqual(sRight?.maxX, 1920)
        XCTAssertEqual(sRight?.width, 220)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 3 }), "Clamped window with width < 40 must be culled")
    }

    // MARK: - 3. Dock Surface Extraction & Fallback Geometry (Feature 4)

    func testDockExtraction_visibleFrameBottomInsetMath() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        // 96pt bottom Dock inset: visibleFrame minY = 96, height = 1344
        let visibleFrame = CGRect(x: 0, y: 96, width: 2560, height: 1344)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = true

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame, primaryScreenHeight: 1440, config: config)

        XCTAssertEqual(surfaces.count, 1)
        let dock = surfaces[0]
        XCTAssertTrue(dock.isDock)
        XCTAssertEqual(dock.id, CGWindowID.max - 10)
        XCTAssertEqual(dock.topEdgeY, 96)
        XCTAssertEqual(dock.minX, 0)
        XCTAssertEqual(dock.maxX, 2560)
        XCTAssertEqual(dock.width, 2560)
        XCTAssertEqual(dock.frame, CGRect(x: 0, y: 0, width: 2560, height: 96))
    }

    func testDockExtraction_insetThresholdBoundaries() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = true

        // Exactly 10pt inset -> NO dock (condition is > 10)
        let frame10 = CGRect(x: 0, y: 10, width: 1920, height: 1070)
        let surfs10 = detector.detectSurfaces(screenRect: screenRect, visibleFrame: frame10, primaryScreenHeight: 1080, config: config)
        XCTAssertTrue(surfs10.isEmpty, "Inset of exactly 10pt must not trigger Dock fallback")

        // 10.1pt inset -> Trigger Dock fallback
        let frame10Point1 = CGRect(x: 0, y: 10.1, width: 1920, height: 1069.9)
        let surfs10Point1 = detector.detectSurfaces(screenRect: screenRect, visibleFrame: frame10Point1, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfs10Point1.count, 1, "Inset > 10pt must trigger Dock fallback")
        XCTAssertTrue(surfs10Point1[0].isDock)

        // 0pt inset (Dock auto-hidden) -> NO dock
        let frame0 = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let surfs0 = detector.detectSurfaces(screenRect: screenRect, visibleFrame: frame0, primaryScreenHeight: 1080, config: config)
        XCTAssertTrue(surfs0.isEmpty, "0pt inset must not trigger Dock fallback")
    }

    func testDockExtraction_sideDockIgnored() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Left Dock: visibleFrame has minX = 75, minY = 0
        let visibleFrameLeft = CGRect(x: 75, y: 0, width: 1845, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = true

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrameLeft, primaryScreenHeight: 1080, config: config)
        XCTAssertTrue(surfaces.isEmpty, "Side Dock with bottom inset 0 must not produce bottom Dock surface")
    }

    func testDockExtraction_disabledInConfig() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = CGRect(x: 0, y: 85, width: 1920, height: 995)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = false // DISABLED

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame, primaryScreenHeight: 1080, config: config)
        XCTAssertTrue(surfaces.isEmpty, "Dock must not be extracted when accumulateOnDock is false")
    }

    // MARK: - 4. Zero-TCC Window Querying & Filtering Rules (Features 1 & 2)

    func testFiltering_layerFiltering() {
        let windows: [WindowInfo] = [
            WindowInfo(windowNumber: 1, ownerName: "Normal", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 2, ownerName: "Background", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: -1, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 3, ownerName: "Floating", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 3, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 4, ownerName: "DockLevel", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 20, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 5, ownerName: "MenuLevel", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 25, alpha: 1.0, isOnScreen: true)
        ]

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces[0].id, 1)
    }

    func testFiltering_alphaThresholdBoundary() {
        let windows: [WindowInfo] = [
            WindowInfo(windowNumber: 1, ownerName: "JustUnderAlpha", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, alpha: 0.05, isOnScreen: true),
            WindowInfo(windowNumber: 2, ownerName: "JustAboveAlpha", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, alpha: 0.051, isOnScreen: true)
        ]

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces[0].id, 2, "Window with alpha <= 0.05 must be filtered out, > 0.05 must be kept")
    }

    func testFiltering_minDimensionsBoundary() {
        let windows: [WindowInfo] = [
            WindowInfo(windowNumber: 1, ownerName: "Width119", bounds: CGRect(x: 100, y: 100, width: 119, height: 100), layer: 0, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 2, ownerName: "Height79", bounds: CGRect(x: 100, y: 100, width: 200, height: 79), layer: 0, alpha: 1.0, isOnScreen: true),
            WindowInfo(windowNumber: 3, ownerName: "Exact120x80", bounds: CGRect(x: 100, y: 100, width: 120, height: 80), layer: 0, alpha: 1.0, isOnScreen: true)
        ]

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces[0].id, 3, "Window with exact minimum dimensions 120x80 must be kept; below must be filtered out")
    }

    func testFiltering_selfPIDExclusion() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let win = WindowInfo(windowNumber: 88, ownerPID: myPID, ownerName: "LiveApp", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0, alpha: 1.0, isOnScreen: true)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnWindows = true

        let surfaces = detector.detectSurfaces(for: screen, primaryScreenHeight: 1080, config: config)
        XCTAssertTrue(surfaces.isEmpty, "Own process PID windows must be excluded")
    }

    // MARK: - 5. Bottom Shelf Baseline Ledge (Feature 5)

    func testBottomShelf_baselineCoexistenceWithDock() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = CGRect(x: 0, y: 80, width: 1920, height: 1000)

        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = true
        config.accumulateOnDock = true
        config.accumulateOnWindows = false

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame, primaryScreenHeight: 1080, config: config)

        XCTAssertEqual(surfaces.count, 2)

        let shelf = surfaces.first(where: { $0.id == 0 })
        XCTAssertNotNil(shelf)
        XCTAssertEqual(shelf?.topEdgeY, 0)
        XCTAssertEqual(shelf?.minX, 0)
        XCTAssertEqual(shelf?.maxX, 1920)
        XCTAssertFalse(shelf?.isDock ?? true)

        let dock = surfaces.first(where: { $0.isDock })
        XCTAssertNotNil(dock)
        XCTAssertEqual(dock?.topEdgeY, 80)
        XCTAssertEqual(dock?.minX, 0)
        XCTAssertEqual(dock?.maxX, 1920)
    }
}
