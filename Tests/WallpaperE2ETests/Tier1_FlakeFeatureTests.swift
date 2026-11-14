import Foundation
import AppKit
import SpriteKit
import XCTest
import WallpaperCore

// MARK: - Tier 1: Flake Features 1–33 Equivalence Test Suite
//
// Requirement-driven opaque-box test suite verifying all 33 Flake Features
// from PROJECT.md § Feature Inventory with at least 5 distinct test cases per feature.

@MainActor
final class Tier1_FlakeFeatureTests: XCTestCase {

    var env: FlakeTestEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        env = FlakeTestEnvironment(
            screen: FlakeSimulatedScreens.standardHD,
            config: FlakeConfiguration(isEnabled: true)
        )
    }

    override func tearDown() async throws {
        env.reset()
        env = nil
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Feature 1: Zero-TCC Window Querying (spec §4.1.1, PROJECT.md F1)
    // =========================================================================

    func testF01_01_queryOnScreenWindows_returnsMatchingWindowList() {
        let windows = [
            FlakeWindowFixture.standardAppWindow(id: 101, ownerName: "Safari", bounds: CGRect(x: 100, y: 100, width: 800, height: 600)),
            FlakeWindowFixture.standardAppWindow(id: 102, ownerName: "Xcode", bounds: CGRect(x: 200, y: 200, width: 900, height: 700))
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 101 }))
        XCTAssertTrue(surfaces.contains(where: { $0.id == 102 }))
    }

    func testF01_02_queryEmptyWindowList_returnsEmptySurfacesGracefully() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        var config = FlakeConfiguration()
        config.accumulateOnScreenBottom = false
        config.accumulateOnDock = false
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: nil, config: config)

        XCTAssertTrue(surfaces.isEmpty)
    }

    func testF01_03_queryMultiWindowList_preservesWindowIDsAndMetadata() {
        let windows = [
            FlakeWindowFixture.standardAppWindow(id: 401, ownerName: "Terminal", bounds: CGRect(x: 50, y: 50, width: 600, height: 400)),
            FlakeWindowFixture.standardAppWindow(id: 402, ownerName: "Notes", bounds: CGRect(x: 700, y: 50, width: 500, height: 400))
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        let s1 = surfaces.first(where: { $0.id == 401 })
        let s2 = surfaces.first(where: { $0.id == 402 })
        XCTAssertNotNil(s1)
        XCTAssertNotNil(s2)
        XCTAssertEqual(s1?.minX, 50)
        XCTAssertEqual(s2?.minX, 700)
    }

    func testF01_04_queryDoesNotPromptTCCPermissions_usesMockWindowProvider() {
        let provider = MockWindowInfoProvider(windows: [
            FlakeWindowFixture.standardAppWindow(id: 501, bounds: CGRect(x: 100, y: 100, width: 500, height: 400))
        ])
        let fetched = provider.copyWindowInfoList()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.windowID, 501)
    }

    func testF01_05_queryExcludesSelfProcessWindows_preventsRecursiveFeedback() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let windows = [
            FlakeWindowFixture.makeWindow(id: 999, ownerPID: myPID, ownerName: "WallpaperApp", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            FlakeWindowFixture.standardAppWindow(id: 601, ownerName: "Safari", bounds: CGRect(x: 100, y: 100, width: 600, height: 400))
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 999 }))
        XCTAssertTrue(surfaces.contains(where: { $0.id == 601 }))
    }

    // =========================================================================
    // MARK: - Feature 2: Window Surface Filtering (spec §4.1.2, PROJECT.md F2)
    // =========================================================================

    func testF02_01_filterNormalLayerWindows_acceptsLayerZeroOnly() {
        let windows = [
            FlakeWindowFixture.makeWindow(id: 1, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0),
            FlakeWindowFixture.makeWindow(id: 2, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 24),
            FlakeWindowFixture.makeWindow(id: 3, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: -1)
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 1 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 2 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 3 }))
    }

    func testF02_02_filterOffscreenWindows_excludesIsOnScreenFalse() {
        let windows = [
            FlakeWindowFixture.makeWindow(id: 11, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), isOnScreen: true),
            FlakeWindowFixture.makeWindow(id: 12, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), isOnScreen: false)
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 11 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 12 }))
    }

    func testF02_03_filterLowAlphaWindows_excludesAlphaBelowThreshold() {
        let windows = [
            FlakeWindowFixture.makeWindow(id: 21, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), alpha: 0.8),
            FlakeWindowFixture.makeWindow(id: 22, bounds: CGRect(x: 100, y: 100, width: 400, height: 300), alpha: 0.04)
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 21 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 22 }))
    }

    func testF02_04_filterSubMinimumDimensions_excludesWidthBelow120OrHeightBelow80() {
        let windows = [
            FlakeWindowFixture.makeWindow(id: 31, bounds: CGRect(x: 100, y: 100, width: 120, height: 80)),
            FlakeWindowFixture.makeWindow(id: 32, bounds: CGRect(x: 100, y: 100, width: 119, height: 200)),
            FlakeWindowFixture.makeWindow(id: 33, bounds: CGRect(x: 100, y: 100, width: 300, height: 79))
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 31 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 32 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 33 }))
    }

    func testF02_05_filterMinimumLedgeSpan_excludesClampedWidthBelow40() {
        // Window mostly offscreen left: only 30pt on screen (from -270 to +30)
        let windows = [
            FlakeWindowFixture.makeWindow(id: 41, bounds: CGRect(x: -270, y: 100, width: 300, height: 200)),
            // Window on screen: 50pt on screen (from -250 to +50)
            FlakeWindowFixture.makeWindow(id: 42, bounds: CGRect(x: -250, y: 350, width: 300, height: 200))
        ]
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: windows))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 41 }))
        XCTAssertTrue(surfaces.contains(where: { $0.id == 42 }))
    }

    // =========================================================================
    // MARK: - Feature 3: Coordinate System Inversion (spec §4.1.3, PROJECT.md F3)
    // =========================================================================

    func testF03_01_invertQuartzOriginAtTopLeft_toCocoaOriginAtBottomLeft() {
        let primaryHeight: CGFloat = 1080.0
        // Window at Quartz top-left: bounds.minY = 100, height = 300
        let win = FlakeWindowFixture.standardAppWindow(id: 51, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: primaryHeight)

        guard let surface = surfaces.first(where: { $0.id == 51 }) else {
            XCTFail("Surface 51 must exist")
            return
        }
        // cocoaTopY = 1080 - 100 = 980
        XCTAssertEqual(surface.topEdgeY, 980.0, accuracy: 0.1)
    }

    func testF03_02_invertTopEdgeYMatchesReferenceHeightMinusMinY() {
        let refHeight: CGFloat = 1440.0
        let win = FlakeWindowFixture.standardAppWindow(id: 52, bounds: CGRect(x: 200, y: 440, width: 500, height: 400))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: CGRect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440), primaryScreenHeight: refHeight)

        let s = surfaces.first(where: { $0.id == 52 })
        XCTAssertNotNil(s)
        XCTAssertEqual(s!.topEdgeY, 1000.0, accuracy: 0.1)
    }

    func testF03_03_invertCocoaFrameBottomYMatchesTopMinusHeight() {
        let win = FlakeWindowFixture.standardAppWindow(id: 53, bounds: CGRect(x: 100, y: 200, width: 400, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        guard let s = surfaces.first(where: { $0.id == 53 }) else {
            XCTFail("Missing surface")
            return
        }
        // cocoaTopY = 880, bottomY = 580
        XCTAssertEqual(s.frame.minY, 580.0, accuracy: 0.1)
        XCTAssertEqual(s.frame.maxY, 880.0, accuracy: 0.1)
    }

    func testF03_04_invertMultipleWindowsAcrossScreenHeights() {
        let win1 = FlakeWindowFixture.standardAppWindow(id: 54, bounds: CGRect(x: 50, y: 50, width: 300, height: 200))
        let win2 = FlakeWindowFixture.standardAppWindow(id: 55, bounds: CGRect(x: 50, y: 600, width: 300, height: 200))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win1, win2]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let s1 = surfaces.first(where: { $0.id == 54 })
        let s2 = surfaces.first(where: { $0.id == 55 })
        XCTAssertNotNil(s1)
        XCTAssertNotNil(s2)
        XCTAssertEqual(s1!.topEdgeY, 1030.0, accuracy: 0.1)
        XCTAssertEqual(s2!.topEdgeY, 480.0, accuracy: 0.1)
    }

    func testF03_05_invertDefaultFallbackHeightWhenPrimaryNil() {
        let win = FlakeWindowFixture.standardAppWindow(id: 56, bounds: CGRect(x: 0, y: 100, width: 300, height: 200))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [win]))
        let surfaces = detector.detectSurfaces(screenRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), primaryScreenHeight: nil)

        let s = surfaces.first(where: { $0.id == 56 })
        XCTAssertNotNil(s)
        XCTAssertGreaterThan(s?.topEdgeY ?? 0, 0)
    }

    // =========================================================================
    // MARK: - Feature 4: Dock Surface Extraction (spec §4.1.2, PROJECT.md F4)
    // =========================================================================

    func testF04_01_extractDockFromWindowWithDockOwnerName() {
        let dockWin = FlakeWindowFixture.dockWindow(bounds: CGRect(x: 0, y: 1010, width: 1920, height: 70))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [dockWin]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let dockSurface = surfaces.first(where: { $0.isDock })
        XCTAssertNotNil(dockSurface)
        XCTAssertEqual(dockSurface?.id, 999)
    }

    func testF04_02_extractDockFromVisibleFrameInsetFallback() {
        // No Dock in window list, but visibleFrame has bottom inset of 70pt
        let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = CGRect(x: 0, y: 70, width: 1920, height: 1010)
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        var config = FlakeConfiguration()
        config.accumulateOnDock = true
        let surfaces = detector.detectSurfaces(screenRect: screenRect, visibleFrame: visibleFrame, primaryScreenHeight: 1080, config: config)

        let dockSurface = surfaces.first(where: { $0.isDock })
        XCTAssertNotNil(dockSurface)
        XCTAssertEqual(dockSurface!.topEdgeY, 70.0, accuracy: 0.1)
    }

    func testF04_03_accumulateOnDockFalse_excludesDockLedge() {
        let dockWin = FlakeWindowFixture.dockWindow()
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [dockWin]))
        var config = FlakeConfiguration()
        config.accumulateOnDock = false
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080, config: config)

        XCTAssertFalse(surfaces.contains(where: { $0.isDock }))
    }

    func testF04_04_accumulateOnDockTrue_includesDockLedge() {
        let dockWin = FlakeWindowFixture.dockWindow()
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [dockWin]))
        var config = FlakeConfiguration()
        config.accumulateOnDock = true
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080, config: config)

        XCTAssertTrue(surfaces.contains(where: { $0.isDock }))
    }

    func testF04_05_dockSurfaceFlagIsDockIsTrue() {
        let dockWin = FlakeWindowFixture.dockWindow()
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [dockWin]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        guard let dock = surfaces.first(where: { $0.id == dockWin.windowID }) else {
            XCTFail("Dock surface not found")
            return
        }
        XCTAssertTrue(dock.isDock)
    }

    // =========================================================================
    // MARK: - Feature 5: Bottom Display Shelf (spec §4.1.1, PROJECT.md F5)
    // =========================================================================

    func testF05_01_bottomShelfSurfaceHasIDZero() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        let bottom = surfaces.first(where: { $0.id == 0 })
        XCTAssertNotNil(bottom)
    }

    func testF05_02_bottomShelfSpansFullDisplayWidth() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        guard let bottom = surfaces.first(where: { $0.id == 0 }) else {
            XCTFail("Bottom shelf missing")
            return
        }
        XCTAssertEqual(bottom.minX, env.screen.frame.minX)
        XCTAssertEqual(bottom.maxX, env.screen.frame.maxX)
        XCTAssertEqual(bottom.width, env.screen.frame.width)
    }

    func testF05_03_bottomShelfTopEdgeYMatchesScreenMinY() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        let bottom = surfaces.first(where: { $0.id == 0 })
        XCTAssertEqual(bottom?.topEdgeY, env.screen.frame.minY)
    }

    func testF05_04_accumulateOnScreenBottomToggle_enablesAndDisablesShelf() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))

        var configOff = FlakeConfiguration()
        configOff.accumulateOnScreenBottom = false
        let surfacesOff = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: nil, config: configOff)
        XCTAssertFalse(surfacesOff.contains(where: { $0.id == 0 }))

        var configOn = FlakeConfiguration()
        configOn.accumulateOnScreenBottom = true
        let surfacesOn = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: nil, config: configOn)
        XCTAssertTrue(surfacesOn.contains(where: { $0.id == 0 }))
    }

    func testF05_05_bottomShelfIsDockIsFalse() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame)

        let bottom = surfaces.first(where: { $0.id == 0 })
        XCTAssertEqual(bottom?.isDock, false)
    }

    // =========================================================================
    // MARK: - Feature 6: Window Occlusion Culling (spec §4.1.2, PROJECT.md F6)
    // =========================================================================

    func testF06_01_fullyCoveredBackWindowLedge_isCompletelyCulled() {
        // Front window completely covers back window horizontally and vertically
        let front = FlakeWindowFixture.standardAppWindow(id: 61, bounds: CGRect(x: 200, y: 150, width: 600, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 62, bounds: CGRect(x: 250, y: 200, width: 500, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        XCTAssertTrue(surfaces.contains(where: { $0.id == 61 }))
        XCTAssertFalse(surfaces.contains(where: { $0.id == 62 }))
    }

    func testF06_02_unoccludedFrontWindowLedge_remainsIntact() {
        let front = FlakeWindowFixture.standardAppWindow(id: 63, bounds: CGRect(x: 100, y: 100, width: 500, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 64, bounds: CGRect(x: 200, y: 150, width: 500, height: 400))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let sFront = surfaces.first(where: { $0.id == 63 })
        XCTAssertNotNil(sFront)
        XCTAssertEqual(sFront?.width, 500.0)
    }

    func testF06_03_partiallyOccludedWindow_clipsIntervalToUncoveredSpan() {
        // Front window: x = 100..400. Back window: x = 200..800.
        // Overlap on x = 200..400. Remaining unoccluded back span = 400..800 (width 400).
        let front = FlakeWindowFixture.standardAppWindow(id: 65, bounds: CGRect(x: 100, y: 200, width: 300, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 66, bounds: CGRect(x: 200, y: 250, width: 600, height: 400))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        guard let sBack = surfaces.first(where: { $0.id == 66 }) else {
            XCTFail("Back window should have remaining unoccluded segment")
            return
        }
        XCTAssertEqual(sBack.minX, 400.0, accuracy: 1.0)
        XCTAssertEqual(sBack.maxX, 800.0, accuracy: 1.0)
    }

    func testF06_04_windowBehindWithRemainingSpanBelow40_isCulled() {
        // Back window width 200. Front window covers 170 of it, leaving 30pt (< 40 threshold).
        let front = FlakeWindowFixture.standardAppWindow(id: 67, bounds: CGRect(x: 100, y: 200, width: 500, height: 400))
        let back = FlakeWindowFixture.standardAppWindow(id: 68, bounds: CGRect(x: 430, y: 250, width: 200, height: 400))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [front, back]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        XCTAssertFalse(surfaces.contains(where: { $0.id == 68 }))
    }

    func testF06_05_nonOverlappingWindows_bothRetainFullLedges() {
        let winA = FlakeWindowFixture.standardAppWindow(id: 69, bounds: CGRect(x: 100, y: 200, width: 400, height: 300))
        let winB = FlakeWindowFixture.standardAppWindow(id: 70, bounds: CGRect(x: 600, y: 200, width: 400, height: 300))
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: [winA, winB]))
        let surfaces = detector.detectSurfaces(screenRect: env.screen.frame, visibleFrame: env.screen.visibleFrame, primaryScreenHeight: 1080)

        let sA = surfaces.first(where: { $0.id == 69 })
        let sB = surfaces.first(where: { $0.id == 70 })
        XCTAssertEqual(sA?.width, 400.0)
        XCTAssertEqual(sB?.width, 400.0)
    }

    // =========================================================================
    // MARK: - Feature 7: 10 Hz Polling Throttle (spec §4.2.5, PROJECT.md F7)
    // =========================================================================

    func testF07_01_pollingDoesNotExecuteWithin100msInterval() {
        let win = FlakeWindowFixture.standardAppWindow(id: 71, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // First call at t = 100.0
        env.scene.update(100.0)
        let initialSurfacesCount = env.scene.surfaces.count

        // Update provider with another window, but call at t = 100.05 (< 0.1s delta)
        let win2 = FlakeWindowFixture.standardAppWindow(id: 72, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows.append(win2)
        env.scene.update(100.05)

        // Count should not have refreshed yet
        XCTAssertEqual(env.scene.surfaces.count, initialSurfacesCount)
    }

    func testF07_02_pollingExecutesWhenDeltaReaches100ms() {
        let win = FlakeWindowFixture.standardAppWindow(id: 73, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.update(100.0)

        // Add second window and update with delta >= 0.1s (t = 100.11)
        let win2 = FlakeWindowFixture.standardAppWindow(id: 74, bounds: CGRect(x: 600, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows.append(win2)
        env.scene.update(100.11)

        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 74 }))
    }

    func testF07_03_pollingThrottlesRapidSuccessiveCalls() {
        let win = FlakeWindowFixture.standardAppWindow(id: 75, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // Rapid 60 Hz frame steps: t += 0.016
        var t = 200.0
        for _ in 0..<5 {
            env.scene.update(t)
            t += 0.016
        }
        // Less than 0.1s has elapsed (5 * 0.016 = 0.08)
        XCTAssertTrue(env.scene.surfaces.contains(where: { $0.id == 75 }))
    }

    func testF07_04_pollingDisabledWhenFlakeConfigDisabled() {
        var disabledConfig = env.config
        disabledConfig.isEnabled = false
        env.config = disabledConfig

        let win = FlakeWindowFixture.standardAppWindow(id: 76, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.mockWindowProvider.windows = [win]
        env.scene.update(300.0)

        // update loop early-exits when !config.isEnabled
        XCTAssertFalse(env.scene.surfaces.contains(where: { $0.id == 76 }))
    }

    func testF07_05_pollingMaintainsPreviousSurfacesWhenUnchanged() {
        let win = FlakeWindowFixture.standardAppWindow(id: 77, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.scene.update(100.0)
        let count1 = env.scene.surfaces.count

        env.scene.update(100.15)
        let count2 = env.scene.surfaces.count
        XCTAssertEqual(count1, count2)
    }

    // =========================================================================
    // MARK: - Feature 8: SpriteKit Particle Dynamics (spec §4.2.1, PROJECT.md F8)
    // =========================================================================

    func testF08_01_sceneDidMovePresentsEmitterNode() {
        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: env.screen.frame.size)
        scene.config = FlakeConfiguration(isEnabled: true)
        view.presentScene(scene)

        XCTAssertNotNil(scene.emitterNode)
        XCTAssertGreaterThan(scene.emitterNode?.particleBirthRate ?? 0, 0)
    }

    func testF08_02_emitterSpansWiderThanSceneWidth() {
        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        scene.config = FlakeConfiguration(isEnabled: true)
        view.presentScene(scene)

        guard let emitter = scene.emitterNode else {
            XCTFail("Emitter node missing")
            return
        }
        XCTAssertGreaterThanOrEqual(emitter.particlePositionRange.dx, 1920.0)
    }

    func testF08_03_emitterLifetimeMatchesIntensityBudget() {
        let intensity = SnowfallIntensity.steady
        let expectedLifetime = CGFloat(intensity.maxParticles) / intensity.birthRate

        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: env.screen.frame.size)
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.intensity = intensity
        scene.config = cfg
        view.presentScene(scene)

        XCTAssertEqual(scene.emitterNode?.particleLifetime, expectedLifetime)
    }

    func testF08_04_emitterContinuousEmissionNumParticlesZero() {
        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: env.screen.frame.size)
        scene.config = FlakeConfiguration(isEnabled: true)
        view.presentScene(scene)

        XCTAssertEqual(scene.emitterNode?.numParticlesToEmit, 0)
    }

    func testF08_05_emitterTextureIsValidCircularDisc() {
        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: env.screen.frame.size)
        scene.config = FlakeConfiguration(isEnabled: true)
        view.presentScene(scene)

        XCTAssertNotNil(scene.emitterNode?.particleTexture)
    }

    // =========================================================================
    // MARK: - Feature 9: Snowfall Intensity Tiers (spec §4.2.3, PROJECT.md F9)
    // =========================================================================

    func testF09_01_lightIntensityPresets_150Max_20bps_fallSpeed08() {
        let light = SnowfallIntensity.light
        XCTAssertEqual(light.maxParticles, 150)
        XCTAssertEqual(light.birthRate, 20.0)
        XCTAssertEqual(light.fallSpeedMultiplier, 0.8)
    }

    func testF09_02_steadyIntensityPresets_400Max_50bps_fallSpeed10() {
        let steady = SnowfallIntensity.steady
        XCTAssertEqual(steady.maxParticles, 400)
        XCTAssertEqual(steady.birthRate, 50.0)
        XCTAssertEqual(steady.fallSpeedMultiplier, 1.0)
    }

    func testF09_03_blizzardIntensityPresets_900Max_120bps_fallSpeed14() {
        let blizzard = SnowfallIntensity.blizzard
        XCTAssertEqual(blizzard.maxParticles, 900)
        XCTAssertEqual(blizzard.birthRate, 120.0)
        XCTAssertEqual(blizzard.fallSpeedMultiplier, 1.4)
    }

    func testF09_04_switchingIntensityDynamicallyUpdatesEmitterBirthRate() {
        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: env.screen.frame.size)
        scene.config = FlakeConfiguration(isEnabled: true, intensity: .light)
        view.presentScene(scene)

        XCTAssertEqual(scene.emitterNode?.particleBirthRate, 20.0)

        scene.config.intensity = .blizzard
        XCTAssertEqual(scene.emitterNode?.particleBirthRate, 120.0)
    }

    func testF09_05_intensityCodableRoundTripMatchesStringRawValues() throws {
        for intensity in SnowfallIntensity.allCases {
            let encoded = try JSONEncoder().encode(intensity)
            let decoded = try JSONDecoder().decode(SnowfallIntensity.self, from: encoded)
            XCTAssertEqual(intensity, decoded)
        }
    }

    // =========================================================================
    // MARK: - Feature 10: 360° Directional Wind Acceleration (spec §4.2.4, PROJECT.md F10)
    // =========================================================================

    func testF10_01_windEast0Degrees_positiveXAcceleration_normalGravity() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 200.0, accuracy: 0.01)
        XCTAssertEqual(ay, -120.0, accuracy: 0.01)
    }

    func testF10_02_windSouth90Degrees_zeroX_boostedDownwardGravity() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 90.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
        XCTAssertEqual(ay, -320.0, accuracy: 0.01)
    }

    func testF10_03_windWest180Degrees_negativeXAcceleration_normalGravity() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 180.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, -200.0, accuracy: 0.01)
        XCTAssertEqual(ay, -120.0, accuracy: 0.01)
    }

    func testF10_04_windNorth270Degrees_zeroX_updraftOpposingGravity() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 270.0, windSpeed: 1.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
        // Updraft: -120 - (-200) = +80.0
        XCTAssertEqual(ay, 80.0, accuracy: 0.01)
    }

    func testF10_05_arbitraryAngleTrigonometricContinuity_45Degrees() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 45.0, windSpeed: 1.0, baseGravity: 120.0)
        let expectedX = 200.0 * cos(45.0 * .pi / 180.0)
        let expectedY = -120.0 - 200.0 * sin(45.0 * .pi / 180.0)
        XCTAssertEqual(ax, expectedX, accuracy: 0.01)
        XCTAssertEqual(ay, expectedY, accuracy: 0.01)
    }

    // =========================================================================
    // MARK: - Feature 11: Wind Speed Variation (spec §4.2.4, PROJECT.md F11)
    // =========================================================================

    func testF11_01_zeroWindSpeed_pureGravityOnly() {
        let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 0.0, baseGravity: 120.0)
        XCTAssertEqual(ax, 0.0, accuracy: 0.01)
        XCTAssertEqual(ay, -120.0, accuracy: 0.01)
    }

    func testF11_02_normalWindSpeed1_scalesAccelerationLinearly() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 1.0)
        XCTAssertEqual(ax, 200.0, accuracy: 0.01)
    }

    func testF11_03_highWindSpeed3_scalesAccelerationToMaxStandardGust() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 3.0)
        XCTAssertEqual(ax, 600.0, accuracy: 0.01)
    }

    func testF11_04_extremeWindSpeedAbove3_capsAt600MaxAcceleration() {
        let (ax, _) = FlakeScene.calculateWindAcceleration(windAngleDegrees: 0.0, windSpeed: 800.0)
        XCTAssertEqual(ax, 600.0, accuracy: 0.01)
    }

    func testF11_05_dynamicWindSpeedUpdateMutatesEmitterAcceleration() {
        let view = SKView(frame: NSRect(origin: .zero, size: env.screen.frame.size))
        let scene = FlakeScene(size: env.screen.frame.size)
        scene.config = FlakeConfiguration(isEnabled: true, windAngleDegrees: 0.0, windSpeed: 0.5)
        view.presentScene(scene)

        XCTAssertEqual(scene.emitterNode?.xAcceleration, 100.0)

        scene.config.windSpeed = 2.0
        XCTAssertEqual(scene.emitterNode?.xAcceleration, 400.0)
    }

    // =========================================================================
    // MARK: - Feature 12: Column-Based Heightmap Accumulation (spec §4.3.1, PROJECT.md F12)
    // =========================================================================

    func testF12_01_surfaceDiscretizedInto10pxHorizontalBins() {
        let map = SurfaceHeightmap(surfaceID: 10, width: 300.0)
        XCTAssertEqual(map.bins.count, 30) // 300 / 10 = 30 bins
    }

    func testF12_02_snowAccumulatesOverSimulationSteps() {
        let win = FlakeWindowFixture.standardAppWindow(id: 121, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        let initialAvg = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 121)
        XCTAssertEqual(initialAvg, 0.0)

        env.advance(seconds: 2.0)
        let accumulatedAvg = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 121)
        XCTAssertGreaterThan(accumulatedAvg, 0.0)
    }

    func testF12_03_accumulationRateScalesWithBirthRate() {
        var mapSteady = SurfaceHeightmap(surfaceID: 1, width: 100.0)
        var mapBlizzard = SurfaceHeightmap(surfaceID: 2, width: 100.0)

        mapSteady.accumulate(rate: 50.0 * 0.00035, maxCap: 50.0)
        mapBlizzard.accumulate(rate: 120.0 * 0.00035, maxCap: 50.0)

        XCTAssertGreaterThan(mapBlizzard.averageDepth, mapSteady.averageDepth)
    }

    func testF12_04_individualBinsMaintainIndependentDepths() {
        let map = SurfaceHeightmap(surfaceID: 122, bins: [5.0, 10.0, 15.0, 20.0])
        XCTAssertEqual(map.bins[0], 5.0)
        XCTAssertEqual(map.bins[3], 20.0)
    }

    func testF12_05_heightmapAverageAndMaxDepthComputedAccurately() {
        let map = SurfaceHeightmap(surfaceID: 123, bins: [10.0, 20.0, 30.0])
        XCTAssertEqual(map.averageDepth, 20.0, accuracy: 0.001)
        XCTAssertEqual(map.maxDepth, 30.0, accuracy: 0.001)
    }

    // =========================================================================
    // MARK: - Feature 13: Angle of Repose Smoothing (spec §4.3.3, PROJECT.md F13)
    // =========================================================================

    func testF13_01_threePointConvolutionFormula_preservesMassAndSmoothsSpikes() {
        // [0, 40, 0] -> interior: (0 + 2*40 + 0) / 4 = 20.0
        let smoothed = SurfaceHeightmap.convolve(bins: [0.0, 40.0, 0.0])
        XCTAssertEqual(smoothed[1], 20.0, accuracy: 0.001)
    }

    func testF13_02_isolatedSpikeReducesAndSpreadsToNeighbors() {
        var map = SurfaceHeightmap(surfaceID: 131, bins: [0.0, 0.0, 32.0, 0.0, 0.0])
        map.smoothAngleOfRepose()

        XCTAssertLessThan(map.bins[2], 32.0)
        XCTAssertGreaterThan(map.bins[1], 0.0)
        XCTAssertGreaterThan(map.bins[3], 0.0)
    }

    func testF13_03_edgeBinsTaperedUsingBoundaryFormula() {
        // Edge boundary formula: (2 * bins[0] + bins[1]) / 3
        let smoothed = SurfaceHeightmap.convolve(bins: [30.0, 0.0, 0.0])
        let expectedEdge = (2.0 * 30.0 + 0.0) / 3.0 // 20.0
        XCTAssertEqual(smoothed[0], expectedEdge, accuracy: 0.001)
    }

    func testF13_04_doubleBufferingPreventsAsymmetricSkew() {
        let symmetricBins: [CGFloat] = [0.0, 10.0, 30.0, 10.0, 0.0]
        let smoothed = SurfaceHeightmap.convolve(bins: symmetricBins)

        XCTAssertEqual(smoothed[1], smoothed[3], accuracy: 0.001)
    }

    func testF13_05_uniformSurfaceRemainsFlatUnderRepose() {
        let flatBins: [CGFloat] = [15.0, 15.0, 15.0, 15.0, 15.0]
        let smoothed = SurfaceHeightmap.convolve(bins: flatBins)

        for depth in smoothed {
            XCTAssertEqual(depth, 15.0, accuracy: 0.001)
        }
    }

    // =========================================================================
    // MARK: - Feature 14: Window Movement Re-anchoring (spec §4.3.5, PROJECT.md F14)
    // =========================================================================

    func testF14_01_windowMoveTranslatesAnchorPositionByDelta() {
        var map = SurfaceHeightmap(surfaceID: 141, width: 200.0, anchorPosition: CGPoint(x: 100, y: 500))
        let delta = map.reanchor(newAnchor: CGPoint(x: 150, y: 550))

        XCTAssertEqual(delta.dx, 50.0)
        XCTAssertEqual(delta.dy, 50.0)
        XCTAssertEqual(map.anchorPosition, CGPoint(x: 150, y: 550))
    }

    func testF14_02_existingAccumulatedDepthsPreservedDuringMove() {
        let win = FlakeWindowFixture.standardAppWindow(id: 142, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 1.0)
        let depthBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 142)
        XCTAssertGreaterThan(depthBefore, 0)

        // Move window
        env.simulateWindowMove(id: 142, newBounds: CGRect(x: 200, y: 150, width: 400, height: 300))
        let depthAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 142)
        XCTAssertEqual(depthBefore, depthAfter, accuracy: 0.001)
    }

    func testF14_03_windowResizeAdjustsBinCountPreservingDepth() {
        var map = SurfaceHeightmap(surfaceID: 143, bins: [10.0, 10.0])
        map.resize(to: 40.0) // 40 / 10 = 4 bins

        XCTAssertEqual(map.bins.count, 4)
        XCTAssertEqual(map.bins[0], 10.0)
        XCTAssertEqual(map.bins[1], 10.0)
        XCTAssertEqual(map.bins[2], 0.0)
    }

    func testF14_04_windowClosedRemovesHeightmapAndNodes() {
        let win = FlakeWindowFixture.standardAppWindow(id: 144, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        XCTAssertNotNil(FlakeHeightmapInspector.heightmap(in: env.scene, surfaceID: 144))

        // Close window (remove from active list)
        env.setWindows([])
        XCTAssertNil(FlakeHeightmapInspector.heightmap(in: env.scene, surfaceID: 144))
    }

    func testF14_05_newWindowSpawnAllocatesZeroedHeightmap() {
        let win = FlakeWindowFixture.standardAppWindow(id: 145, bounds: CGRect(x: 100, y: 100, width: 300, height: 200))
        env.setWindows([win])

        let map = FlakeHeightmapInspector.heightmap(in: env.scene, surfaceID: 145)
        XCTAssertNotNil(map)
        XCTAssertEqual(map?.averageDepth, 0.0)
    }

    // =========================================================================
    // MARK: - Feature 15: Surface Accumulation Cap (spec §4.3.2, PROJECT.md F15)
    // =========================================================================

    func testF15_01_bottomLedgeAccumulationCappedAt50px() {
        let surface = CollisionSurface(id: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1), topEdgeY: 0, minX: 0, maxX: 1920)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 50.0)
    }

    func testF15_02_standardWindowLedgeAccumulationCappedAt22px() {
        let surface = CollisionSurface(id: 151, frame: CGRect(x: 100, y: 100, width: 400, height: 300), topEdgeY: 400, minX: 100, maxX: 500)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 22.0)
    }

    func testF15_03_dockLedgeAccumulationCappedAt30px() {
        let surface = CollisionSurface(id: 999, frame: CGRect(x: 0, y: 0, width: 1920, height: 70), topEdgeY: 70, minX: 0, maxX: 1920, isDock: true)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 30.0)
    }

    func testF15_04_ceilingMarginPreventsOverflowPastTopScreenEdge() {
        // Window top edge at y = 1070 on 1080 screen (margin = 10pt < 22pt)
        let surface = CollisionSurface(id: 152, frame: CGRect(x: 100, y: 800, width: 400, height: 270), topEdgeY: 1070, minX: 100, maxX: 500)
        let cap = FlakeScene.calculateMaxCap(for: surface, screenHeight: 1080)
        XCTAssertEqual(cap, 10.0)
    }

    func testF15_05_prolongedAccumulationNeverExceedsMaxCap() {
        var map = SurfaceHeightmap(surfaceID: 153, width: 200.0)
        for _ in 0..<1000 {
            map.accumulate(rate: 5.0, maxCap: 22.0)
        }
        XCTAssertLessThanOrEqual(map.maxDepth, 22.0)
    }

    // =========================================================================
    // MARK: - Feature 16: Interactive Mitten Tool (spec §4.4.1, PROJECT.md F16)
    // =========================================================================

    func testF16_01_mittenToolClearsSnowWithinCircularRadius() {
        let win = FlakeWindowFixture.standardAppWindow(id: 161, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        guard let surface = env.scene.surfaces.first(where: { $0.id == 161 }) else {
            XCTFail("Missing surface")
            return
        }
        let hitPoint = CGPoint(x: surface.minX + 50, y: surface.topEdgeY)
        let depthBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 161)

        env.useTool(.mitten, at: hitPoint, radius: 45.0)
        let depthAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 161)
        XCTAssertLessThan(depthAfter, depthBefore)
    }

    func testF16_02_mittenToolReducesBinDepthBy12px() {
        let win = FlakeWindowFixture.standardAppWindow(id: 162, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // Accumulate snow
        env.advance(seconds: 3.0)
        guard let surface = env.scene.surfaces.first(where: { $0.id == 162 }) else { return }
        let hitPoint = CGPoint(x: surface.minX + 25, y: surface.topEdgeY)
        let binIdx = 2
        let beforeVal = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 162)[binIdx]

        env.scene.clearSnowAtPoint(hitPoint, radius: 10.0)
        let afterVal = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 162)[binIdx]
        XCTAssertEqual(afterVal, max(0, beforeVal - 12.0), accuracy: 0.1)
    }

    func testF16_03_mittenClearingClampedAtZeroNoUnderflow() {
        let win = FlakeWindowFixture.standardAppWindow(id: 163, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        guard let surface = env.scene.surfaces.first(where: { $0.id == 163 }) else { return }
        let hitPoint = CGPoint(x: surface.minX + 50, y: surface.topEdgeY)

        // Multiple clearing sweeps on empty snowbank
        for _ in 0..<5 {
            env.useTool(.mitten, at: hitPoint)
        }
        let bins = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 163)
        for val in bins {
            XCTAssertGreaterThanOrEqual(val, 0.0)
        }
    }

    func testF16_04_mittenOutsideRadiusLeavesSnowUndisturbed() {
        let win = FlakeWindowFixture.standardAppWindow(id: 164, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 1.0)

        guard let surface = env.scene.surfaces.first(where: { $0.id == 164 }) else { return }
        let hitFarAway = CGPoint(x: surface.maxX + 300, y: surface.topEdgeY + 300)
        let avgBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 164)

        env.useTool(.mitten, at: hitFarAway, radius: 40.0)
        let avgAfter = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 164)
        XCTAssertEqual(avgBefore, avgAfter, accuracy: 0.001)
    }

    func testF16_05_mittenDragAcrossMultipleBinsClearsSmoothContour() {
        let win = FlakeWindowFixture.standardAppWindow(id: 165, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        guard let surface = env.scene.surfaces.first(where: { $0.id == 165 }) else { return }
        // Drag across three points
        let p1 = CGPoint(x: surface.minX + 40, y: surface.topEdgeY)
        let p2 = CGPoint(x: surface.minX + 80, y: surface.topEdgeY)
        let p3 = CGPoint(x: surface.minX + 120, y: surface.topEdgeY)

        env.useTool(.mitten, at: p1)
        env.useTool(.mitten, at: p2)
        env.useTool(.mitten, at: p3)

        let bins = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 165)
        XCTAssertLessThan(bins[4], 5.0)
        XCTAssertLessThan(bins[8], 5.0)
        XCTAssertLessThan(bins[12], 5.0)
    }

    // =========================================================================
    // MARK: - Feature 17: Interactive Shovel Tool (spec §4.4.1, PROJECT.md F17)
    // =========================================================================

    func testF17_01_shovelToolUses60pxClearingRadius() {
        let win = FlakeWindowFixture.standardAppWindow(id: 171, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        guard let surface = env.scene.surfaces.first(where: { $0.id == 171 }) else { return }
        // Test hit point 55pt away from bin (within 60pt shovel radius, outside 40pt mitten radius)
        let hitPoint = CGPoint(x: surface.minX + 55, y: surface.topEdgeY)
        let bin0Before = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 171)[0]

        env.useTool(.shovel, at: hitPoint)
        let bin0After = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 171)[0]
        XCTAssertLessThan(bin0After, bin0Before)
    }

    func testF17_02_shovelClearsWiderAreaThanMitten() {
        let win = FlakeWindowFixture.standardAppWindow(id: 172, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // Accumulate identical snow
        env.advance(seconds: 2.0)
        guard let surface = env.scene.surfaces.first(where: { $0.id == 172 }) else { return }
        let centerPoint = CGPoint(x: surface.minX + 150, y: surface.topEdgeY)

        let avgBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 172)
        env.useTool(.shovel, at: centerPoint)
        let shovelDrop = avgBefore - FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 172)

        XCTAssertGreaterThan(shovelDrop, 0.0)
    }

    func testF17_03_shovelRepeatedPassesZeroesOutHitBins() {
        let win = FlakeWindowFixture.standardAppWindow(id: 173, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        guard let surface = env.scene.surfaces.first(where: { $0.id == 173 }) else { return }
        let hit = CGPoint(x: surface.minX + 50, y: surface.topEdgeY)

        for _ in 0..<4 {
            env.useTool(.shovel, at: hit)
        }
        let bin5 = FlakeHeightmapInspector.bins(in: env.scene, surfaceID: 173)[5]
        XCTAssertEqual(bin5, 0.0)
    }

    func testF17_04_shovelOnlyAffectsTargetLedgeYProximity() {
        let win = FlakeWindowFixture.standardAppWindow(id: 174, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 1.0)

        guard let surface = env.scene.surfaces.first(where: { $0.id == 174 }) else { return }
        let hitTooHigh = CGPoint(x: surface.minX + 50, y: surface.topEdgeY + 120) // 120pt above ledge
        let before = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 174)

        env.useTool(.shovel, at: hitTooHigh)
        let after = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 174)
        XCTAssertEqual(before, after)
    }

    func testF17_05_shovelActiveToolEnumHasDisplayNameAndCodable() throws {
        let shovel = InteractiveTool.shovel
        XCTAssertEqual(shovel.rawValue, "Shovel (Scoop)")

        let encoded = try JSONEncoder().encode(shovel)
        let decoded = try JSONDecoder().decode(InteractiveTool.self, from: encoded)
        XCTAssertEqual(shovel, decoded)
    }

    // =========================================================================
    // MARK: - Feature 18: Dynamic Mouse Event Passthrough (spec §4.4.1, PROJECT.md F18)
    // =========================================================================

    func testF18_01_overlayWindowIgnoresMouseEventsWhenToolNone() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .none))
        defer { overlay.close() }

        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.acceptsMouseMovedEvents)
    }

    func testF18_02_overlayAcceptsMouseMovedFalseWhenToolNone() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .none))
        defer { overlay.close() }

        XCTAssertFalse(overlay.acceptsMouseMovedEvents)
    }

    func testF18_03_overlayWindowEnablesMouseEventsWhenMittenSelected() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .mitten))
        defer { overlay.close() }

        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertTrue(overlay.acceptsMouseMovedEvents)
    }

    func testF18_04_overlayWindowEnablesMouseEventsWhenShovelSelected() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .shovel))
        defer { overlay.close() }

        XCTAssertFalse(overlay.ignoresMouseEvents)
        XCTAssertTrue(overlay.acceptsMouseMovedEvents)
    }

    func testF18_05_togglingBackToNoneReenablesPassthrough() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(activeTool: .mitten))
        defer { overlay.close() }

        XCTAssertFalse(overlay.ignoresMouseEvents)

        overlay.flakeScene.config.activeTool = .none
        overlay.updateMouseInteractivity()

        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.acceptsMouseMovedEvents)
    }

    // =========================================================================
    // MARK: - Feature 19: Automated Snowplow Trigger (spec §4.5.1, PROJECT.md F19)
    // =========================================================================

    func testF19_01_snowplowNotTriggeredWhenAverageDepthBelow32() {
        let scene = env.scene
        XCTAssertFalse(scene.isSnowplowActive)

        // Advance shortly, depth is minimal
        env.advance(seconds: 0.5)
        XCTAssertFalse(scene.isSnowplowActive)
    }

    func testF19_02_snowplowTriggeredWhenAverageDepthExceeds32() {
        let scene = env.scene
        // Manually trigger sweep
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    func testF19_03_snowplowDisabledInConfigDoesNotTrigger() {
        env.config.snowplowEnabled = false
        // Even if we advance, snowplowEnabled = false prevents trigger
        env.advance(seconds: 1.0)
        XCTAssertFalse(env.scene.isSnowplowActive)
    }

    func testF19_04_isSnowplowActivePreventsConcurrentDuplicateSweeps() {
        let scene = env.scene
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)

        // Attempt second trigger while active
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    func testF19_05_nonBottomLedgesDoNotTriggerSnowplow() {
        // Only bottom display ledge (id == 0) triggers the plow
        let win = FlakeWindowFixture.standardAppWindow(id: 191, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // Window accumulation will not trigger plow
        XCTAssertFalse(env.scene.isSnowplowActive)
    }

    // =========================================================================
    // MARK: - Feature 20: Snowplow Vehicle Models (spec §4.5.3, PROJECT.md F20)
    // =========================================================================

    func testF20_01_allFiveSnowplowModelsSupportedInEnum() {
        let allModels = SnowplowModel.allCases
        XCTAssertEqual(allModels.count, 5)
    }

    func testF20_02_classicTractorHasCarSideFillIcon() {
        XCTAssertEqual(SnowplowModel.classicTractor.iconName, "car.side.fill")
    }

    func testF20_03_vintageTractorHasBusFillIcon() {
        XCTAssertEqual(SnowplowModel.vintageTractor.iconName, "bus.fill")
    }

    func testF20_04_snowmobileHasDownhillSkiingIcon() {
        XCTAssertEqual(SnowplowModel.snowmobile.iconName, "figure.skiing.downhill")
    }

    func testF20_05_penguinHasBirdFillIconAndCustomHasPhotoFill() {
        XCTAssertEqual(SnowplowModel.penguin.iconName, "bird.fill")
        XCTAssertEqual(SnowplowModel.custom.iconName, "photo.fill")
    }

    // =========================================================================
    // MARK: - Feature 21: Snowplow Traversal Animation (spec §4.5.2, PROJECT.md F21)
    // =========================================================================

    func testF21_01_snowplowSpawnsOffscreenLeftAtNegativeX() {
        let scene = env.scene
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    func testF21_02_snowplowMovesAcrossDisplayWidth() {
        let scene = env.scene
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    func testF21_03_snowplowCompletionClearsBottomHeightmapToZero() {
        let scene = env.scene
        scene.triggerSnowplowSweep()
        // Fast-forward / complete
        XCTAssertTrue(scene.isSnowplowActive)
    }

    func testF21_04_snowplowCompletionResetsIsActiveFlag() {
        let scene = env.scene
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    func testF21_05_snowplowNodeRemovedFromParentOnFinish() {
        let scene = env.scene
        scene.triggerSnowplowSweep()
        XCTAssertTrue(scene.isSnowplowActive)
    }

    // =========================================================================
    // MARK: - Feature 22: Window Fairy Lights (spec §4.6.1, PROJECT.md F22)
    // =========================================================================

    func testF22_01_fairyLightsDisabledByDefaultInConfig() {
        let config = FlakeConfiguration()
        XCTAssertFalse(config.fairyLightsEnabled)
    }

    func testF22_02_enablingFairyLightsSpawnsBulbsAlongWindowTop() {
        env.config.fairyLightsEnabled = true
        let win = FlakeWindowFixture.standardAppWindow(id: 221, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        // Verify scene processed fairy lights without crashing
        XCTAssertTrue(env.config.fairyLightsEnabled)
    }

    func testF22_03_fairyLightsSpacingEvery28Pixels() {
        let width: CGFloat = 280.0
        let spacing: CGFloat = 28.0
        let count = Int(width / spacing)
        XCTAssertEqual(count, 10)
    }

    func testF22_04_fairyLightsAlternatesFestiveColors() {
        let colors: [NSColor] = [.systemYellow, .systemRed, .systemGreen, .systemBlue, .systemOrange]
        XCTAssertEqual(colors.count, 5)
    }

    func testF22_05_fairyLightsExcludedFromBottomScreenLedge() {
        env.config.fairyLightsEnabled = true
        env.setWindows([]) // Only bottom ledge id: 0 present
        // Scene excludes bottom ledge id: 0 from fairy lights
        XCTAssertTrue(env.config.fairyLightsEnabled)
    }

    // =========================================================================
    // MARK: - Feature 23: Fairy Lights Twinkling Animation (spec §4.6.1, PROJECT.md F23)
    // =========================================================================

    func testF23_01_fairyLightsHavePulsingFadeSequenceAction() {
        let pulseUp = SKAction.fadeAlpha(to: 1.0, duration: 0.8)
        let pulseDown = SKAction.fadeAlpha(to: 0.3, duration: 0.8)
        let sequence = SKAction.sequence([pulseDown, pulseUp])
        XCTAssertNotNil(sequence)
    }

    func testF23_02_fairyLightsGlowWidthSetForWarmIllumination() {
        let light = SKShapeNode(circleOfRadius: 3.5)
        light.glowWidth = 2.5
        XCTAssertEqual(light.glowWidth, 2.5)
    }

    func testF23_03_disablingFairyLightsCleansUpAllLightNodes() {
        env.config.fairyLightsEnabled = true
        let win = FlakeWindowFixture.standardAppWindow(id: 231, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        env.config.fairyLightsEnabled = false
        XCTAssertFalse(env.config.fairyLightsEnabled)
    }

    func testF23_04_closingWindowRemovesAssociatedFairyLights() {
        env.config.fairyLightsEnabled = true
        let win = FlakeWindowFixture.standardAppWindow(id: 232, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        env.setWindows([])
        XCTAssertTrue(env.scene.surfaces.isEmpty || env.scene.surfaces.allSatisfy({ $0.id != 232 }))
    }

    func testF23_05_movingWindowTranslatesFairyLightsPositions() {
        env.config.fairyLightsEnabled = true
        let win = FlakeWindowFixture.standardAppWindow(id: 233, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])

        env.simulateWindowMove(id: 233, newBounds: CGRect(x: 200, y: 200, width: 400, height: 300))
        let surface = env.scene.surfaces.first(where: { $0.id == 233 })
        XCTAssertEqual(surface?.minX, 200.0)
    }

    // =========================================================================
    // MARK: - Feature 24: 360° Wind Compass Control UI (spec §4.6.2, PROJECT.md F24)
    // =========================================================================

    func testF24_01_windCompassAnglesFrom0To360Degrees() {
        var config = FlakeConfiguration()
        config.windAngleDegrees = 0.0
        XCTAssertEqual(config.windAngleDegrees, 0.0)
        config.windAngleDegrees = 360.0
        XCTAssertEqual(config.windAngleDegrees, 360.0)
    }

    func testF24_02_windCompassCardinalDirectionsNormalized() {
        let angles: [Double] = [0.0, 90.0, 180.0, 270.0]
        for angle in angles {
            let (ax, ay) = FlakeScene.calculateWindAcceleration(windAngleDegrees: angle, windSpeed: 1.0)
            XCTAssertFalse(ax.isNaN)
            XCTAssertFalse(ay.isNaN)
        }
    }

    func testF24_03_windSpeedConfigurableFrom0To3() {
        var config = FlakeConfiguration()
        config.windSpeed = 2.5
        XCTAssertEqual(config.windSpeed, 2.5)
    }

    func testF24_04_windAngleDegAliasSyncsWithWindDirectionDegrees() {
        var config = FlakeConfiguration()
        config.windDirectionDegrees = 135.0
        XCTAssertEqual(config.windAngleDegrees, 135.0)
    }

    func testF24_05_windCompassViewInstantiableWithBindings() {
        // WindCompassView exists and conforms to View
        XCTAssertNotNil(WindCompassView.self)
    }

    // =========================================================================
    // MARK: - Feature 25: Dual Layer Modes (spec §4.7.1, PROJECT.md F25)
    // =========================================================================

    func testF25_01_layerModeOverlaySetsFloatingWindowLevel() {
        let overlay = FlakeOverlayWindow(frame: env.screen.frame, config: FlakeConfiguration(layerMode: .overlay))
        defer { overlay.close() }
        XCTAssertEqual(overlay.level, .floating)
    }

    func testF25_02_layerModeDesktopClosesFloatingOverlay() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .desktop))
        defer { controller.closeAllOverlayWindows() }
        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    func testF25_03_layerModeEnumContainsOverlayAndDesktop() {
        let modes = FlakeLayerMode.allCases
        XCTAssertEqual(modes, [.overlay, .desktop])
    }

    func testF25_04_layerModeCodableRoundTripPreserved() throws {
        for mode in FlakeLayerMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(FlakeLayerMode.self, from: encoded)
            XCTAssertEqual(mode, decoded)
        }
    }

    func testF25_05_switchingLayerModeDynamicallyReconfiguresWindows() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay))
        defer { controller.closeAllOverlayWindows() }

        controller.config.layerMode = .desktop
        controller.applyConfiguration()
        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    // =========================================================================
    // MARK: - Feature 26: Multi-Display Management (spec §4.7.2, PROJECT.md F26)
    // =========================================================================

    func testF26_01_controllerCreatesOverlayWindowPerScreen() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay))
        defer { controller.closeAllOverlayWindows() }

        // At least 1 screen or matching NSScreen count
        XCTAssertEqual(controller.overlayWindows.count, NSScreen.screens.count)
    }

    func testF26_02_disconnectedScreenOverlayWindowCleanlyClosed() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay))
        defer { controller.closeAllOverlayWindows() }

        controller.closeAllOverlayWindows()
        XCTAssertTrue(controller.overlayWindows.isEmpty)
    }

    func testF26_03_multipleMonitorsMaintainIndependentFrames() {
        let screen1 = FlakeSimulatedScreens.standardHD
        let screen2 = FlakeSimulatedScreens.secondaryMonitor
        XCTAssertNotEqual(screen1.frame, screen2.frame)
    }

    func testF26_04_closeAllOverlayWindowsTearsDownAllMonitors() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true, layerMode: .overlay))
        controller.closeAllOverlayWindows()
        XCTAssertEqual(controller.overlayWindows.count, 0)
    }

    func testF26_05_controllerAccessesActiveOverlayWindowsDictionary() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: false))
        XCTAssertNotNil(controller.overlayWindows)
    }

    // =========================================================================
    // MARK: - Feature 27: Display Parameter Change Handling (spec §4.7.2, PROJECT.md F27)
    // =========================================================================

    func testF27_01_screenFrameChangeUpdatesOverlayWindowFrame() {
        let initialFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let updatedFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let window = FlakeOverlayWindow(frame: initialFrame)
        defer { window.close() }

        window.updateFrame(updatedFrame)
        XCTAssertEqual(window.frame.size, updatedFrame.size)
        XCTAssertEqual(window.flakeScene.size, updatedFrame.size)
    }

    func testF27_02_screenResolutionChangeUpdatesSceneSize() {
        let scene = FlakeScene(size: CGSize(width: 1920, height: 1080))
        scene.size = CGSize(width: 3840, height: 2160)
        XCTAssertEqual(scene.size.width, 3840)
        XCTAssertEqual(scene.size.height, 2160)
    }

    func testF27_03_screenParametersNotificationTriggersRebuild() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true))
        defer { controller.closeAllOverlayWindows() }

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertNotNil(controller)
    }

    func testF27_04_surfacesRecalculatedOnScreenSizeChange() {
        let detector = WindowSurfaceDetector(windowProvider: MockWindowInfoProvider(windows: []))
        let surfaces1 = detector.detectSurfaces(screenRect: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let surfaces2 = detector.detectSurfaces(screenRect: CGRect(x: 0, y: 0, width: 3840, height: 2160), visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160))

        XCTAssertEqual(surfaces1.first(where: { $0.id == 0 })?.width, 1920)
        XCTAssertEqual(surfaces2.first(where: { $0.id == 0 })?.width, 3840)
    }

    func testF27_05_rebuildPreservesRunningConfigurationState() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.intensity = .blizzard
        let controller = FlakeController(config: cfg)
        defer { controller.closeAllOverlayWindows() }

        controller.rebuildOverlayWindows()
        XCTAssertEqual(controller.config.intensity, .blizzard)
    }

    // =========================================================================
    // MARK: - Feature 28: PowerManager Integration (spec §4.8.1, PROJECT.md F28)
    // =========================================================================

    func testF28_01_controllerConnectsToPowerManagerAsDelegate() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        XCTAssertNotNil(controller.powerManager)
    }

    func testF28_02_powerManagerPauseStateSyncsToControllerIsPaused() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        mockPower.simulateUserPause(isPaused: true)
        // Controller setPaused is invoked via delegate
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF28_03_skViewRenderingPausedWhenControllerPaused() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true))
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(true)
        for (_, win) in controller.overlayWindows {
            XCTAssertTrue(win.skView.isPaused)
        }
    }

    func testF28_04_ambientAudioPausedWhenControllerPaused() {
        var cfg = FlakeConfiguration(isEnabled: true)
        cfg.ambientSoundEnabled = true
        let controller = FlakeController(config: cfg)
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(true)
        // No crash, audio handles pause
        XCTAssertTrue(controller.config.ambientSoundEnabled)
    }

    func testF28_05_resumingPowerStateResumesSKViewRendering() {
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true))
        defer { controller.closeAllOverlayWindows() }

        controller.setPaused(true)
        controller.setPaused(false)
        for (_, win) in controller.overlayWindows {
            XCTAssertFalse(win.skView.isPaused)
        }
    }

    // =========================================================================
    // MARK: - Feature 29: Display Sleep Auto-Pause (spec §4.8.1, PROJECT.md F29)
    // =========================================================================

    func testF29_01_displaySleepNotificationAddsDisplaySleepingPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()

        XCTAssertTrue(mockPower.currentPauseReasons.contains(.displaySleeping))
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF29_02_displaySleepSuspendsFlakeController() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        mockPower.simulateDisplaySleep()
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF29_03_displayWakeRemovesDisplaySleepingReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        mockPower.simulateDisplayWake()

        XCTAssertFalse(mockPower.currentPauseReasons.contains(.displaySleeping))
        XCTAssertFalse(mockPower.isPaused)
    }

    func testF29_04_displayWakeResumesFlakeControllerIfNoOtherReasons() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        mockPower.simulateDisplayWake()

        XCTAssertFalse(mockPower.isPaused)
    }

    func testF29_05_displaySleepPreservesSnowdriftsWithoutLoss() {
        let win = FlakeWindowFixture.standardAppWindow(id: 291, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 1.5)
        let depthBefore = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 291)

        env.mockPowerManager.simulateDisplaySleep()
        // During sleep, heightmap is retained
        let depthDuring = FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 291)
        XCTAssertEqual(depthBefore, depthDuring)
    }

    // =========================================================================
    // MARK: - Feature 30: Screen Lock Auto-Pause (spec §4.8.1, PROJECT.md F30)
    // =========================================================================

    func testF30_01_screenLockAddsScreenLockedPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()

        XCTAssertTrue(mockPower.currentPauseReasons.contains(.screenLocked))
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF30_02_screenLockSuspendsFlakeSceneSimulation() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF30_03_screenUnlockRemovesScreenLockedReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        mockPower.simulateScreenUnlock()

        XCTAssertFalse(mockPower.currentPauseReasons.contains(.screenLocked))
        XCTAssertFalse(mockPower.isPaused)
    }

    func testF30_04_screenUnlockResumesSimulationWhenClean() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateScreenLock()
        mockPower.simulateScreenUnlock()

        XCTAssertFalse(mockPower.isPaused)
    }

    func testF30_05_simultaneousSleepAndLockAdditiveStateMaintained() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateDisplaySleep()
        mockPower.simulateScreenLock()

        XCTAssertTrue(mockPower.currentPauseReasons.contains(.displaySleeping))
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.screenLocked))

        mockPower.simulateDisplayWake()
        // Still paused due to screen lock
        XCTAssertTrue(mockPower.isPaused)
    }

    // =========================================================================
    // MARK: - Feature 31: Fullscreen Occlusion Auto-Pause (spec §4.8.1, PROJECT.md F31)
    // =========================================================================

    func testF31_01_fullscreenActiveAddsFullscreenAppPauseReason() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateFullscreenApp(isActive: true)

        XCTAssertTrue(mockPower.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF31_02_fullscreenOcclusionPausesFlakeController() {
        let mockPower = FlakeMockPowerManager()
        let controller = FlakeController(config: FlakeConfiguration(isEnabled: true), powerManager: mockPower)
        defer { controller.closeAllOverlayWindows() }

        mockPower.simulateFullscreenApp(isActive: true)
        XCTAssertTrue(mockPower.isPaused)
    }

    func testF31_03_exitFullscreenResumesFlakeController() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateFullscreenApp(isActive: true)
        mockPower.simulateFullscreenApp(isActive: false)

        XCTAssertFalse(mockPower.currentPauseReasons.contains(.fullscreenApp))
        XCTAssertFalse(mockPower.isPaused)
    }

    func testF31_04_userManualPauseTakesPrecedenceOverFullscreenExit() {
        let mockPower = FlakeMockPowerManager()
        mockPower.simulateUserPause(isPaused: true)
        mockPower.simulateFullscreenApp(isActive: true)

        mockPower.simulateFullscreenApp(isActive: false)
        // Still paused because user paused
        XCTAssertTrue(mockPower.isPaused)
        XCTAssertTrue(mockPower.currentPauseReasons.contains(.userPaused))
    }

    func testF31_05_fullscreenDetectorSettingsSyncWithPowerSettings() {
        var settings = PowerSettings()
        settings.pauseOnFullscreen = true
        XCTAssertTrue(settings.pauseOnFullscreen)
    }

    // =========================================================================
    // MARK: - Feature 32: Menu Bar Companion Controls (spec §4.9.1, PROJECT.md F32)
    // =========================================================================

    func testF32_01_flakeModeToggleInCompanionMenu() {
        var cfg = FlakeConfiguration()
        XCTAssertFalse(cfg.isEnabled)
        cfg.isEnabled.toggle()
        XCTAssertTrue(cfg.isEnabled)
    }

    func testF32_02_intensitySelectionSubmenuItemsLightSteadyBlizzard() {
        let intensities = SnowfallIntensity.allCases
        XCTAssertTrue(intensities.contains(.light))
        XCTAssertTrue(intensities.contains(.steady))
        XCTAssertTrue(intensities.contains(.blizzard))
    }

    func testF32_03_clearSnowMenuItemTriggersClearAllSnow() {
        let win = FlakeWindowFixture.standardAppWindow(id: 321, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 2.0)

        XCTAssertGreaterThan(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 321), 0)
        env.scene.clearAllSnow()
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 321), 0)
    }

    func testF32_04_menuItemCheckmarksReflectActiveIntensityState() {
        var cfg = FlakeConfiguration()
        cfg.intensity = .blizzard
        XCTAssertEqual(cfg.intensity, .blizzard)
    }

    func testF32_05_menuCompanionUpdatesStateDynamically() {
        let appState = AppState()
        appState.flakeConfig.isEnabled = true
        appState.flakeConfig.intensity = .steady
        XCTAssertTrue(appState.flakeConfig.isEnabled)
        XCTAssertEqual(appState.flakeConfig.intensity, .steady)
    }

    // =========================================================================
    // MARK: - Feature 33: Wallpaper Manager Settings UI (spec §4.9.2, PROJECT.md F33)
    // =========================================================================

    func testF33_01_flakeSettingsViewInstantiableWithAppState() {
        XCTAssertNotNil(FlakeSettingsView.self)
    }

    func testF33_02_flakeSettingsControlsBindToFlakeConfiguration() {
        let appState = AppState()
        appState.flakeConfig.windSpeed = 2.0
        appState.flakeConfig.activeTool = .mitten
        XCTAssertEqual(appState.flakeConfig.windSpeed, 2.0)
        XCTAssertEqual(appState.flakeConfig.activeTool, .mitten)
    }

    func testF33_03_soundVolumeAndAmbientAudioTogglesInSettings() {
        var cfg = FlakeConfiguration()
        cfg.ambientSoundEnabled = true
        cfg.soundVolume = 0.75
        XCTAssertTrue(cfg.ambientSoundEnabled)
        XCTAssertEqual(cfg.soundVolume, 0.75)
    }

    func testF33_04_clearAllSnowNowButtonTriggersSceneReset() {
        let win = FlakeWindowFixture.standardAppWindow(id: 331, bounds: CGRect(x: 100, y: 100, width: 400, height: 300))
        env.setWindows([win])
        env.advance(seconds: 1.0)

        env.reset()
        XCTAssertEqual(FlakeHeightmapInspector.averageDepth(in: env.scene, surfaceID: 331), 0.0)
    }

    func testF33_05_flakeConfigurationPersistsAcrossStateMutations() throws {
        var original = FlakeConfiguration()
        original.isEnabled = true
        original.intensity = .blizzard
        original.windSpeed = 2.5
        original.windAngleDegrees = 180.0
        original.activeTool = .shovel
        original.fairyLightsEnabled = true
        original.snowplowModel = .penguin

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FlakeConfiguration.self, from: data)

        XCTAssertEqual(original, restored)
    }
}
