import XCTest
import AppKit
import CoreGraphics
import Darwin
@testable import WallpaperCore

/// Empirical Stress Test Harness for Milestone 2 Multi-Display Lifecycle & Window Management
///
/// Tests:
/// 1. Dynamic display hot-plugging simulation (60+ rapid changes)
/// 2. Complex multi-display topologies (3+ displays, vertical stacking, asymmetrical resolutions, negative origins)
/// 3. Resource leak detection (window, passthrough view, and content view deallocation on display removal)
/// 4. Concurrency stress (rapid state mutations while displays are reloading)
/// 5. Boundary resilience (degenerate frames, duplicate display IDs, notification flooding, idempotent termination)
@MainActor
final class Milestone2StressTests: XCTestCase {

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

    // MARK: - 1. Dynamic Display Hot-Plugging Simulation (60+ Rapid Changes)

    func testDynamicDisplayHotPlugging60Cycles() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 1)

        // 60 rapid hot-plugging transitions with varied display topologies
        for cycle in 1...60 {
            let topologyMode = cycle % 6
            switch topologyMode {
            case 0:
                // Headless / zero screens (e.g. display sleep or all displays disconnected)
                mockProvider.screens = []

            case 1:
                // Single 1080p display
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                ]

            case 2:
                // Dual display: 1080p primary + 4K secondary
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160))
                ]

            case 3:
                // Triple display: 1080p + 4K + Ultrawide to the left (negative origin)
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160)),
                    DisplayDescriptor(displayID: 3, frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440))
                ]

            case 4:
                // Quad display: 1080p + 4K + Left Ultrawide + Top stacked display
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160)),
                    DisplayDescriptor(displayID: 3, frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440)),
                    DisplayDescriptor(displayID: 4, frame: CGRect(x: 0, y: 1080, width: 1920, height: 1200))
                ]

            case 5:
                // Resolution change on display 1: 5K resolution
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 5120, height: 2880))
                ]

            default:
                break
            }

            manager.reloadDisplays()

            // Invariant verification after every single cycle
            XCTAssertEqual(
                manager.windows.count,
                mockProvider.screens.count,
                "Cycle \(cycle): Window count (\(manager.windows.count)) must match screen count (\(mockProvider.screens.count))"
            )

            for screen in mockProvider.screens {
                guard let win = manager.window(for: screen.displayID) else {
                    XCTFail("Cycle \(cycle): Missing window for displayID \(screen.displayID)")
                    continue
                }
                XCTAssertEqual(
                    win.frame,
                    screen.frame,
                    "Cycle \(cycle): Window frame (\(win.frame)) must match screen frame (\(screen.frame))"
                )
                XCTAssertEqual(
                    win.displayID,
                    screen.displayID,
                    "Cycle \(cycle): Window displayID must match screen displayID"
                )
            }
        }
    }

    func testScreenParametersNotificationFloodStress() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        // Flood 100 screen parameter change notifications while alternating topologies
        for i in 1...100 {
            if i % 3 == 0 {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
                ]
            } else if i % 3 == 1 {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
                ]
            } else {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                    DisplayDescriptor(displayID: 3, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
                ]
            }
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }

        XCTAssertEqual(manager.windows.count, mockProvider.screens.count)
    }

    // MARK: - 2. Complex Multi-Display Topologies

    func testComplexTopologies_VerticalStackingNegativeOriginsAndHitTesting() {
        // Multi-display topology:
        // Screen 1: Primary (0, 0, 1920, 1080)
        // Screen 2: Top Stacked (0, 1080, 1920, 1080)
        // Screen 3: Bottom Stacked (0, -1080, 1920, 1080)
        // Screen 4: Left Ultrawide (-3440, 0, 3440, 1440)
        // Screen 5: Right Portrait (1920, -500, 1080, 1920)
        let screens = [
            DisplayDescriptor(displayID: 101, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 102, frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 103, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 104, frame: CGRect(x: -3440, y: 0, width: 3440, height: 1440)),
            DisplayDescriptor(displayID: 105, frame: CGRect(x: 1920, y: -500, width: 1080, height: 1920))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 5)

        // Gate 1 & Gate 2 verification in default passthrough mode
        for screen in screens {
            guard let window = manager.window(for: screen.displayID) else {
                XCTFail("Missing window for screen \(screen.displayID)")
                continue
            }
            XCTAssertTrue(window.ignoresMouseEvents, "Window for screen \(screen.displayID) must ignore mouse events")
            XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))

            // Hit test center of screen in default mode -> MUST BE NIL
            let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            XCTAssertNil(window.hitTest(center), "Default mode on screen \(screen.displayID) must return nil")
        }

        // Elevate to interactive mode
        manager.isInteractive = true

        for screen in screens {
            guard let window = manager.window(for: screen.displayID) else {
                XCTFail("Missing window for screen \(screen.displayID)")
                continue
            }
            XCTAssertFalse(window.ignoresMouseEvents)
            XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)

            // Hit test center of screen in interactive mode -> MUST HIT
            let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let hit = window.hitTest(center)
            XCTAssertNotNil(hit, "Interactive mode on screen \(screen.displayID) at \(center) must hit")

            // Hit test outside screen bounds -> MUST BE NIL
            let outsidePoint = CGPoint(x: screen.frame.minX - 50, y: screen.frame.minY - 50)
            XCTAssertNil(window.hitTest(outsidePoint), "Point outside screen \(screen.displayID) must return nil")
        }

        // Cross-screen hit testing isolation: Screen 4's coordinate must not hit Screen 1's window
        let screen4Center = CGPoint(x: screens[3].frame.midX, y: screens[3].frame.midY)
        XCTAssertNotNil(manager.window(for: 104)?.hitTest(screen4Center))
        XCTAssertNil(manager.window(for: 101)?.hitTest(screen4Center), "Screen 1 must not hit Screen 4's coordinates")
        XCTAssertNil(manager.window(for: 102)?.hitTest(screen4Center))
        XCTAssertNil(manager.window(for: 103)?.hitTest(screen4Center))
        XCTAssertNil(manager.window(for: 105)?.hitTest(screen4Center))
    }

    func testAsymmetricalResolutions() {
        // Diverse non-standard resolutions
        let screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1440, y: 0, width: 5120, height: 1440)),
            DisplayDescriptor(displayID: 3, frame: CGRect(x: -1080, y: 0, width: 1080, height: 1920)),
            DisplayDescriptor(displayID: 4, frame: CGRect(x: 0, y: 900, width: 3840, height: 2160))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 4)
        for screen in screens {
            let win = manager.window(for: screen.displayID)
            XCTAssertNotNil(win)
            XCTAssertEqual(win?.frame, screen.frame)
        }
    }

    // MARK: - 3. Resource Leak Detection & Window Deallocation

    func testWindowDeallocationOnDisplayRemoval() {
        weak var weakWindow2: DesktopWindow?
        weak var weakPassthroughView2: PassthroughView?
        weak var weakChildView2: NSView?
        weak var weakWindow3: DesktopWindow?

        let mockProvider = MockScreenProvider(screens: [])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        autoreleasepool {
            mockProvider.screens = [
                DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
                DisplayDescriptor(displayID: 3, frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080))
            ]
            manager.reloadDisplays()

            if let window2 = manager.windows[2] {
                weakWindow2 = window2
                weakPassthroughView2 = window2.passthroughView

                let child = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
                window2.contentView = child
                weakChildView2 = child
            }

            weakWindow3 = manager.windows[3]

            XCTAssertNotNil(weakWindow2)
            XCTAssertNotNil(weakPassthroughView2)
            XCTAssertNotNil(weakChildView2)
            XCTAssertNotNil(weakWindow3)
        }

        // Remove display 2 from screen provider and reload inside an autoreleasepool
        autoreleasepool {
            mockProvider.screens.removeAll { $0.displayID == 2 }
            manager.reloadDisplays()
        }

        XCTAssertNil(manager.windows[2], "Window 2 must be removed from manager's dictionary")
        XCTAssertEqual(manager.windows.count, 2, "2 windows should remain")
        XCTAssertNotNil(manager.windows[3], "Window 3 must still be present")

        // Drain autorelease pools and spin runloop to allow AppKit deallocation
        for _ in 1...10 {
            autoreleasepool {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }

        XCTAssertNil(weakWindow2, "DesktopWindow for removed display must be deallocated without leaking")
        XCTAssertNil(weakPassthroughView2, "PassthroughView must be deallocated when window is removed")
        XCTAssertNil(weakChildView2, "Child contentView must be deallocated when window is removed")

        // Window 3 must still be alive
        XCTAssertNotNil(weakWindow3, "Window 3 should still be alive")

        // Now remove display 3
        autoreleasepool {
            mockProvider.screens.removeAll { $0.displayID == 3 }
            manager.reloadDisplays()
        }

        for _ in 1...10 {
            autoreleasepool {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }

        XCTAssertNil(weakWindow3, "Window 3 must be deallocated after removal")
        XCTAssertEqual(manager.windows.count, 1)
    }

    func testRepeatedCreationAndDestructionMemoryStability() {
        let mockProvider = MockScreenProvider(screens: [])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        var weakReferences: [WeakWindowBox] = []

        // 60 cycles of dynamic window creation and removal
        for cycle in 1...60 {
            autoreleasepool {
                mockProvider.screens = [
                    DisplayDescriptor(displayID: CGDirectDisplayID(cycle), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                ]
                manager.reloadDisplays()
                if let win = manager.windows[CGDirectDisplayID(cycle)] {
                    weakReferences.append(WeakWindowBox(win))
                }
            }

            autoreleasepool {
                mockProvider.screens = []
                manager.reloadDisplays()
            }
        }

        // Allow AppKit runloop to drain deferred releases
        for _ in 1...10 {
            autoreleasepool {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }

        let livingCount = weakReferences.filter { $0.window != nil }.count
        XCTAssertEqual(livingCount, 0, "All 60 dynamically destroyed windows must be deallocated (found \(livingCount) leaked)")
    }

    // MARK: - 4. Concurrency Stress (State Mutations During Reloads)

    func testConcurrentPropertyModificationsDuringReloads() async {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        // Execute rapid concurrent tasks across actors
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Interactivity toggling
            group.addTask { @MainActor in
                for i in 1...60 {
                    manager.isInteractive = (i % 2 == 0)
                }
            }

            // Task 2: Wallpaper switching
            group.addTask { @MainActor in
                for i in 1...60 {
                    let item = WallpaperItem(title: "Concurrent Item \(i)", type: .web, pathOrURL: "/tmp/\(i)")
                    manager.setWallpaper(item)
                }
            }

            // Task 3: Audio & Playback controls with boundary values
            group.addTask { @MainActor in
                for i in 1...60 {
                    manager.setPaused(i % 2 == 0)
                    manager.setMuted(i % 3 == 0)
                    let vol = (i % 4 == 0) ? -1.0 : ((i % 4 == 1) ? 2.0 : Float(i) / 60.0)
                    manager.setVolume(Float(vol))
                }
            }

            // Task 4: Simultaneous Display Reloading
            group.addTask { @MainActor in
                for i in 1...60 {
                    if i % 2 == 0 {
                        mockProvider.screens = [
                            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440)),
                            DisplayDescriptor(displayID: 3, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
                        ]
                    } else {
                        mockProvider.screens = [
                            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                        ]
                    }
                    manager.reloadDisplays()
                }
            }
        }

        // Post-concurrency consistency verification
        XCTAssertEqual(manager.windows.count, mockProvider.screens.count)
        XCTAssertGreaterThanOrEqual(manager.volume, 0.0)
        XCTAssertLessThanOrEqual(manager.volume, 1.0)
        for window in manager.windowList {
            XCTAssertEqual(window.isInteractive, manager.isInteractive, "Window interactivity must stay synchronized with manager")
        }
    }

    // MARK: - 5. Boundary & Extreme Value Attacks

    func testDegenerateDisplayFrames() {
        let screens = [
            DisplayDescriptor(displayID: 10, frame: CGRect(x: 0, y: 0, width: 0, height: 0)),
            DisplayDescriptor(displayID: 20, frame: CGRect(x: 100_000, y: -100_000, width: 10_000, height: 10_000)),
            DisplayDescriptor(displayID: 30, frame: CGRect(x: -500, y: -500, width: 1, height: 1))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 3)
        XCTAssertNotNil(manager.windows[10])
        XCTAssertNotNil(manager.windows[20])
        XCTAssertNotNil(manager.windows[30])

        manager.isInteractive = true
        XCTAssertNil(manager.windows[10]?.hitTest(CGPoint(x: 50, y: 50)))
        XCTAssertNil(manager.windows[20]?.hitTest(CGPoint(x: 0, y: 0)))
    }

    func testVolumeExtremeValuesAndEdgeCases() {
        let manager = DesktopWindowManager(screenProvider: MockScreenProvider())
        defer { manager.terminate() }

        manager.setVolume(-Float.greatestFiniteMagnitude)
        XCTAssertEqual(manager.volume, 0.0)

        manager.setVolume(Float.greatestFiniteMagnitude)
        XCTAssertEqual(manager.volume, 1.0)

        manager.setVolume(-.infinity)
        XCTAssertEqual(manager.volume, 0.0)

        manager.setVolume(.infinity)
        XCTAssertEqual(manager.volume, 0.0)

        manager.setVolume(.nan)
        XCTAssertEqual(manager.volume, 0.0)

        manager.setVolume(-0.0)
        XCTAssertEqual(manager.volume, 0.0)

        manager.setVolume(Float.leastNonzeroMagnitude)
        XCTAssertEqual(manager.volume, Float.leastNonzeroMagnitude)
    }

    func testDuplicateDisplayIDsInScreenProvider() {
        let screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        // Gracefully deduplicates to exactly 1 window with last reported frame
        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.windows[1]?.frame.size, CGSize(width: 2560, height: 1440))
    }

    func testRapidContentViewSwapping() {
        let window = DesktopWindow(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), isInteractive: true)

        var weakViews: [WeakViewBox] = []

        for _ in 1...50 {
            autoreleasepool {
                let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
                window.contentView = view
                weakViews.append(WeakViewBox(view))
            }
        }

        let currentContent = window.contentView
        XCTAssertNotNil(currentContent)

        // Previous 49 views must be deallocated
        for _ in 1...10 {
            autoreleasepool {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }

        let deadViewsCount = weakViews.dropLast().filter { $0.view == nil }.count
        XCTAssertEqual(deadViewsCount, 49, "Replaced child views must be removed and deallocated")
    }

    func testMultipleTerminateCallsAreIdempotent() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)

        XCTAssertEqual(manager.windows.count, 1)

        manager.terminate()
        XCTAssertEqual(manager.windows.count, 0)

        // Repeated calls must be cleanly idempotent without crashing
        manager.terminate()
        manager.terminate()
        XCTAssertEqual(manager.windows.count, 0)

        // Calling reloadDisplays after terminate works cleanly
        manager.reloadDisplays()
        XCTAssertEqual(manager.windows.count, 1)
    }
}

// MARK: - Weak Boxing Helper Structs

private struct WeakWindowBox {
    weak var window: DesktopWindow?
    init(_ window: DesktopWindow) {
        self.window = window
    }
}

private struct WeakViewBox {
    weak var view: NSView?
    init(_ view: NSView) {
        self.view = view
    }
}
