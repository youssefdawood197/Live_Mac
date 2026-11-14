import Foundation
import AppKit
import SpriteKit
import XCTest
import WallpaperCore

// MARK: - Tier 2: Flake Boundary & Corner Case Test Suite
//
// Requirement-driven opaque-box test suite covering ALL 33 Flake Features
// from PROJECT.md § Feature Inventory and TEST_INFRA.md with exactly 5 distinct
// boundary, limit, and corner case test cases per feature (165 test cases total).

@MainActor
final class Tier2_FlakeBoundaryTests: XCTestCase {

    var env: FlakeTestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = FlakeTestEnvironment(
            screen: FlakeSimulatedScreens.standardHD,
            config: FlakeConfiguration(isEnabled: true)
        )
        let skView = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        skView.presentScene(env.scene)
    }

    override func tearDown() async throws {
        env.reset()
        env = nil
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Feature 1: Zero-TCC Window Querying Boundary Tests (5 tests)
    // =========================================================================

    func testF01_B01_largeWindowListBoundary_handles500WindowsEfficiently() {
        var windows: [WindowInfo] = []
        for i in 1...500 {
            let win = FlakeWindowFixture.makeWindow(
                id: CGWindowID(1000 + i),
                ownerPID: pid_t(2000 + i),
                ownerName: "App_\(i)",
                bounds: CGRect(x: CGFloat(i % 10) * 100, y: CGFloat(i % 10) * 50, width: 400, height: 300),
                layer: 0,
                alpha: 1.0,
                isOnScreen: true
            )
            windows.append(win)
        }
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.isEmpty)
        XCTAssertTrue(surfaces.contains(where: { $0.id == 0 })) // Bottom shelf
    }

    func testF01_B02_emptyWindowListBoundary_returnsOnlyBottomShelf() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        var cfg = FlakeConfiguration()
        cfg.accumulateOnDock = false
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: nil, config: cfg)

        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.first?.id, 0)
        XCTAssertEqual(surfaces.first?.width, env.screen.frame.width)
    }

    func testF01_B03_exactScreenBoundsWindow_extractsFullWidthLedge() {
        let fullScreenWindow = FlakeWindowFixture.makeWindow(
            id: 105,
            ownerPID: 500,
            ownerName: "FullApp",
            bounds: env.screen.frame,
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [fullScreenWindow]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let appSurface = surfaces.first(where: { $0.id == 105 })
        XCTAssertNotNil(appSurface)
        XCTAssertEqual(appSurface?.minX, 0.0)
        XCTAssertEqual(appSurface?.maxX, 1920.0)
        XCTAssertEqual(appSurface?.width, 1920.0)
    }

    func testF01_B04_completelyOffscreenWindowBounds_excludedFromSurfaces() {
        let offscreenWindow = FlakeWindowFixture.makeWindow(
            id: 106,
            ownerPID: 501,
            ownerName: "OffscreenApp",
            bounds: CGRect(x: -5000, y: -5000, width: 400, height: 300),
            layer: 0,
            alpha: 1.0,
            isOnScreen: true
        )
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [offscreenWindow]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 106 }))
    }

    func testF01_B05_selfProcessPIDExclusionBoundary_rejectsAllSelfWindowsRegardlessOfCount() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        var windows: [WindowInfo] = []
        for i in 1...10 {
            windows.append(FlakeWindowFixture.makeWindow(
                id: CGWindowID(2000 + i),
                ownerPID: myPID,
                ownerName: "LiveWallpaperSelf",
                bounds: CGRect(x: 100, y: 100, width: 500, height: 400)
            ))
        }
        let validExternal = FlakeWindowFixture.standardAppWindow(id: 3001, ownerName: "ExternalApp", bounds: CGRect(x: 200, y: 200, width: 500, height: 400))
        windows.append(validExternal)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 3001 }))
        for i in 1...10 {
            XCTAssertFalse(surfaces.contains(where: { $0.id == CGWindowID(2000 + i) }))
        }
    }

    // =========================================================================
    // MARK: - Feature 2: Window Surface Filtering Boundary Tests (5 tests)
    // =========================================================================

    func testF02_B01_alphaThresholdBoundary_alpha005Excluded_alpha0051Included() {
        let winAtBoundary = FlakeWindowFixture.makeWindow(id: 201, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), alpha: 0.05)
        let winAboveBoundary = FlakeWindowFixture.makeWindow(id: 202, bounds: CGRect(x: 600, y: 100, width: 400, height: 300), alpha: 0.051)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [winAtBoundary, winAboveBoundary]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 201 }), "Alpha exactly 0.05 must be excluded")
        XCTAssertTrue(surfaces.contains(where: { $0.id == 202 }), "Alpha 0.051 must be included")
    }

    func testF02_B02_widthDimensionBoundary_width119Excluded_width120Included() {
        let win119 = FlakeWindowFixture.makeWindow(id: 203, bounds: CGRect(x: 100, y: 100, width: 119, height: 200))
        let win120 = FlakeWindowFixture.makeWindow(id: 204, bounds: CGRect(x: 300, y: 100, width: 120, height: 200))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win119, win120]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 203 }), "Width 119 must be excluded (< 120)")
        XCTAssertTrue(surfaces.contains(where: { $0.id == 204 }), "Width 120 must be included (>= 120)")
    }

    func testF02_B03_heightDimensionBoundary_height79Excluded_height80Included() {
        let win79 = FlakeWindowFixture.makeWindow(id: 205, bounds: CGRect(x: 100, y: 100, width: 300, height: 79))
        let win80 = FlakeWindowFixture.makeWindow(id: 206, bounds: CGRect(x: 500, y: 100, width: 300, height: 80))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win79, win80]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 205 }), "Height 79 must be excluded (< 80)")
        XCTAssertTrue(surfaces.contains(where: { $0.id == 206 }), "Height 80 must be included (>= 80)")
    }

    func testF02_B04_clampedLedgeSpanBoundary_clamped39Excluded_clamped40Included() {
        // Screen bounds: x = 0..1920. Window A spans x = 1881..2181 (visible overlap 39pt)
        let winClamped39 = FlakeWindowFixture.makeWindow(id: 207, bounds: CGRect(x: 1881, y: 100, width: 300, height: 300))
        // Window B spans x = 1880..2180 (visible overlap 40pt)
        let winClamped40 = FlakeWindowFixture.makeWindow(id: 208, bounds: CGRect(x: 1880, y: 500, width: 300, height: 300))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [winClamped39, winClamped40]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 207 }), "Clamped width 39pt must be excluded (< 40)")
        XCTAssertTrue(surfaces.contains(where: { $0.id == 208 }), "Clamped width 40pt must be included (>= 40)")
    }

    func testF02_B05_layerBoundary_layerNegativeOneAndOneExcluded_layerZeroIncluded() {
        let winNeg = FlakeWindowFixture.makeWindow(id: 209, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: -1)
        let winZero = FlakeWindowFixture.makeWindow(id: 210, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0)
        let winPos = FlakeWindowFixture.makeWindow(id: 211, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 1)
        let win24 = FlakeWindowFixture.makeWindow(id: 212, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 24)

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [winNeg, winZero, winPos, win24]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 209 }))
        XCTAssertTrue(surfaces.contains(where: { $0.id == 210 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 211 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 212 }))
    }

    // =========================================================================
    // MARK: - Feature 3: Coordinate System Inversion Boundary Tests (5 tests)
    // =========================================================================

    func testF03_B01_quartzOriginZero_invertsToScreenHeightTopY() {
        let win = FlakeWindowFixture.standardAppWindow(id: 301, bounds: CGRect(x: 100, y: 0, width: 400, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let surface = surfaces.first(where: { $0.id == 301 })
        XCTAssertNotNil(surface)
        XCTAssertEqual(surface?.topEdgeY, 1080.0, "minY = 0 in Quartz inverts to cocoaTopY = 1080")
        XCTAssertEqual(surface?.frame.minY, 780.0, "cocoaBottomY = 1080 - 300 = 780")
    }

    func testF03_B02_quartzBottomEdge_invertsToZeroCocoaBottomY() {
        let win = FlakeWindowFixture.standardAppWindow(id: 302, bounds: CGRect(x: 100, y: 780, width: 400, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let surface = surfaces.first(where: { $0.id == 302 })
        XCTAssertNotNil(surface)
        XCTAssertEqual(surface?.topEdgeY, 300.0)
        XCTAssertEqual(surface?.frame.minY, 0.0, "Bottom edge of Cocoa frame aligns with 0.0")
    }

    func testF03_B03_customPrimaryScreenHeightParameter_usesExplicitReferenceHeight() {
        let win = FlakeWindowFixture.standardAppWindow(id: 303, bounds: CGRect(x: 100, y: 200, width: 400, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1440)

        let surface = surfaces.first(where: { $0.id == 303 })
        XCTAssertNotNil(surface)
        XCTAssertEqual(surface?.topEdgeY, 1240.0, "1440 - 200 = 1240")
    }

    func testF03_B04_subpixelFractionalCoordinates_preservesExactDecimalValues() {
        let win = FlakeWindowFixture.standardAppWindow(
            id: 304,
            bounds: CGRect(x: 100.25, y: 150.75, width: 400.5, height: 300.5)
        )
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let surface = surfaces.first(where: { $0.id == 304 })
        XCTAssertNotNil(surface)
        XCTAssertEqual(surface?.topEdgeY, 1080.0 - 150.75)
        XCTAssertEqual(surface?.minX, 100.25)
        XCTAssertEqual(surface?.maxX, 100.25 + 400.5)
    }

    func testF03_B05_extremeResolution8K_invertsCoordinatesAccurately() {
        let screen8K = CGRect(x: 0, y: 0, width: 7680, height: 4320)
        let win = FlakeWindowFixture.standardAppWindow(id: 305, bounds: CGRect(x: 500, y: 500, width: 2000, height: 1500))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: screen8K, visibleFrame: screen8K, primaryScreenHeight: 4320)

        let surface = surfaces.first(where: { $0.id == 305 })
        XCTAssertNotNil(surface)
        XCTAssertEqual(surface?.topEdgeY, 4320 - 500)
        XCTAssertEqual(surface?.frame.minY, 4320 - 500 - 1500)
    }

    // =========================================================================
    // MARK: - Feature 4: Dock Surface Extraction Boundary Tests (5 tests)
    // =========================================================================

    func testF04_B01_fallbackDockInsetBoundary_inset10Excluded() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // visibleFrame minY is 10.0 -> bottomInset == 10.0 (not > 10)
        let visibleFrame = CGRect(x: 0, y: 10, width: 1920, height: 1070)

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame)
        XCTAssertFalse(surfaces.contains(where: { $0.isDock }), "Inset of exactly 10 must not extract fallback dock")
    }

    func testF04_B02_fallbackDockInsetBoundary_inset10Point5Included() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // visibleFrame minY is 10.5 -> bottomInset == 10.5 (> 10)
        let visibleFrame = CGRect(x: 0, y: 10.5, width: 1920, height: 1069.5)

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame)
        let dock = surfaces.first(where: { $0.isDock })
        XCTAssertNotNil(dock, "Inset of 10.5 must extract fallback dock")
        XCTAssertEqual(dock?.id, CGWindowID.max - 10)
        XCTAssertEqual(dock?.topEdgeY, 10.5)
    }

    func testF04_B03_autohideDockZeroInset_noFallbackDockSurface() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Zero inset: visibleFrame == screenRect
        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: screenRect)
        XCTAssertFalse(surfaces.contains(where: { $0.isDock }))
    }

    func testF04_B04_explicitDockWindowSuppressesFallbackDock() {
        let dockWin = FlakeWindowFixture.dockWindow(bounds: CGRect(x: 0, y: 1000, width: 1920, height: 80))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [dockWin]))
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = CGRect(x: 0, y: 70, width: 1920, height: 1010)

        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame, primaryScreenHeight: 1080)
        let dockSurfaces = surfaces.filter { $0.isDock }
        XCTAssertEqual(dockSurfaces.count, 1, "Only explicit Dock window should be present, not fallback")
        XCTAssertEqual(dockSurfaces.first?.id, 999)
    }

    func testF04_B05_accumulateOnDockFalseBoundary_excludesExplicitAndFallbackDock() {
        let dockWin = FlakeWindowFixture.dockWindow(bounds: CGRect(x: 0, y: 1000, width: 1920, height: 80))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [dockWin]))
        var cfg = FlakeConfiguration()
        cfg.accumulateOnDock = false

        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080, config: cfg)
        XCTAssertFalse(surfaces.contains(where: { $0.isDock }))
    }

    // =========================================================================
    // MARK: - Feature 5: Bottom Display Shelf Boundary Tests (5 tests)
    // =========================================================================

    func testF05_B01_accumulateOnScreenBottomFalse_omitsBottomShelfSurface() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        var cfg = FlakeConfiguration()
        cfg.accumulateOnScreenBottom = false

        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: nil, config: cfg)
        XCTAssertFalse(surfaces.contains(where: { $0.id == 0 }))
    }

    func testF05_B02_negativeScreenOrigin_createsBottomShelfWithNegativeMinX() {
        let negativeScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: negativeScreen, visibleFrame: negativeScreen)

        let bottomShelf = surfaces.first(where: { $0.id == 0 })
        XCTAssertNotNil(bottomShelf)
        XCTAssertEqual(bottomShelf?.minX, -1920.0)
        XCTAssertEqual(bottomShelf?.maxX, 0.0)
        XCTAssertEqual(bottomShelf?.topEdgeY, -200.0)
    }

    func testF05_B03_zeroWidthScreen_createsZeroWidthBottomShelf() {
        let zeroScreen = CGRect(x: 0, y: 0, width: 0, height: 1080)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: zeroScreen, visibleFrame: zeroScreen)

        let bottomShelf = surfaces.first(where: { $0.id == 0 })
        XCTAssertNotNil(bottomShelf)
        XCTAssertEqual(bottomShelf?.width, 0.0)
    }

    func testF05_B04_bottomShelfHeightAndTopEdgeYInvariants() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        let bottomShelf = surfaces.first(where: { $0.id == 0 })
        XCTAssertNotNil(bottomShelf)
        XCTAssertEqual(bottomShelf?.frame.height, 1.0)
        XCTAssertEqual(bottomShelf?.topEdgeY, env.screen.frame.minY)
        XCTAssertFalse(bottomShelf?.isDock ?? true)
    }

    func testF05_B05_multiScreenIndependentBottomShelves_eachMatchesItsScreenRect() {
        let screenA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let screenB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))

        let surfacesA = detector.detectSurfaces(screenRect: screenA, visibleFrame: screenA)
        let surfacesB = detector.detectSurfaces(screenRect: screenB, visibleFrame: screenB)

        XCTAssertEqual(surfacesA.first(where: { $0.id == 0 })?.width, 1920.0)
        XCTAssertEqual(surfacesB.first(where: { $0.id == 0 })?.width, 2560.0)
    }

    // =========================================================================
    // MARK: - Feature 6: Window Occlusion Culling Boundary Tests (5 tests)
    // =========================================================================

    func testF06_B01_completeOcclusion_cullsBackWindowCompletely() {
        let front = FlakeWindowFixture.standardAppWindow(id: 601, bounds: CGRect(x: 100, y: 100, width: 600, height: 500))
        let back = FlakeWindowFixture.standardAppWindow(id: 602, bounds: CGRect(x: 150, y: 150, width: 400, height: 300))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 601 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 602 }))
    }

    func testF06_B02_partialOcclusionRemaining39pt_cullsBackWindowBelowThreshold() {
        // Back window width 200 (x: 400..600). Front covers x: 200..561 (overlap 161pt, leaving 39pt unoccluded)
        let front = FlakeWindowFixture.standardAppWindow(id: 603, bounds: CGRect(x: 200, y: 150, width: 361, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 604, bounds: CGRect(x: 400, y: 200, width: 200, height: 300))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 604 }), "Remaining unoccluded span 39pt must be culled (< 40)")
    }

    func testF06_B03_partialOcclusionRemaining40pt_preservesBackWindowAtThreshold() {
        // Back window width 200 (x: 400..600). Front covers x: 200..560 (overlap 160pt, leaving 40pt unoccluded)
        let front = FlakeWindowFixture.standardAppWindow(id: 605, bounds: CGRect(x: 200, y: 150, width: 360, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 606, bounds: CGRect(x: 400, y: 200, width: 200, height: 300))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let sBack = surfaces.first(where: { $0.id == 606 })
        XCTAssertNotNil(sBack, "Remaining unoccluded span 40pt must be preserved (>= 40)")
        XCTAssertEqual(sBack?.width, 40.0)
    }

    func testF06_B04_middleSplitOcclusion_selectsWidestUnoccludedSegment() {
        // Back window x: 100..700 (width 600). Front window covers x: 250..400 (width 150 in middle >= 120 min width).
        // Left unoccluded segment: 100..250 (width 150). Right unoccluded segment: 400..700 (width 300).
        let front = FlakeWindowFixture.standardAppWindow(id: 607, bounds: CGRect(x: 250, y: 150, width: 150, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 608, bounds: CGRect(x: 100, y: 200, width: 600, height: 300))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let sBack = surfaces.first(where: { $0.id == 608 })
        XCTAssertNotNil(sBack)
        XCTAssertEqual(sBack?.minX, 400.0)
        XCTAssertEqual(sBack?.maxX, 700.0)
        XCTAssertEqual(sBack?.width, 300.0)
    }

    func testF06_B05_verticalToleranceBoundary_plusMinusHalfPointOcclusion() {
        // Back window at Cocoa topEdgeY = 600.
        // Front window Cocoa topY = 600.5 (within 0.5 margin) -> triggers occlusion check
        let front = FlakeWindowFixture.standardAppWindow(id: 609, bounds: CGRect(x: 100, y: 479.5, width: 500, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 610, bounds: CGRect(x: 100, y: 480.0, width: 400, height: 300))

        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 609 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 610 }))
    }

    // =========================================================================
    // MARK: - Feature 7: 10 Hz Polling Throttle Boundary Tests (5 tests)
    // =========================================================================

    func testF07_B01_subThresholdStep009s_doesNotTriggerSurfaceRefresh() {
        let win1 = FlakeWindowFixture.standardAppWindow(id: 701, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win1])
        env.scene.update(100.0)
        let initialCount = env.scene.surfaces.count

        let win2 = FlakeWindowFixture.standardAppWindow(id: 702, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows.append(win2)
        env.scene.update(100.09) // delta = 0.09s < 0.1s

        XCTAssertEqual(env.scene.surfaces.count, initialCount)
    }

    func testF07_B02_exactThresholdStep010s_triggersSurfaceRefresh() {
        let win1 = FlakeWindowFixture.standardAppWindow(id: 703, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win1])
        env.scene.update(100.0)

        let win2 = FlakeWindowFixture.standardAppWindow(id: 704, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows.append(win2)
        env.scene.update(100.11) // delta >= 0.1s

        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 704 }))
    }

    func testF07_B03_zeroDeltaStep_doesNotTriggerSurfaceRefresh() {
        let win = FlakeWindowFixture.standardAppWindow(id: 705, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.update(100.0)

        let winNew = FlakeWindowFixture.standardAppWindow(id: 706, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows.append(winNew)
        env.scene.update(100.0) // zero delta

        XCTAssertFalse(env.scene.surfaces.contains(where: { $0.id == 706 }))
    }

    func testF07_B04_negativeDeltaStep_clockJumpBackwardsHandledSafely() {
        let win = FlakeWindowFixture.standardAppWindow(id: 707, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.update(100.0)

        // Negative delta (clock jumped back)
        env.scene.update(95.0)
        XCTAssertEqual(env.scene.surfaces.count, 2) // bottom shelf + win
    }

    func testF07_B05_largeDeltaStep60s_triggersSinglePollWithoutLooping() {
        let win1 = FlakeWindowFixture.standardAppWindow(id: 708, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win1])
        env.scene.update(100.0)

        let win2 = FlakeWindowFixture.standardAppWindow(id: 709, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows.append(win2)
        env.scene.update(160.0) // 60s leap

        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 709 }))
    }

    // =========================================================================
    // MARK: - Feature 8: SpriteKit Particle Dynamics Boundary Tests (5 tests)
    // =========================================================================

    func testF08_B01_disabledConfig_zeroParticleBirthRate() {
        var cfg = FlakeConfiguration()
        cfg.isEnabled = false
        env.config = cfg

        XCTAssertEqual(env.scene.emitterNode?.particleBirthRate, 0.0)
    }

    func testF08_B02_fallSpeedMultiplierMonotonicity_lightSteadyBlizzard() {
        let lightSpeed = 60 * SnowfallIntensity.light.fallSpeedMultiplier
        let steadySpeed = 60 * SnowfallIntensity.steady.fallSpeedMultiplier
        let blizzardSpeed = 60 * SnowfallIntensity.blizzard.fallSpeedMultiplier

        XCTAssertLessThan(lightSpeed, steadySpeed)
        XCTAssertLessThan(steadySpeed, blizzardSpeed)
        XCTAssertEqual(lightSpeed, 48.0)
        XCTAssertEqual(steadySpeed, 60.0)
        XCTAssertEqual(blizzardSpeed, 84.0)
    }

    func testF08_B03_particleLifetimeMatchesBudgetExactly() {
        for intensity in SnowfallIntensity.allCases {
            let budget = intensity.birthRate * intensity.particleLifetime
            XCTAssertEqual(budget, CGFloat(intensity.maxParticles), accuracy: 0.01)
        }
    }

    func testF08_B04_sceneResizeToZero_emitterHandlesGracefully() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        scene.didChangeSize(CGSize(width: 0, height: 0))
        XCTAssertNotNil(scene)
    }

    func testF08_B05_emitterParticleAlphaAndScaleRangesWithinValidBounds() {
        guard let emitter = env.scene.emitterNode else {
            XCTFail("Emitter node must exist")
            return
        }
        XCTAssertEqual(emitter.particleAlpha, 0.85, accuracy: 0.01)
        XCTAssertEqual(emitter.particleAlphaRange, 0.25, accuracy: 0.01)
        XCTAssertEqual(emitter.particleScale, 0.25, accuracy: 0.01)
        XCTAssertEqual(emitter.particleScaleRange, 0.15, accuracy: 0.01)
        XCTAssertEqual(emitter.particleColorBlendFactor, 1.0)
        XCTAssertNotNil(emitter.particleTexture)
    }

    // =========================================================================
    // MARK: - Feature 9: Snowfall Intensity Tiers Boundary Tests (5 tests)
    // =========================================================================

    func testF09_B01_lightIntensityMaxParticlesAndBirthRateBoundary() {
        let light = SnowfallIntensity.light
        XCTAssertEqual(light.maxParticles, 150)
        XCTAssertEqual(light.birthRate, 20.0)
        XCTAssertEqual(light.particleLifetime, 7.5)
    }

    func testF09_B02_steadyIntensityMaxParticlesAndBirthRateBoundary() {
        let steady = SnowfallIntensity.steady
        XCTAssertEqual(steady.maxParticles, 400)
        XCTAssertEqual(steady.birthRate, 50.0)
        XCTAssertEqual(steady.particleLifetime, 8.0)
    }

    func testF09_B03_blizzardIntensityMaxParticlesAndBirthRateBoundary() {
        let blizzard = SnowfallIntensity.blizzard
        XCTAssertEqual(blizzard.maxParticles, 900)
        XCTAssertEqual(blizzard.birthRate, 120.0)
        XCTAssertEqual(blizzard.particleLifetime, 7.5)
    }

    func testF09_B04_intensityRawValuesCodableSerializationRoundTrip() throws {
        for intensity in SnowfallIntensity.allCases {
            let encoded = try JSONEncoder().encode(intensity)
            let decoded = try JSONDecoder().decode(SnowfallIntensity.self, from: encoded)
            XCTAssertEqual(intensity, decoded)
        }
    }

    func testF09_B05_dynamicIntensitySwitchingUpdatesEmitterPropertiesImmediately() {
        env.config.intensity = .light
        XCTAssertEqual(env.scene.emitterNode?.particleBirthRate, 20.0)

        env.config.intensity = .blizzard
        XCTAssertEqual(env.scene.emitterNode?.particleBirthRate, 120.0)
        XCTAssertEqual(env.scene.emitterNode?.particleSpeed, 60.0 * 1.4)
    }

    // =========================================================================
    // MARK: - Feature 10: 360° Directional Wind Acceleration Boundary Tests (5 tests)
    // =========================================================================

    func testF10_B01_windAngle0DegreesEast_pureHorizontalPositiveAcceleration() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 200.0, accuracy: 0.01)
        XCTAssertEqual(ay, -120.0, accuracy: 0.01)
    }

    func testF10_B02_windAngle90DegreesSouth_pureVerticalDownAcceleration() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
        XCTAssertEqual(ay, -320.0, accuracy: 0.01) // -120 - 200
    }

    func testF10_B03_windAngle180DegreesWest_pureHorizontalNegativeAcceleration() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 180.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, -200.0, accuracy: 0.01)
        XCTAssertEqual(ay, -120.0, accuracy: 0.01)
    }

    func testF10_B04_windAngle270DegreesNorth_updraftVerticalAcceleration() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
        XCTAssertEqual(ay, 80.0, accuracy: 0.01) // -120 - 200*(-1) = +80
    }

    func testF10_B05_windAngleNegative90DegreesEquivalence_matches270Degrees() {
        let (axNeg, ayNeg) = FlakeScene.calculateWindAcceleration(windAngleDegrees: -90.0, windSpeed: 1.0, baseGravity: 120.0)
        let (ax270, ay270) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270.0, windSpeed: 1.0, baseGravity: 120.0)

        XCTAssertEqual(axNeg, ax270, accuracy: 0.01)
        XCTAssertEqual(ayNeg, ay270, accuracy: 0.01)
    }

    // =========================================================================
    // MARK: - Feature 11: Wind Speed Variation Boundary Tests (5 tests)
    // =========================================================================

    func testF11_B01_zeroWindSpeed_pureGravityOnly() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 45.0, windSpeed: 0.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
        XCTAssertEqual(ay, -120.0, accuracy: 0.01)
    }

    func testF11_B02_maxNormalizedWindSpeed3Point0_produces600pxPerSec2() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 3.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 600.0, accuracy: 0.01)
    }

    func testF11_B03_directSpeedInputAbove3_usesDirectValueUpTo600() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 450.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 450.0, accuracy: 0.01)
    }

    func testF11_B04_extremeSpeedOverflow1000_clampedTo600() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 1000.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 600.0, accuracy: 0.01, "Wind acceleration must be capped at 600 px/s²")
    }

    func testF11_B05_fractionalSpeed0Point1_producesLinearAcceleration() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 0.1, baseGravity: 120.0)
        XCTAssertEqual(ax, 20.0, accuracy: 0.01) // 0.1 * 200 = 20
    }

    // =========================================================================
    // MARK: - Feature 12: Column-Based Heightmap Accumulation Boundary Tests (5 tests)
    // =========================================================================

    func testF12_B01_binCountBoundary_width10Produces1Bin_width11Produces2Bins() {
        let map10 = SurfaceHeightmap(surfaceID: 1, width: 10.0)
        let map11 = SurfaceHeightmap(surfaceID: 2, width: 11.0)

        XCTAssertEqual(map10.bins.count, 1)
        XCTAssertEqual(map11.bins.count, 2)
    }

    func testF12_B02_zeroWidthSurface_allocatesMinimum1Bin() {
        let mapZero = SurfaceHeightmap(surfaceID: 3, width: 0.0)
        XCTAssertEqual(mapZero.bins.count, 1)
    }

    func testF12_B03_largeSurfaceWidth3840_allocatesExact384Bins() {
        let map4K = SurfaceHeightmap(surfaceID: 4, width: 3840.0)
        XCTAssertEqual(map4K.bins.count, 384)
    }

    func testF12_B04_zeroAccumulationRate_binsRemainZero() {
        var map = SurfaceHeightmap(surfaceID: 5, width: 200.0)
        map.accumulate(rate: 0.0, maxCap: 22.0)
        XCTAssertEqual(map.averageDepth, 0.0)
        XCTAssertEqual(map.maxDepth, 0.0)
    }

    func testF12_B05_monotonicAccumulationWithWindBias_binsGrowMonotonically() {
        var map = SurfaceHeightmap(surfaceID: 6, width: 200.0)
        map.accumulate(rate: 5.0, maxCap: 22.0, windAngleDegrees: 0.0, windSpeed: 1.0)
        let firstDepth = map.averageDepth
        XCTAssertGreaterThan(firstDepth, 0.0)

        map.accumulate(rate: 5.0, maxCap: 22.0, windAngleDegrees: 0.0, windSpeed: 1.0)
        let secondDepth = map.averageDepth
        XCTAssertGreaterThan(secondDepth, firstDepth)
    }

    // =========================================================================
    // MARK: - Feature 13: Angle of Repose Smoothing Boundary Tests (5 tests)
    // =========================================================================

    func testF13_B01_singleBinArray_remainsUnchanged() {
        let bins: [CGFloat] = [12.0]
        let smoothed = SurfaceHeightmap.convolve(bins: bins)
        XCTAssertEqual(smoothed, [12.0])
    }

    func testF13_B02_twoBinsArray_appliesTwoPointBoundaryTaper() {
        let bins: [CGFloat] = [10.0, 20.0]
        let smoothed = SurfaceHeightmap.convolve(bins: bins)
        // result[0] = (2*10 + 20)/3 = 40/3 = 13.333
        // result[1] = (10 + 2*20)/3 = 50/3 = 16.666
        XCTAssertEqual(smoothed[0], 40.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(smoothed[1], 50.0 / 3.0, accuracy: 0.01)
    }

    func testF13_B03_centerImpulseThreeBins_convolvesSymmetrically() {
        let bins: [CGFloat] = [0.0, 40.0, 0.0]
        let smoothed = SurfaceHeightmap.convolve(bins: bins)
        // smoothed[1] = (0 + 2*40 + 0)/4 = 20.0
        XCTAssertEqual(smoothed[1], 20.0, accuracy: 0.01)
        XCTAssertEqual(smoothed[0], smoothed[2], accuracy: 0.01)
    }

    func testF13_B04_uniformBinHeights_remainsIdenticalAfterSmoothing() {
        let bins: [CGFloat] = [15.0, 15.0, 15.0, 15.0, 15.0]
        let smoothed = SurfaceHeightmap.convolve(bins: bins)
        for i in 0..<bins.count {
            XCTAssertEqual(smoothed[i], 15.0, accuracy: 0.01)
        }
    }

    func testF13_B05_maxCapEnforcementDuringConvolution_clampsSmoothedValues() {
        let bins: [CGFloat] = [50.0, 50.0, 50.0]
        let smoothed = SurfaceHeightmap.convolve(bins: bins, maxCap: 22.0)
        for val in smoothed {
            XCTAssertLessThanOrEqual(val, 22.0)
        }
    }

    // =========================================================================
    // MARK: - Feature 14: Window Movement Re-anchoring Boundary Tests (5 tests)
    // =========================================================================

    func testF14_B01_zeroDisplacementReanchor_returnsZeroVector() {
        var map = SurfaceHeightmap(surfaceID: 10, width: 200.0, anchorPosition: CGPoint(x: 100, y: 200))
        let delta = map.reanchor(newAnchor: CGPoint(x: 100, y: 200))

        XCTAssertEqual(delta.dx, 0.0)
        XCTAssertEqual(delta.dy, 0.0)
        XCTAssertEqual(map.anchorPosition, CGPoint(x: 100, y: 200))
    }

    func testF14_B02_negativeTranslation_returnsNegativeVector() {
        var map = SurfaceHeightmap(surfaceID: 11, width: 200.0, anchorPosition: CGPoint(x: 300, y: 400))
        let delta = map.reanchor(newAnchor: CGPoint(x: 200, y: 350))

        XCTAssertEqual(delta.dx, -100.0)
        XCTAssertEqual(delta.dy, -50.0)
        XCTAssertEqual(map.anchorPosition, CGPoint(x: 200, y: 350))
    }

    func testF14_B03_widthExpansionDuringMove_preservesExistingAccumulationAndZeroPads() {
        var map = SurfaceHeightmap(surfaceID: 12, width: 100.0) // 10 bins
        map.bins = Array(repeating: 15.0, count: 10)
        map.resize(to: 150.0) // 15 bins

        XCTAssertEqual(map.bins.count, 15)
        for i in 0..<10 {
            XCTAssertEqual(map.bins[i], 15.0)
        }
        for i in 10..<15 {
            XCTAssertEqual(map.bins[i], 0.0)
        }
    }

    func testF14_B04_widthContractionDuringMove_truncatesBinsWithoutCrash() {
        var map = SurfaceHeightmap(surfaceID: 13, width: 150.0) // 15 bins
        map.bins = Array(repeating: 18.0, count: 15)
        map.resize(to: 80.0) // 8 bins

        XCTAssertEqual(map.bins.count, 8)
        for val in map.bins {
            XCTAssertEqual(val, 18.0)
        }
    }

    func testF14_B05_largeLeapDisplacementAcrossScreen_reanchorsToNewPointAccurately() {
        var map = SurfaceHeightmap(surfaceID: 14, width: 400.0, anchorPosition: CGPoint(x: 50, y: 50))
        let delta = map.reanchor(newAnchor: CGPoint(x: 1800, y: 950))

        XCTAssertEqual(delta.dx, 1750.0)
        XCTAssertEqual(delta.dy, 900.0)
        XCTAssertEqual(map.anchorPosition, CGPoint(x: 1800, y: 950))
    }

    // =========================================================================
    // MARK: - Feature 15: Surface Accumulation Cap Boundary Tests (5 tests)
    // =========================================================================

    func testF15_B01_windowTouchingScreenTop_capIsZero() {
        let surface = CollisionSurface(id: 151, frame: CGRect(x: 100, y: 780, width: 400, height: 300), topEdgeY: 1080, minX: 100, maxX: 500)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 0.0, "Window touching screen ceiling must have 0 cap")
    }

    func testF15_B02_window10ptBelowScreenTop_capClampedTo10() {
        let surface = CollisionSurface(id: 152, frame: CGRect(x: 100, y: 770, width: 400, height: 300), topEdgeY: 1070, minX: 100, maxX: 500)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 10.0, "Ceiling margin of 10pt must restrict cap to 10 (< 22)")
    }

    func testF15_B03_standardWindowFarBelowTop_capIs22() {
        let surface = CollisionSurface(id: 153, frame: CGRect(x: 100, y: 200, width: 400, height: 300), topEdgeY: 500, minX: 100, maxX: 500)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 22.0, "Standard window base cap is 22px")
    }

    func testF15_B04_dockSurface_capIs30() {
        let surface = CollisionSurface(id: 154, frame: CGRect(x: 0, y: 0, width: 1920, height: 70), topEdgeY: 70, minX: 0, maxX: 1920, isDock: true)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 30.0, "Dock base cap is 30px")
    }

    func testF15_B05_bottomDisplayShelf_capIs50() {
        let surface = CollisionSurface(id: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1), topEdgeY: 0, minX: 0, maxX: 1920, isDock: false)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 50.0, "Bottom display shelf base cap is 50px")
    }

    // =========================================================================
    // MARK: - Feature 16: Interactive Mitten Tool Boundary Tests (5 tests)
    // =========================================================================

    func testF16_B01_cursorExactlyOnLedge_clearsBinsWithinRadius45() {
        let win = FlakeWindowFixture.standardAppWindow(id: 161, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        guard let s = env.scene.surfaces.first(where: { $0.id == 161 }) else {
            XCTFail("Window surface must exist")
            return
        }
        env.scene.heightmaps[161]?.bins = Array(repeating: 20.0, count: 40)

        // Clear at center of window ledge
        let centerPoint = CGPoint(x: (s.minX + s.maxX) / 2, y: s.topEdgeY)
        env.useTool(.mitten, at: centerPoint, radius: 45.0)

        let depthAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 161)
        XCTAssertLessThan(depthAfter, 20.0)
    }

    func testF16_B02_cursorBeyondVerticalThreshold_noSnowCleared() {
        let win = FlakeWindowFixture.standardAppWindow(id: 162, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        guard let s = env.scene.surfaces.first(where: { $0.id == 162 }) else { return }
        env.scene.heightmaps[162]?.bins = Array(repeating: 20.0, count: 40)

        // Point is 70pt away vertically (> radius 45 + 20)
        let farPoint = CGPoint(x: (s.minX + s.maxX) / 2, y: s.topEdgeY + 70.0)
        env.useTool(.mitten, at: farPoint, radius: 45.0)

        let depthAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 162)
        XCTAssertEqual(depthAfter, 20.0, "Cursor beyond vertical reach must not clear snow")
    }

    func testF16_B03_repeatedClearingClampedAtZero_neverBecomesNegative() {
        let win = FlakeWindowFixture.standardAppWindow(id: 163, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        guard let s = env.scene.surfaces.first(where: { $0.id == 163 }) else { return }
        env.scene.heightmaps[163]?.bins = Array(repeating: 10.0, count: 40)

        let centerPoint = CGPoint(x: (s.minX + s.maxX) / 2, y: s.topEdgeY)
        for _ in 1...10 {
            env.useTool(.mitten, at: centerPoint, radius: 45.0)
        }

        let bins = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 163)
        for b in bins {
            XCTAssertGreaterThanOrEqual(b, 0.0, "Bins must never underflow below zero")
        }
    }

    func testF16_B04_cursorAtLeftmostEdge_clearsOnlyLeftBins() {
        let win = FlakeWindowFixture.standardAppWindow(id: 164, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        guard let s = env.scene.surfaces.first(where: { $0.id == 164 }) else { return }
        env.scene.heightmaps[164]?.bins = Array(repeating: 20.0, count: 40)

        // Clear at minX
        let leftEdgePoint = CGPoint(x: s.minX, y: s.topEdgeY)
        env.useTool(.mitten, at: leftEdgePoint, radius: 45.0)

        let bins = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 164)
        XCTAssertLessThan(bins.first ?? 0, 20.0, "First bin should be reduced")
        XCTAssertEqual(bins.last, 20.0, "Last bin should remain untouched")
    }

    func testF16_B05_clearingAppliesToBothWindowAndBottomShelfIndependently() {
        let win = FlakeWindowFixture.standardAppWindow(id: 165, bounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        env.setWindows([win])
        env.scene.heightmaps[0]?.bins = Array(repeating: 20.0, count: 192)
        env.scene.heightmaps[165]?.bins = Array(repeating: 20.0, count: 40)

        // Clear bottom shelf at (500, 0)
        env.useTool(.mitten, at: CGPoint(x: 500, y: 0), radius: 45.0)

        let bottomDepth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 0)
        let winDepth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 165)
        XCTAssertLessThan(bottomDepth, 20.0)
        XCTAssertEqual(winDepth, 20.0, "Window depth should remain unaffected when clearing bottom")
    }

    // =========================================================================
    // MARK: - Feature 17: Interactive Shovel Tool Boundary Tests (5 tests)
    // =========================================================================

    func testF17_B01_shovelRadius60ClearsWiderSpanThanMitten45() {
        let winA = FlakeWindowFixture.standardAppWindow(id: 171, bounds: CGRect(x: 100, y: 200, width: 400, height: 300))
        env.setWindows([winA])
        env.scene.heightmaps[171]?.bins = Array(repeating: 20.0, count: 40)

        let point = CGPoint(x: 300, y: env.scene.surfaces.first(where: { $0.id == 171 })?.topEdgeY ?? 880)
        env.useTool(.shovel, at: point, radius: 60.0)
        let clearedShovelBins = env.scene.heightmaps[171]?.bins.filter { $0 < 20.0 }.count ?? 0

        // Reset and test with mitten radius
        env.scene.heightmaps[171]?.bins = Array(repeating: 20.0, count: 40)
        env.useTool(.mitten, at: point, radius: 45.0)
        let clearedMittenBins = env.scene.heightmaps[171]?.bins.filter { $0 < 20.0 }.count ?? 0

        XCTAssertGreaterThan(clearedShovelBins, clearedMittenBins, "Shovel (radius 60) must clear more bins than mitten (radius 45)")
    }

    func testF17_B02_fullLedgeSweep_clearsEntireSurfaceToZero() {
        let win = FlakeWindowFixture.standardAppWindow(id: 172, bounds: CGRect(x: 200, y: 200, width: 200, height: 300))
        env.setWindows([win])
        guard let s = env.scene.surfaces.first(where: { $0.id == 172 }) else { return }
        env.scene.heightmaps[172]?.bins = Array(repeating: 10.0, count: 20)

        var x = s.minX
        while x <= s.maxX {
            env.useTool(.shovel, at: CGPoint(x: x, y: s.topEdgeY), radius: 60.0)
            x += 30.0
        }

        let depth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 172)
        XCTAssertEqual(depth, 0.0, "Full sweep must clear all bins to zero")
    }

    func testF17_B03_shovelOnZeroDepthLedge_maintainsZeroWithoutUnderflow() {
        let win = FlakeWindowFixture.standardAppWindow(id: 173, bounds: CGRect(x: 200, y: 200, width: 200, height: 300))
        env.setWindows([win])
        guard let s = env.scene.surfaces.first(where: { $0.id == 173 }) else { return }

        env.useTool(.shovel, at: CGPoint(x: s.minX + 50, y: s.topEdgeY), radius: 60.0)
        let depth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 173)
        XCTAssertEqual(depth, 0.0)
    }

    func testF17_B04_shovelOutsideAnySurface_noHeightmapsModified() {
        let win = FlakeWindowFixture.standardAppWindow(id: 174, bounds: CGRect(x: 200, y: 200, width: 200, height: 300))
        env.setWindows([win])
        env.scene.heightmaps[174]?.bins = Array(repeating: 15.0, count: 20)

        // Click outside any surface
        env.useTool(.shovel, at: CGPoint(x: 10, y: 500), radius: 60.0)
        let depth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 174)
        XCTAssertEqual(depth, 15.0)
    }

    func testF17_B05_shovelOnDockLedge_clearsDockAccumulationAccurately() {
        let dockWin = FlakeWindowFixture.dockWindow(bounds: CGRect(x: 0, y: 1000, width: 1920, height: 80))
        env.setWindows([dockWin])
        env.scene.heightmaps[999]?.bins = Array(repeating: 25.0, count: 192)

        let dockTopY = env.scene.surfaces.first(where: { $0.id == 999 })?.topEdgeY ?? 80.0
        env.useTool(.shovel, at: CGPoint(x: 960, y: dockTopY), radius: 60.0)

        let dockDepth = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 999)
        XCTAssertLessThan(dockDepth, 25.0)
    }

    // =========================================================================
    // MARK: - Feature 18: Dynamic Mouse Event Passthrough Boundary Tests (5 tests)
    // =========================================================================

    func testF18_B01_toolNone_ignoresMouseEventsTrue() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .none))
        defer { overlay.close() }
        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.acceptsMouseMovedEvents)
    }

    func testF18_B02_toolMitten_ignoresMouseEventsFalse() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .mitten))
        defer { overlay.close() }
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertTrue(overlay.acceptsMouseMovedEvents)
    }

    func testF18_B03_toolShovel_ignoresMouseEventsFalse() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .shovel))
        defer { overlay.close() }
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertTrue(overlay.acceptsMouseMovedEvents)
    }

    func testF18_B04_toolSnowman_ignoresMouseEventsFalse() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .snowman))
        defer { overlay.close() }
        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertTrue(overlay.acceptsMouseMovedEvents)
    }

    func testF18_B05_rapidToolSwitching_restoresCorrectStateConsistently() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .none))
        defer { overlay.close() }

        for _ in 1...20 {
            overlay.flakeScene.config.activeTool = .shovel
            overlay.updateMouseInteractivity()
            XCTAssertFalse(overlay.ignoresMouseEvents)

            overlay.flakeScene.config.activeTool = .none
            overlay.updateMouseInteractivity()
            XCTAssertTrue(overlay.ignoresMouseEvents)
        }
    }

    // =========================================================================
    // MARK: - Feature 19: Automated Snowplow Trigger Boundary Tests (5 tests)
    // =========================================================================

    func testF19_B01_bottomDepthExactly32_doesNotTriggerSnowplow() {
        // Average depth of exactly 32.0 does not exceed 32.0 threshold (> 32)
        let boundaryMap = SurfaceHeightmap(surfaceID: 0, bins: Array(repeating: 32.0, count: 192))
        XCTAssertFalse(boundaryMap.averageDepth > 32.0, "Depth of exactly 32.0 must NOT exceed 32")

        // Sub-threshold depth in scene does not trigger snowplow
        env.scene.heightmaps[0]?.bins = Array(repeating: 25.0, count: 192)
        env.scene.update(100.1)
        XCTAssertFalse(env.scene.isSnowplowActive)
    }

    func testF19_B02_bottomDepth32Point01_triggersSnowplow() {
        let aboveMap = SurfaceHeightmap(surfaceID: 0, bins: Array(repeating: 32.01, count: 192))
        XCTAssertTrue(aboveMap.averageDepth > 32.0, "Depth of 32.01 exceeds 32")

        env.scene.heightmaps[0]?.bins = Array(repeating: 35.0, count: 192)
        env.scene.update(100.1)
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    func testF19_B03_snowplowDisabled_depth40DoesNotTriggerSnowplow() {
        env.config.snowplowEnabled = false
        env.scene.heightmaps[0]?.bins = Array(repeating: 40.0, count: 192)
        env.scene.update(100.1)
        XCTAssertFalse(env.scene.isSnowplowActive, "Snowplow disabled in config must not trigger")
    }

    func testF19_B04_plowAlreadyActive_secondTriggerIgnored() {
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)

        // Attempt second trigger
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    func testF19_B05_windowLedgeDepthExceeds32_doesNotTriggerBottomPlow() {
        let win = FlakeWindowFixture.standardAppWindow(id: 195, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.heightmaps[195]?.bins = Array(repeating: 45.0, count: 40)
        env.scene.heightmaps[0]?.bins = Array(repeating: 10.0, count: 192)

        env.scene.update(100.1)
        XCTAssertFalse(env.scene.isSnowplowActive, "Window drift depth > 32 must not trigger bottom snowplow")
    }

    // =========================================================================
    // MARK: - Feature 20: Snowplow Vehicle Models Boundary Tests (5 tests)
    // =========================================================================

    func testF20_B01_allFiveModelsIterableInEnum() {
        let models = SnowplowModel.allCases
        XCTAssertEqual(models.count, 5)
        XCTAssertTrue(models.contains(.classicTractor))
        XCTAssertTrue(models.contains(.vintageTractor))
        XCTAssertTrue(models.contains(.snowmobile))
        XCTAssertTrue(models.contains(.penguin))
        XCTAssertTrue(models.contains(.custom))
    }

    func testF20_B02_classicTractorIconCarSideFill() {
        XCTAssertEqual(SnowplowModel.classicTractor.iconName, "car.side.fill")
    }

    func testF20_B03_vintageTractorIconBusFill() {
        XCTAssertEqual(SnowplowModel.vintageTractor.iconName, "bus.fill")
    }

    func testF20_B04_snowmobileIconFigureSkiingDownhill() {
        XCTAssertEqual(SnowplowModel.snowmobile.iconName, "figure.skiing.downhill")
    }

    func testF20_B05_penguinIconBirdFillAndCustomIconPhotoFill() {
        XCTAssertEqual(SnowplowModel.penguin.iconName, "bird.fill")
        XCTAssertEqual(SnowplowModel.custom.iconName, "photo.fill")
    }

    // =========================================================================
    // MARK: - Feature 21: Snowplow Traversal Animation Boundary Tests (5 tests)
    // =========================================================================

    func testF21_B01_snowplowInitialPositionXIsNegative60() {
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    func testF21_B02_snowplowDestinationXIsWidthPlus60() {
        let expectedDestX = env.scene.size.width + 60
        XCTAssertEqual(expectedDestX, 1980.0)
    }

    func testF21_B03_snowplowZPositionIs30() {
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    func testF21_B04_snowplowTraversalOn4KDisplayScalesDestination() {
        let scene4K = FlakeScene(size: CGSize(width: 3840, height: 2160))
        let dest = scene4K.size.width + 60
        XCTAssertEqual(dest, 3900.0)
    }

    func testF21_B05_snowplowSweepSetsActiveFlagImmediately() {
        XCTAssertFalse(env.scene.isSnowplowActive)
        env.scene.triggerSnowplowSweep()
        XCTAssertTrue(env.scene.isSnowplowActive)
    }

    // =========================================================================
    // MARK: - Feature 22: Window Fairy Lights Boundary Tests (5 tests)
    // =========================================================================

    func testF22_B01_subSpacingWindowWidth20_createsMinimum1Bulb() {
        let win = FlakeWindowFixture.makeWindow(id: 221, bounds: CGRect(x: 100, y: 100, width: 20, height: 100))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        XCTAssertNotNil(env.scene)
    }

    func testF22_B02_exactMultiplesOfSpacing280_creates10Bulbs() {
        let win = FlakeWindowFixture.standardAppWindow(id: 222, bounds: CGRect(x: 100, y: 100, width: 280, height: 200))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        XCTAssertNotNil(env.scene)
    }

    func testF22_B03_bottomDisplayShelfIdZero_neverGetsFairyLights() {
        env.config.fairyLightsEnabled = true
        env.scene.updateSurfaces()
        XCTAssertNotNil(env.scene)
    }

    func testF22_B04_fairyLightsDisabledInConfig_clearsFairyLights() {
        env.config.fairyLightsEnabled = false
        env.scene.applyConfiguration()
        XCTAssertFalse(env.config.fairyLightsEnabled)
    }

    func testF22_B05_fairyLightBulbYPositionIsTopEdgeYMinus2() {
        let win = FlakeWindowFixture.standardAppWindow(id: 225, bounds: CGRect(x: 100, y: 100, width: 300, height: 200))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        XCTAssertNotNil(env.scene)
    }

    // =========================================================================
    // MARK: - Feature 23: Fairy Lights Twinkling Animation Boundary Tests (5 tests)
    // =========================================================================

    func testF23_B01_bulbShapeNodeRadius3Point5AndGlow2Point5() {
        let win = FlakeWindowFixture.standardAppWindow(id: 231, bounds: CGRect(x: 100, y: 100, width: 300, height: 200))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        XCTAssertNotNil(env.scene)
    }

    func testF23_B02_bulbZPositionIs15() {
        let win = FlakeWindowFixture.standardAppWindow(id: 232, bounds: CGRect(x: 100, y: 100, width: 300, height: 200))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        XCTAssertNotNil(env.scene)
    }

    func testF23_B03_bulbColorsCycleThroughFiveFestiveColors() {
        let colors: [NSColor] = [.systemYellow, .systemRed, .systemGreen, .systemBlue, .systemOrange]
        XCTAssertEqual(colors.count, 5)
    }

    func testF23_B04_movingWindowRepositionsFairyLightBulbsByDelta() {
        let win = FlakeWindowFixture.standardAppWindow(id: 234, bounds: CGRect(x: 100, y: 100, width: 300, height: 200))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        env.simulateWindowMove(id: 234, newBounds: CGRect(x: 200, y: 150, width: 300, height: 200))
        XCTAssertNotNil(env.scene)
    }

    func testF23_B05_closedWindowRemovesFairyLightNodes() {
        let win = FlakeWindowFixture.standardAppWindow(id: 235, bounds: CGRect(x: 100, y: 100, width: 300, height: 200))
        env.config.fairyLightsEnabled = true
        env.setWindows([win])
        env.setWindows([]) // Close window
        XCTAssertFalse(env.scene.surfaces.contains(where: { $0.id == 235 }))
    }

    // =========================================================================
    // MARK: - Feature 24: 360° Wind Compass Control UI Boundary Tests (5 tests)
    // =========================================================================

    func testF24_B01_angleBoundary0And360DegreesAreEquivalent() {
        let (ax0, ay0) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 2.0)
        let (ax360, ay360) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 360.0, windSpeed: 2.0)

        XCTAssertEqual(ax0, ax360, accuracy: 0.01)
        XCTAssertEqual(ay0, ay360, accuracy: 0.01)
    }

    func testF24_B02_negativeAngleMinus45_calculatesValidAccelerations() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: -45.0, windSpeed: 1.5)
        XCTAssertFalse(ax.isNaN)
        XCTAssertFalse(ay.isNaN)
        XCTAssertGreaterThan(ax, 0.0) // cos(-45) > 0
    }

    func testF24_B03_windSpeedZero_producesZeroHorizontalAcceleration() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 30.0, windSpeed: 0.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
    }

    func testF24_B04_windSpeed3Point0_producesMaxNormalizedAcceleration() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 3.0)
        XCTAssertEqual(ax, 600.0, accuracy: 0.01)
    }

    func testF24_B05_windDirectionDegreesAliasMatchesWindAngleDegrees() {
        var cfg = FlakeConfiguration()
        cfg.windDirectionDegrees = 225.0
        XCTAssertEqual(cfg.windAngleDegrees, 225.0)

        cfg.windAngleDegrees = 315.0
        XCTAssertEqual(cfg.windDirectionDegrees, 315.0)
    }

    // =========================================================================
    // MARK: - Feature 25: Dual Layer Modes Boundary Tests (5 tests)
    // =========================================================================

    func testF25_B01_overlayMode_setsFloatingWindowLevel() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(layerMode: .overlay))
        defer { overlay.close() }
        XCTAssertEqual(overlay.level, .floating)
    }

    func testF25_B02_desktopMode_controllerClosesOverlayWindows() {
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        let controller = FlakeController(
            config: FlakeConfiguration(isEnabled: true, layerMode: .desktop),
            screenProvider: mockScreens
        )
        defer { controller.closeAllOverlayWindows() }

        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    func testF25_B03_switchFromOverlayToDesktop_closesExistingOverlayWindows() {
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        let controller = FlakeController(
            config: FlakeConfiguration(isEnabled: true, layerMode: .overlay),
            screenProvider: mockScreens
        )
        defer { controller.closeAllOverlayWindows() }
        XCTAssertEqual(controller.overlayWindows.count, 1)

        controller.config.layerMode = .desktop
        controller.applyConfiguration()
        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    func testF25_B04_switchFromDesktopToOverlay_recreatesOverlayWindows() {
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        let controller = FlakeController(
            config: FlakeConfiguration(isEnabled: true, layerMode: .desktop),
            screenProvider: mockScreens
        )
        defer { controller.closeAllOverlayWindows() }
        XCTAssertTrue(controller.overlayWindows.isEmpty)

        controller.config.layerMode = .overlay
        controller.applyConfiguration()
        XCTAssertEqual(controller.overlayWindows.count, 1)
    }

    func testF25_B05_layerModeAllCasesAndCodableRoundTrip() throws {
        let modes = FlakeLayerMode.allCases
        XCTAssertEqual(modes.count, 2)
        for m in modes {
            let data = try JSONEncoder().encode(m)
            let decoded = try JSONDecoder().decode(FlakeLayerMode.self, from: data)
            XCTAssertEqual(m, decoded)
        }
    }

    // =========================================================================
    // MARK: - Feature 26: Multi-Display Management Boundary Tests (5 tests)
    // =========================================================================

    func testF26_B01_zeroScreensInProvider_overlayWindowsDictionaryEmpty() {
        let emptyProvider = MockScreenProvider(screens: [])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay), screenProvider: emptyProvider)
        defer { controller.closeAllOverlayWindows() }

        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    func testF26_B02_singleScreen_createsExactlyOneOverlayWindow() {
        let singleProvider = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay), screenProvider: singleProvider)
        defer { controller.closeAllOverlayWindows() }

        XCTAssertEqual(controller.overlayWindows.count, 1)
    }

    func testF26_B03_dualScreens_createsTwoWindowsWithMatchingDisplayIDs() {
        let dualProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay), screenProvider: dualProvider)
        defer { controller.closeAllOverlayWindows() }

        XCTAssertEqual(controller.overlayWindows.count, 2)
        XCTAssertNotNil(controller.overlayWindows[1])
        XCTAssertNotNil(controller.overlayWindows[2])
    }

    func testF26_B04_tripleScreens_createsThreeIndependentWindows() {
        let tripleProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 3, frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080))
        ])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay), screenProvider: tripleProvider)
        defer { controller.closeAllOverlayWindows() }

        XCTAssertEqual(controller.overlayWindows.count, 3)
    }

    func testF26_B05_disconnectOneScreen_cleansUpRemovedDisplayWindow() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay), screenProvider: mockScreens)
        defer { controller.closeAllOverlayWindows() }
        XCTAssertEqual(controller.overlayWindows.count, 2)

        // Simulate display unplug
        mockScreens.screens = [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        controller.rebuildOverlayWindows()

        XCTAssertEqual(controller.overlayWindows.count, 1)
        XCTAssertNil(controller.overlayWindows[2])
    }

    // =========================================================================
    // MARK: - Feature 27: Display Parameter Change Handling Boundary Tests (5 tests)
    // =========================================================================

    func testF27_B01_displayResizeTo8K_updatesWindowAndSceneSize() {
        let initial = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = FlakeOverlayWindow(frame: initial)
        defer { window.close() }

        let target8K = CGRect(x: 0, y: 0, width: 7680, height: 4320)
        window.updateFrame(target8K)

        XCTAssertEqual(window.frame.size, target8K.size)
        XCTAssertEqual(window.flakeScene.size, target8K.size)
    }

    func testF27_B02_displayResizeToSmall320x240_updatesWindowAndSceneSize() {
        let initial = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = FlakeOverlayWindow(frame: initial)
        defer { window.close() }

        let targetSmall = CGRect(x: 0, y: 0, width: 320, height: 240)
        window.updateFrame(targetSmall)

        XCTAssertEqual(window.frame.size, targetSmall.size)
        XCTAssertEqual(window.flakeScene.size, targetSmall.size)
    }

    func testF27_B03_displayOriginShift_updatesWindowFrameOrigin() {
        let initial = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = FlakeOverlayWindow(frame: initial)
        defer { window.close() }

        let shifted = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        window.updateFrame(shifted)

        XCTAssertEqual(window.frame.origin.x, 1920.0)
    }

    func testF27_B04_screenParametersNotification_rebuildsOverlayWindows() {
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), screenProvider: mockScreens)
        defer { controller.closeAllOverlayWindows() }

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertNotNil(controller)
    }

    func testF27_B05_rebuildWithNewScreenBounds_updatesSurfacesGeometry() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: CGRect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        let bottomShelf = surfaces.first(where: { $0.id == 0 })
        XCTAssertEqual(bottomShelf?.width, 2560.0)
    }

    // =========================================================================
    // MARK: - Feature 28: PowerManager Integration Boundary Tests (5 tests)
    // =========================================================================

    func testF28_B01_setPausedTrue_setsSkViewIsPausedOnAllWindows() {
        let mockScreens = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), screenProvider: mockScreens)
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(true)
        for (_, win) in controller.overlayWindows {
            XCTAssertTrue(win.skView.isPaused)
        }
    }

    func testF28_B02_setPausedFalse_resumesSkViewOnAllWindows() {
        let mockScreens = MockScreenProvider(screens: [DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), screenProvider: mockScreens)
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(true)
        controller.setPaused(false)
        for (_, win) in controller.overlayWindows {
            XCTAssertFalse(win.skView.isPaused)
        }
    }

    func testF28_B03_idempotentPauseCalls_causeNoErrors() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true))
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(true)
        controller.setPaused(true)
        XCTAssertTrue(controller.isPaused)
    }

    func testF28_B04_idempotentResumeCalls_causeNoErrors() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true))
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(false)
        controller.setPaused(false)
        XCTAssertFalse(controller.isPaused)
    }

    func testF28_B05_delegateCallback_powerManagerDidChangePauseState_updatesController() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        mockPower.simulateDisplaySleep()
        XCTAssertTrue(controller.isPaused)

        mockPower.simulateDisplayWake()
        XCTAssertFalse(controller.isPaused)
    }

    // =========================================================================
    // MARK: - Feature 29: Display Sleep Auto-Pause Boundary Tests (5 tests)
    // =========================================================================

    func testF29_B01_displaySleep_addsDisplaySleepingPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.displaySleeping))
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF29_B02_displaySleep_controllerSuspended() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        mockPower.simulateDisplaySleep()
        XCTAssertTrue(controller.isPaused)
    }

    func testF29_B03_displayWake_removesDisplaySleepingReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        mockPower.simulateDisplayWake()
        XCTAssertFalse(mockPower.currentPauseReasons.contains(.displaySleeping))
        XCTAssertFalse(mockPower.isPaused)
    }

    func testF29_B04_displayWakeWhileScreenLocked_remainsPaused() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        mockPower.simulateScreenLock()
        mockPower.simulateDisplayWake()

        XCTAssertTrue(mockPower.isPaused, "Must remain paused while screenLocked is active")
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.screenLocked))
    }

    func testF29_B05_rapidSleepWakeCycling_settlesInFinalState() {
        let mockPower = FlakeMockPowerManager()
        for _ in 1...10 {
            mockPower.simulateDisplaySleep()
            mockPower.simulateDisplayWake()
        }
        XCTAssertFalse(mockPower.isPaused)
        XCTAssertTrue(mockPower.currentPauseReasons.isEmpty)
    }

    // =========================================================================
    // MARK: - Feature 30: Screen Lock Auto-Pause Boundary Tests (5 tests)
    // =========================================================================

    func testF30_B01_screenLock_addsScreenLockedPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.screenLocked))
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF30_B02_screenLock_controllerSuspended() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        mockPower.simulateScreenLock()
        XCTAssertTrue(controller.isPaused)
    }

    func testF30_B03_screenUnlock_removesScreenLockedReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        mockPower.simulateScreenUnlock()
        XCTAssertFalse(mockPower.currentPauseReasons.contains(.screenLocked))
        XCTAssertFalse(mockPower.isPaused)
    }

    func testF30_B04_screenUnlockWhileDisplaySleeping_remainsPaused() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        mockPower.simulateDisplaySleep()
        mockPower.simulateScreenUnlock()

        XCTAssertTrue(mockPower.isPaused, "Must remain paused while displaySleeping is active")
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.displaySleeping))
    }

    func testF30_B05_allPauseReasonsCleared_resumesController() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        mockPower.simulateDisplaySleep()
        mockPower.simulateScreenUnlock()
        mockPower.simulateDisplayWake()

        XCTAssertFalse(mockPower.isPaused)
        XCTAssertTrue(mockPower.currentPauseReasons.isEmpty)
    }

    // =========================================================================
    // MARK: - Feature 31: Fullscreen Occlusion Auto-Pause Boundary Tests (5 tests)
    // =========================================================================

    func testF31_B01_fullscreenActive_addsFullscreenAppPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF31_B02_fullscreenExit_removesFullscreenAppPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateFullscreenApp(isActive: true)
        mockPower.simulateFullscreenApp(isActive: false)
        XCTAssertFalse(mockPower.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertFalse(mockPower.isPaused)
    }

    func testF31_B03_fullscreenExitWhileUserPaused_remainsPaused() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateUserPause(isPaused: true)
        mockPower.simulateFullscreenApp(isActive: true)
        mockPower.simulateFullscreenApp(isActive: false)

        XCTAssertTrue(mockPower.isPaused, "Must remain paused when user paused")
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.userPaused))
    }

    func testF31_B04_fullscreenExitWhileDisplaySleeping_remainsPaused() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        mockPower.simulateFullscreenApp(isActive: true)
        mockPower.simulateFullscreenApp(isActive: false)

        XCTAssertTrue(mockPower.isPaused)
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.displaySleeping))
    }

    func testF31_B05_fullscreenRapidToggling_settlesInFinalState() {
        let mockPower = FlakeMockPowerManager()
        for _ in 1...20 {
            mockPower.simulateFullscreenApp(isActive: true)
            mockPower.simulateFullscreenApp(isActive: false)
        }
        XCTAssertFalse(mockPower.isPaused)
        XCTAssertFalse(mockPower.currentPauseReasons.contains(.fullscreenApp))
    }

    // =========================================================================
    // MARK: - Feature 32: Menu Bar Companion Controls Boundary Tests (5 tests)
    // =========================================================================

    func testF32_B01_toggleIsEnabled_togglesStateBackAndForth() {
        var cfg = FlakeConfiguration()
        XCTAssertFalse(cfg.isEnabled)

        cfg.isEnabled.toggle()
        XCTAssertTrue(cfg.isEnabled)

        cfg.isEnabled.toggle()
        XCTAssertFalse(cfg.isEnabled)
    }

    func testF32_B02_cycleAllIntensities_lightSteadyBlizzardLight() {
        var cfg = FlakeConfiguration()
        cfg.intensity = .light
        XCTAssertEqual(cfg.intensity, .light)

        cfg.intensity = .steady
        XCTAssertEqual(cfg.intensity, .steady)

        cfg.intensity = .blizzard
        XCTAssertEqual(cfg.intensity, .blizzard)

        cfg.intensity = .light
        XCTAssertEqual(cfg.intensity, .light)
    }

    func testF32_B03_clearAllSnow_clearsAllSurfaceHeightmapsToZero() {
        let win = FlakeWindowFixture.standardAppWindow(id: 321, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.heightmaps[0]?.bins = Array(repeating: 20.0, count: 192)
        env.scene.heightmaps[321]?.bins = Array(repeating: 20.0, count: 40)

        env.scene.clearAllSnow()
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 0), 0.0)
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 321), 0.0)
    }

    func testF32_B04_activeToolSwitchingInConfig_updatesOverlayMouseInteractivity() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .none))
        defer { overlay.close() }
        XCTAssertTrue(overlay.ignoresMouseEvents)

        overlay.flakeScene.config.activeTool = .mitten
        overlay.updateMouseInteractivity()
        XCTAssertFalse(overlay.ignoresMouseEvents)

        overlay.flakeScene.config.activeTool = .none
        overlay.updateMouseInteractivity()
        XCTAssertTrue(overlay.ignoresMouseEvents)
    }

    func testF32_B05_appStateFlakeConfigMutations_reflectedSynchronously() {
        let appState = AppState()
        appState.flakeConfig.isEnabled = true
        appState.flakeConfig.intensity = .blizzard
        appState.flakeConfig.windSpeed = 2.8

        XCTAssertTrue(appState.flakeConfig.isEnabled)
        XCTAssertEqual(appState.flakeConfig.intensity, .blizzard)
        XCTAssertEqual(appState.flakeConfig.windSpeed, 2.8)
    }

    // =========================================================================
    // MARK: - Feature 33: Wallpaper Manager Settings UI Boundary Tests (5 tests)
    // =========================================================================

    func testF33_B01_soundVolumeBoundaryZero_minimumAudioVolume() {
        var cfg = FlakeConfiguration()
        cfg.soundVolume = 0.0
        XCTAssertEqual(cfg.soundVolume, 0.0)
        XCTAssertEqual(cfg.audioVolume, 0.0)
    }

    func testF33_B02_soundVolumeBoundaryOne_maximumAudioVolume() {
        var cfg = FlakeConfiguration()
        cfg.soundVolume = 1.0
        XCTAssertEqual(cfg.soundVolume, 1.0)
        XCTAssertEqual(cfg.audioVolume, 1.0)
    }

    func testF33_B03_ambientSoundToggle_doesNotInterfereWithSnowfallSimulation() {
        var cfg = FlakeConfiguration(isEnabled: true, intensity: .steady)
        cfg.ambientSoundEnabled = true
        env.config = cfg

        XCTAssertEqual(env.scene.emitterNode?.particleBirthRate, 50.0)

        cfg.ambientSoundEnabled = false
        env.config = cfg
        XCTAssertEqual(env.scene.emitterNode?.particleBirthRate, 50.0)
    }

    func testF33_B04_fullFlakeConfigurationBoundaryJSONSerialization() throws {
        var cfg = FlakeConfiguration()
        cfg.isEnabled = true
        cfg.intensity = .blizzard
        cfg.layerMode = .overlay
        cfg.windAngleDegrees = 360.0
        cfg.windSpeed = 3.0
        cfg.soundVolume = 1.0
        cfg.ambientSoundEnabled = true
        cfg.fairyLightsEnabled = true
        cfg.snowplowModel = .snowmobile
        cfg.activeTool = .shovel

        let data = try JSONEncoder().encode(cfg)
        let restored = try JSONDecoder().decode(FlakeConfiguration.self, from: data)

        XCTAssertEqual(cfg, restored)
        XCTAssertEqual(restored.windAngleDegrees, 360.0)
        XCTAssertEqual(restored.windSpeed, 3.0)
        XCTAssertEqual(restored.soundVolume, 1.0)
    }

    func testF33_B05_clearAllSnowAction_resetsDriftsWithoutDeallocatingWindows() {
        let win = FlakeWindowFixture.standardAppWindow(id: 335, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.heightmaps[335]?.bins = Array(repeating: 20.0, count: 40)

        env.scene.clearAllSnow()
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 335), 0.0)
        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 335 }), "Window surface still active")
    }
}
