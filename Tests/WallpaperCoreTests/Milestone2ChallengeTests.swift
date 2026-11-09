import XCTest
import AppKit
import CoreGraphics
import Darwin
@testable import WallpaperCore

/// Adversarial Challenge Test Suite for Milestone 2 (Desktop Window & Passthrough Engine)
/// Stress-tests window levels, rapid mode toggling, event bombardment, boundary & negative coordinates,
/// multi-display topologies, view hierarchy nesting, volume clamping, and memory leak invariance.
@MainActor
final class Milestone2ChallengeTests: XCTestCase {

    // MARK: - Memory Measurement Helper

    private func getResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    private func makeDummyEvent(type: NSEvent.EventType = .applicationDefined, location: NSPoint = .zero) -> NSEvent {
        if let event = NSEvent.otherEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) {
            return event
        }
        fatalError("Failed to synthesize test NSEvent")
    }

    // MARK: - 1. Window Level Verification & Quartz API Conformity

    func testExactQuartzWindowLevelIntegers() {
        // Exact integer specifications
        let desktopRaw = CGWindowLevelForKey(.desktopWindow)
        let iconRaw = CGWindowLevelForKey(.desktopIconWindow)
        let interactiveRaw = iconRaw + 1

        XCTAssertEqual(desktopRaw, -2147483623, "kCGDesktopWindowLevel must evaluate to -2147483623")
        XCTAssertEqual(iconRaw, -2147483603, "kCGDesktopIconWindowLevel must evaluate to -2147483603")
        XCTAssertEqual(interactiveRaw, -2147483602, "Interactive window level must evaluate to -2147483602")

        XCTAssertEqual(DesktopWindow.defaultLevel.rawValue, -2147483623)
        XCTAssertEqual(DesktopWindow.interactiveLevel.rawValue, -2147483602)
        XCTAssertEqual(NSWindow.Level.desktop.rawValue, -2147483623)
        XCTAssertEqual(NSWindow.Level.desktopInteractive.rawValue, -2147483602)
    }

    func testWindowLevelZOrderOrderingRelations() {
        let desktopLevel = NSWindow.Level.desktop.rawValue
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let interactiveLevel = NSWindow.Level.desktopInteractive.rawValue
        let normalLevel = Int(CGWindowLevelForKey(.normalWindow))
        let floatingLevel = Int(CGWindowLevelForKey(.floatingWindow))

        XCTAssertLessThan(desktopLevel, iconLevel, "Desktop window must render strictly below Finder desktop icons")
        XCTAssertLessThan(iconLevel, interactiveLevel, "Finder desktop icons must render below interactive wallpaper")
        XCTAssertLessThan(interactiveLevel, normalLevel, "Interactive wallpaper must render strictly below normal application windows")
        XCTAssertLessThan(normalLevel, floatingLevel, "Normal windows must render below floating windows")

        XCTAssertEqual(desktopLevel, -2147483623)
        XCTAssertEqual(iconLevel, -2147483603)
        XCTAssertEqual(interactiveLevel, -2147483602)
        XCTAssertEqual(normalLevel, 0)
    }

    func testWindowLevelQuartzBridgeProperty() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        XCTAssertEqual(window.windowLevel, -2147483623)
        XCTAssertEqual(window.level.rawValue, -2147483623)

        window.isInteractive = true
        XCTAssertEqual(window.windowLevel, -2147483602)
        XCTAssertEqual(window.level.rawValue, -2147483602)

        // Directly setting Quartz windowLevel
        window.windowLevel = -2147483623
        XCTAssertEqual(window.level.rawValue, -2147483623)
    }

    // MARK: - 2. Rapid Mode Toggling & State Invariance Stress

    func testRapidModeToggling500CyclesInvariance() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        let startTime = CFAbsoluteTimeGetCurrent()

        for cycle in 1...500 {
            let targetMode = (cycle % 2 != 0) // Odd -> true, Even -> false
            window.isInteractive = targetMode

            XCTAssertEqual(window.isInteractive, targetMode, "Cycle \(cycle): isInteractive mismatch")
            XCTAssertEqual(window.ignoresMouseEvents, !targetMode, "Cycle \(cycle): ignoresMouseEvents must match !targetMode")
            let expectedLevel = targetMode ? -2147483602 : -2147483623
            XCTAssertEqual(window.level.rawValue, expectedLevel, "Cycle \(cycle): level mismatch")
            XCTAssertEqual(window.canBecomeKey, targetMode, "Cycle \(cycle): canBecomeKey mismatch")
            XCTAssertFalse(window.canBecomeMain, "Cycle \(cycle): canBecomeMain must remain false")

            if targetMode {
                XCTAssertNotNil(window.hitTest(CGPoint(x: 500, y: 500)), "Cycle \(cycle): interactive mode must hit")
            } else {
                XCTAssertNil(window.hitTest(CGPoint(x: 500, y: 500)), "Cycle \(cycle): default mode must pass through")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(elapsed, 3.0, "500 rapid mode toggles must execute within 3.0s (actual: \(elapsed)s)")
        XCTAssertFalse(window.isInteractive, "Final state after 500 toggles must be non-interactive")
    }

    func testRapidTogglingTrackingAreaNoLeak() {
        let view = PassthroughView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))

        XCTAssertEqual(view.trackingAreas.count, 0)

        for cycle in 1...200 {
            view.isInteractive = true
            XCTAssertEqual(view.trackingAreas.count, 1, "Cycle \(cycle): Must have exactly 1 active tracking area in interactive mode")

            view.isInteractive = false
            XCTAssertEqual(view.trackingAreas.count, 0, "Cycle \(cycle): Must have exactly 0 tracking areas in default mode")
        }

        XCTAssertEqual(view.trackingAreas.count, 0, "Tracking area count must strictly remain 0 without memory leakage")
    }

    func testManagerRapidInteractivityBroadcastingToMultipleDisplays() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440)),
            DisplayDescriptor(displayID: 3, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 4, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 5, frame: CGRect(x: 4480, y: 0, width: 3840, height: 2160))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 5)

        for cycle in 1...200 {
            let targetMode = (cycle % 2 != 0)
            manager.isInteractive = targetMode

            XCTAssertEqual(manager.isInteractive, targetMode)
            for (displayID, window) in manager.windows {
                XCTAssertEqual(window.isInteractive, targetMode, "Window \(displayID) mismatch on cycle \(cycle)")
                XCTAssertEqual(window.ignoresMouseEvents, !targetMode)
                XCTAssertEqual(window.level.rawValue, targetMode ? -2147483602 : -2147483623)
            }
        }
    }

    // MARK: - 3. High-Frequency Event Bombardment & Zero-Interception Invariance

    func testDefaultModeBombardment5000ClicksNeverIntercepted() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)
        let view = window.passthroughView

        var mouseEventsCaught = 0
        var keyEventsCaught = 0
        view.onMouseEvent = { _ in mouseEventsCaught += 1 }
        view.onKeyEvent = { _ in keyEventsCaught += 1 }

        let dummyEvent = makeDummyEvent()

        // Bombard with 5,000 mixed events while in default passthrough mode
        for i in 1...5000 {
            switch i % 10 {
            case 0: view.mouseDown(with: dummyEvent)
            case 1: view.mouseUp(with: dummyEvent)
            case 2: view.mouseDragged(with: dummyEvent)
            case 3: view.rightMouseDown(with: dummyEvent)
            case 4: view.rightMouseUp(with: dummyEvent)
            case 5: view.rightMouseDragged(with: dummyEvent)
            case 6: view.otherMouseDown(with: dummyEvent)
            case 7: view.mouseMoved(with: dummyEvent)
            case 8: view.scrollWheel(with: dummyEvent)
            case 9:
                view.keyDown(with: dummyEvent)
                view.keyUp(with: dummyEvent)
                view.flagsChanged(with: dummyEvent)
            default: break
            }

            // Also verify hitTest returns nil
            if i % 100 == 0 {
                let randomX = Double((i * 37) % 1920)
                let randomY = Double((i * 53) % 1080)
                XCTAssertNil(window.hitTest(CGPoint(x: randomX, y: randomY)), "Default mode must NEVER intercept clicks (query \(i))")
            }
        }

        XCTAssertEqual(mouseEventsCaught, 0, "ZERO mouse events should be intercepted in default mode")
        XCTAssertEqual(keyEventsCaught, 0, "ZERO keyboard events should be intercepted in default mode")
    }

    func testInteractiveModeBombardment5000EventsDeliveredReliably() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)
        let view = window.passthroughView

        var mouseEventsCaught = 0
        var keyEventsCaught = 0
        view.onMouseEvent = { _ in mouseEventsCaught += 1 }
        view.onKeyEvent = { _ in keyEventsCaught += 1 }

        let dummyEvent = makeDummyEvent()

        // Bombard with 5,000 mouse events
        for i in 1...5000 {
            switch i % 8 {
            case 0: view.mouseDown(with: dummyEvent)
            case 1: view.mouseUp(with: dummyEvent)
            case 2: view.mouseDragged(with: dummyEvent)
            case 3: view.rightMouseDown(with: dummyEvent)
            case 4: view.rightMouseUp(with: dummyEvent)
            case 5: view.otherMouseDown(with: dummyEvent)
            case 6: view.mouseMoved(with: dummyEvent)
            case 7: view.scrollWheel(with: dummyEvent)
            default: break
            }
        }

        XCTAssertEqual(mouseEventsCaught, 5000, "All 5,000 mouse events must be captured in interactive mode")

        // Bombard with 1,500 key events
        for _ in 1...500 {
            view.keyDown(with: dummyEvent)
            view.keyUp(with: dummyEvent)
            view.flagsChanged(with: dummyEvent)
        }

        XCTAssertEqual(keyEventsCaught, 1500, "All 1,500 keyboard events must be captured in interactive mode")
    }

    func testHitTestThroughputBenchmark() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let defaultWindow = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)
        let interactiveWindow = DesktopWindow(displayID: 2, frame: frame, isInteractive: true)

        let iterations = 10000

        // Benchmark default mode passthrough hit testing
        let startDefault = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let pt = CGPoint(x: Double(i % 1920), y: Double((i * 2) % 1080))
            _ = defaultWindow.hitTest(pt)
        }
        let elapsedDefault = CFAbsoluteTimeGetCurrent() - startDefault

        // Benchmark interactive mode hit testing
        let startInteractive = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let pt = CGPoint(x: Double(i % 1920), y: Double((i * 2) % 1080))
            _ = interactiveWindow.hitTest(pt)
        }
        let elapsedInteractive = CFAbsoluteTimeGetCurrent() - startInteractive

        // Ensure sub-millisecond per-event throughput (> 20,000 ops/sec)
        XCTAssertLessThan(elapsedDefault, 0.5, "10,000 default hit tests must take < 0.5s (actual: \(elapsedDefault)s)")
        XCTAssertLessThan(elapsedInteractive, 0.5, "10,000 interactive hit tests must take < 0.5s (actual: \(elapsedInteractive)s)")
    }

    // MARK: - 4. Boundary Coordinates, Negative Displays & Extreme Coordinate Resilience

    func testNegativeDisplayCoordinatesHitTesting() {
        // Multi-monitor arrangement with negative horizontal and vertical coordinates:
        // Screen 1: Primary (0, 0, 1920, 1080)
        // Screen 2: Left display (-1920, 0, 1920, 1080)
        // Screen 3: Far left rotated display (-3000, -500, 1080, 1920)
        // Screen 4: Bottom display (0, -1080, 1920, 1080)
        let screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 3, frame: CGRect(x: -3000, y: -500, width: 1080, height: 1920)),
            DisplayDescriptor(displayID: 4, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        manager.isInteractive = true

        let win1 = manager.windows[1]!
        let win2 = manager.windows[2]!
        let win3 = manager.windows[3]!
        let win4 = manager.windows[4]!

        // Test points strictly in Screen 2 (-1920, 0, 1920, 1080)
        let pt2 = CGPoint(x: -1000, y: 500)
        XCTAssertNotNil(win2.hitTest(pt2), "Screen 2 must hit (-1000, 500)")
        XCTAssertNil(win1.hitTest(pt2), "Screen 1 must not hit Screen 2's point")
        XCTAssertNil(win3.hitTest(pt2))
        XCTAssertNil(win4.hitTest(pt2))

        // Test points strictly in Screen 3 (-3000, -500, 1080, 1920)
        let pt3 = CGPoint(x: -2500, y: 100)
        XCTAssertNotNil(win3.hitTest(pt3), "Screen 3 must hit (-2500, 100)")
        XCTAssertNil(win1.hitTest(pt3))
        XCTAssertNil(win2.hitTest(pt3))
        XCTAssertNil(win4.hitTest(pt3))

        // Test points strictly in Screen 4 (0, -1080, 1920, 1080)
        let pt4 = CGPoint(x: 500, y: -500)
        XCTAssertNotNil(win4.hitTest(pt4), "Screen 4 must hit (500, -500)")
        XCTAssertNil(win1.hitTest(pt4))
        XCTAssertNil(win2.hitTest(pt4))
        XCTAssertNil(win3.hitTest(pt4))
    }

    func testFractionalSubpixelCoordinatesHitTesting() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)

        let fractionalPoints = [
            CGPoint(x: 0.0000001, y: 0.0000001),
            CGPoint(x: 1919.9999999, y: 1079.9999999),
            CGPoint(x: 123.4567890123, y: 789.0123456789),
            CGPoint(x: 960.5, y: 540.5)
        ]

        for pt in fractionalPoints {
            XCTAssertNotNil(window.hitTest(pt), "Fractional point \(pt) inside bounds must hit")
        }

        // Just outside bounds by epsilon
        let outsidePoints = [
            CGPoint(x: -0.0000001, y: 100),
            CGPoint(x: 100, y: -0.0000001),
            CGPoint(x: 1920.0000001, y: 500),
            CGPoint(x: 500, y: 1080.0000001)
        ]

        for pt in outsidePoints {
            XCTAssertNil(window.hitTest(pt), "Subpixel point outside bounds \(pt) must return nil")
        }
    }

    func testExtremeAndAbnormalCoordinatesResilience() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)

        let extremePoints = [
            CGPoint(x: -1_000_000, y: -1_000_000),
            CGPoint(x: 1_000_000, y: 1_000_000),
            CGPoint(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude),
            CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: 0),
            CGPoint(x: CGFloat.nan, y: CGFloat.nan),
            CGPoint(x: CGFloat.infinity, y: 0),
            CGPoint(x: 0, y: -CGFloat.infinity),
            CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity)
        ]

        for pt in extremePoints {
            // Must safely return nil without crashing, trapping, or hanging
            let hit = window.hitTest(pt)
            XCTAssertNil(hit, "Extreme/NaN/Infinity point \(pt) must return nil safely")
        }
    }

    // MARK: - 5. Multi-Display Topology Churn & Dynamic Reconfiguration

    func testMultiDisplayTopologyChurnStress() {
        let mockProvider = MockScreenProvider(screens: [])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        // Run 50 iterations of randomized screen configurations
        for cycle in 1...50 {
            let screenCount = (cycle % 5) // 0 to 4 screens
            var newScreens: [DisplayDescriptor] = []
            for s in 0..<screenCount {
                let did = CGDirectDisplayID(s + 1)
                let originX = Double((s - 1) * 1920)
                let originY = Double((cycle % 3 == 0) ? -1080 : 0)
                let width = Double(1920 + (cycle % 2) * 640)
                let height = Double(1080 + (cycle % 2) * 360)
                newScreens.append(DisplayDescriptor(
                    displayID: did,
                    frame: CGRect(x: originX, y: originY, width: width, height: height)
                ))
            }

            mockProvider.screens = newScreens
            manager.reloadDisplays()

            XCTAssertEqual(manager.windows.count, screenCount, "Cycle \(cycle): Window count must match screen count")
            for screen in newScreens {
                guard let window = manager.windows[screen.displayID] else {
                    XCTFail("Cycle \(cycle): Missing window for display \(screen.displayID)")
                    continue
                }
                XCTAssertEqual(window.frame, screen.frame, "Cycle \(cycle): Window frame mismatch for display \(screen.displayID)")
            }
        }
    }

    func testScreenNotificationRapidBroadcastStress() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        for cycle in 1...30 {
            if cycle % 2 == 0 {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
                ]
            } else {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
                ]
            }

            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }

        XCTAssertEqual(manager.windows.count, mockProvider.screens.count)
    }

    // MARK: - 6. View Hierarchy Nesting & Child View Lifecycle

    func testDeepNestedViewHierarchyHitTesting() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)

        // Build 20 levels of nested container subviews
        var currentParent: NSView = window.passthroughView
        var leafButton: NSButton?

        for depth in 1...20 {
            let container = NSView(frame: NSRect(x: 10, y: 10, width: 900 - Double(depth * 10), height: 900 - Double(depth * 10)))
            currentParent.addSubview(container)
            currentParent = container

            if depth == 20 {
                let button = NSButton(frame: NSRect(x: 50, y: 50, width: 100, height: 40))
                container.addSubview(button)
                leafButton = button
            }
        }

        XCTAssertNotNil(leafButton)

        // In interactive mode, hit testing on the button's screen coordinates must find the leaf button or container
        let buttonScreenPoint = leafButton!.convert(NSPoint(x: 20, y: 20), to: nil)
        let hit = window.hitTest(buttonScreenPoint)
        XCTAssertNotNil(hit, "Nested view hierarchy must return hit view in interactive mode")

        // Switch to default mode: whole hierarchy must be bypassed
        window.isInteractive = false
        let hitDefault = window.hitTest(buttonScreenPoint)
        XCTAssertNil(hitDefault, "Default mode must return nil even with 20 levels of subviews")
    }

    func testContentViewReplacementDeallocatesOldViews() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)

        weak var weakPreviousView: NSView?

        for _ in 1...50 {
            autoreleasepool {
                let newView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
                window.contentView = newView
                weakPreviousView = newView
            }
        }

        autoreleasepool {
            // Install one final view to displace previous view
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }

        XCTAssertNil(weakPreviousView, "Previous content view must be cleanly deallocated without retain cycles")
    }

    // MARK: - 7. Audio & Volume Clamping Adversarial Inputs

    func testVolumeAdversarialClampingStress() {
        let manager = DesktopWindowManager(screenProvider: MockScreenProvider())
        defer { manager.terminate() }

        let adversarialInputs: [(input: Float, expected: Float)] = [
            (0.5, 0.5),
            (0.0, 0.0),
            (1.0, 1.0),
            (-0.0, 0.0),
            (-0.00001, 0.0),
            (1.00001, 1.0),
            (-100.0, 0.0),
            (100.0, 1.0),
            (1e30, 1.0),
            (-1e30, 0.0),
            (Float.infinity, 0.0),
            (-Float.infinity, 0.0),
            (Float.nan, 0.0),
            (-Float.nan, 0.0),
            (Float.leastNonzeroMagnitude, Float.leastNonzeroMagnitude)
        ]

        for (input, expected) in adversarialInputs {
            manager.setVolume(input)
            XCTAssertEqual(
                manager.volume,
                expected,
                accuracy: 0.0001,
                "Volume clamping failed for input: \(input)"
            )
            XCTAssertGreaterThanOrEqual(manager.volume, 0.0)
            XCTAssertLessThanOrEqual(manager.volume, 1.0)
        }
    }

    // MARK: - 8. Memory & Resource Stability Under Extreme Stress

    func testMemoryStabilityUnderStress() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        // Warm up
        manager.isInteractive = true
        manager.isInteractive = false

        let memBefore = getResidentMemoryBytes()

        // 300 mode toggles
        for _ in 1...300 {
            manager.isInteractive.toggle()
        }

        // 20 display reloads
        for cycle in 1...20 {
            if cycle % 2 == 0 {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                ]
            } else {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
                ]
            }
            manager.reloadDisplays()
        }

        let memAfter = getResidentMemoryBytes()
        let growthMB = Double(Int64(memAfter) - Int64(memBefore)) / (1024 * 1024)

        // Memory growth should be minimal (< 15MB)
        XCTAssertLessThan(growthMB, 15.0, "Resident memory growth under stress was \(growthMB) MB, exceeding 15MB threshold")
    }
}
