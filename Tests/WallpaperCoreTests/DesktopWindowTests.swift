import XCTest
import AppKit
import CoreGraphics
@testable import WallpaperCore

@MainActor
final class DesktopWindowTests: XCTestCase {

    // MARK: - 1. Window Attributes & Properties

    func testWindowLevel_defaultIsDesktopLevel() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        let expectedLevel = Int(CGWindowLevelForKey(.desktopWindow))
        XCTAssertEqual(window.level.rawValue, expectedLevel, "Default window level must be desktopWindow (-2147483623)")
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertEqual(DesktopWindow.defaultLevel.rawValue, -2147483623)
        XCTAssertEqual(NSWindow.Level.desktop.rawValue, -2147483623)
    }

    func testWindowLevel_interactiveElevatesAboveDesktopIcons() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)

        let expectedLevel = Int(CGWindowLevelForKey(.desktopIconWindow) + 1)
        XCTAssertEqual(window.level.rawValue, expectedLevel, "Interactive level must be desktopIconWindow + 1 (-2147483602)")
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)
        XCTAssertEqual(DesktopWindow.interactiveLevel.rawValue, -2147483602)
        XCTAssertEqual(NSWindow.Level.desktopInteractive.rawValue, -2147483602)
    }

    func testCollectionBehavior_containsAllRequiredFlags() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame)

        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces), "Must persist across Spaces")
        XCTAssertTrue(window.collectionBehavior.contains(.stationary), "Must remain stationary in Mission Control")
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle), "Must be ignored by Cmd+Tab window cycle")
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary), "Must be fullScreenAuxiliary")
    }

    func testWindowStyleAndProperties_borderlessAndClear() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame)

        XCTAssertTrue(window.styleMask.contains(.borderless), "Window must be borderless")
        XCTAssertFalse(window.isOpaque, "Window must support transparency")
        XCTAssertEqual(window.backgroundColor, .clear, "Window background must be clear")
        XCTAssertFalse(window.hasShadow, "Window must not cast shadow")
        XCTAssertTrue(window.acceptsMouseMovedEvents, "Window must accept mouse moved events")
        XCTAssertFalse(window.isMovable, "Window must not be draggable")
        XCTAssertFalse(window.isReleasedWhenClosed, "Window must not be released when closed")
        XCTAssertFalse(window.hidesOnDeactivate, "Window must not hide on app deactivation")
    }

    func testKeyAndMainCapabilities_cannotBecomeMain() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let defaultWindow = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)
        XCTAssertFalse(defaultWindow.canBecomeKey, "Default window cannot become key")
        XCTAssertFalse(defaultWindow.canBecomeMain, "Window must never become main application window")

        let interactiveWindow = DesktopWindow(displayID: 2, frame: frame, isInteractive: true)
        XCTAssertTrue(interactiveWindow.canBecomeKey, "Interactive window must be able to become key for keyboard input")
        XCTAssertFalse(interactiveWindow.canBecomeMain, "Interactive window must still never become main")
    }

    func testWindowScreenIDMatchesDisplayID() {
        let window = DesktopWindow(displayID: 42, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(window.displayID, 42)
        XCTAssertEqual(window.screenID, 42)
    }

    // MARK: - 2. Dual-Gate Event Routing & Interactivity

    func testDefaultMode_ignoresMouseEventsAndHitTestReturnsNil() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        XCTAssertTrue(window.ignoresMouseEvents, "Gate 1: WindowServer skips mouse events")
        XCTAssertNil(window.hitTest(CGPoint(x: 100, y: 100)), "Gate 2: AppKit hitTest returns nil")
        XCTAssertNil(window.hitTest(CGPoint(x: 500, y: 500)))
    }

    func testInteractiveMode_elevatesWindowLevelAndEnablesInput() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        window.isInteractive = true

        XCTAssertFalse(window.ignoresMouseEvents, "Gate 1: WindowServer delivers mouse events")
        XCTAssertEqual(window.level.rawValue, -2147483602, "Window level elevated to -2147483602")
        XCTAssertNotNil(window.hitTest(CGPoint(x: 100, y: 100)), "Gate 2: Hit testing delivers content view")
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isKeyWindow)
    }

    func testToggleInteractiveMode_restoresDefaultState() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        // Toggle on
        window.setInteractive(true)
        XCTAssertTrue(window.isInteractive)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.level.rawValue, -2147483602)
        XCTAssertNotNil(window.hitTest(CGPoint(x: 200, y: 200)))

        // Toggle back off
        window.setInteractive(false)
        XCTAssertFalse(window.isInteractive)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(window.level.rawValue, -2147483623)
        XCTAssertNil(window.hitTest(CGPoint(x: 200, y: 200)))
        XCTAssertFalse(window.isKeyWindow)
    }

    func test100CycleRapidTogglingParity() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        for _ in 1...100 {
            window.isInteractive.toggle()
        }

        // Even number of toggles returns to initial state (false)
        XCTAssertFalse(window.isInteractive, "100 toggles must preserve parity and return to default mode")
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopWindow))
        XCTAssertNil(window.hitTest(CGPoint(x: 100, y: 100)))

        // 1 more toggle -> interactive
        window.isInteractive.toggle()
        XCTAssertTrue(window.isInteractive)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.windowLevel, CGWindowLevelForKey(.desktopIconWindow) + 1)
        XCTAssertNotNil(window.hitTest(CGPoint(x: 100, y: 100)))
    }

    func testHitTest_windowBorderCoordinates() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: false)

        // Default mode: all coordinates return nil
        XCTAssertNil(window.hitTest(CGPoint(x: 0, y: 0)))
        XCTAssertNil(window.hitTest(CGPoint(x: 1920, y: 1080)))
        XCTAssertNil(window.hitTest(CGPoint(x: -1, y: -1)))
        XCTAssertNil(window.hitTest(CGPoint(x: 1921, y: 1081)))

        // Interactive mode
        window.isInteractive = true
        XCTAssertNotNil(window.hitTest(CGPoint(x: 0, y: 0)), "Origin (0,0) must hit in interactive mode")
        XCTAssertNotNil(window.hitTest(CGPoint(x: 960, y: 540)), "Center must hit")
        XCTAssertNil(window.hitTest(CGPoint(x: -1, y: -1)), "Negative coordinates outside window must return nil")
        XCTAssertNil(window.hitTest(CGPoint(x: 2000, y: 2000)), "Coordinates beyond window bounds must return nil")
    }

    func testHitTest_childViewDeliveryInInteractionMode() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let window = DesktopWindow(displayID: 1, frame: frame, isInteractive: true)

        let childButton = NSButton(frame: NSRect(x: 100, y: 100, width: 200, height: 50))
        window.contentView = childButton

        let hit = window.hitTest(CGPoint(x: 150, y: 125))
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit === childButton, "Child view must be delivered directly to the hit tester")
    }

    func testPassthroughView_trackingAreaActiveOnlyInInteractiveMode() {
        let view = PassthroughView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertFalse(view.isInteractive)
        view.updateTrackingAreas()
        XCTAssertEqual(view.trackingAreas.count, 0, "No tracking areas when non-interactive to save CPU")

        view.isInteractive = true
        view.updateTrackingAreas()
        XCTAssertEqual(view.trackingAreas.count, 1, "Dynamic tracking area registered when interactive")
        let area = view.trackingAreas.first
        XCTAssertTrue(area?.options.contains(.mouseMoved) == true)
        XCTAssertTrue(area?.options.contains(.inVisibleRect) == true)

        view.isInteractive = false
        view.updateTrackingAreas()
        XCTAssertEqual(view.trackingAreas.count, 0, "Tracking area removed when returning to default mode")
    }

    func testPassthroughView_menuReturnsNil() {
        let view = PassthroughView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        let event = NSEvent()
        XCTAssertNil(view.menu(for: event), "Default context menus are suppressed")

        view.isInteractive = true
        XCTAssertNil(view.menu(for: event), "Interactive mode also suppresses default WebKit developer menus")
    }

    func testPassthroughView_mouseAndKeyCallbacks() {
        let view = PassthroughView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        var mouseEventCaught: NSEvent?
        var keyEventCaught: NSEvent?
        view.onMouseEvent = { mouseEventCaught = $0 }
        view.onKeyEvent = { keyEventCaught = $0 }

        view.isInteractive = true

        // Synthesize test events
        if let dummyEvent = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) {
            view.mouseDown(with: dummyEvent)
            XCTAssertNotNil(mouseEventCaught)

            view.keyDown(with: dummyEvent)
            XCTAssertNotNil(keyEventCaught)
        }
    }

    // MARK: - 3. Multi-Display Topologies

    func testSingleDisplay_createsExactlyOneWindow() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 10, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertNotNil(manager.windows[10])
        XCTAssertEqual(manager.windows[10]?.frame, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(manager.windowList.count, 1)
    }

    func testMultiDisplay_createsWindowPerScreenWithMatchingFrames() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertEqual(manager.windows[1]?.frame, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(manager.windows[2]?.frame, CGRect(x: 1920, y: 0, width: 2560, height: 1440))
    }

    func testNegativeCoordinates_positionsSecondaryScreenCorrectly() {
        // Monitor arranged to the left of the main display (negative X)
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let secondaryWindow = manager.windows[2]
        XCTAssertNotNil(secondaryWindow)
        XCTAssertEqual(secondaryWindow?.frame.origin.x, -1920)
        XCTAssertEqual(secondaryWindow?.frame.origin.y, 0)

        // Event routing on secondary display
        manager.isInteractive = true
        XCTAssertNotNil(secondaryWindow?.hitTest(CGPoint(x: -1000, y: 500)), "Should hit secondary screen")
        XCTAssertNil(secondaryWindow?.hitTest(CGPoint(x: 100, y: 100)), "Should not hit secondary screen at primary coordinates")
    }

    func testScreenProviderAbstraction_noDirectNSScreenCrash() {
        // Verifies complex arrangements without physical hardware
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 100, frame: CGRect(x: 0, y: 0, width: 3840, height: 2160)),
            DisplayDescriptor(displayID: 200, frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 300, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 3)
    }

    // MARK: - 4. Dynamic Hot-Plugging Diffing

    func testDynamicDisplayAddition_spawnsNewWindow() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 1)

        // Hot-plug second display
        mockProvider.screens.append(DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)))
        manager.reloadDisplays()

        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertNotNil(manager.windows[2])
        XCTAssertEqual(manager.windows[2]?.frame.origin.x, 1920)
    }

    func testDynamicDisplayRemoval_closesAndCleansUpWindow() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 2)

        // Unplug display 2
        mockProvider.screens.removeAll { $0.displayID == 2 }
        manager.reloadDisplays()

        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertNil(manager.windows[2], "Detached window must be removed from manager")
        XCTAssertNotNil(manager.windows[1], "Remaining window must be preserved")
    }

    func testDynamicResolutionChange_updatesWindowFrame() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows[1]?.frame.size, CGSize(width: 1920, height: 1080))

        // Change resolution to 4K
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        ]
        manager.reloadDisplays()

        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.windows[1]?.frame.size, CGSize(width: 3840, height: 2160))
    }

    func testScreenParametersNotification_triggersAutomaticReload() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        mockProvider.screens.append(DisplayDescriptor(displayID: 99, frame: CGRect(x: 1920, y: 0, width: 1440, height: 900)))

        // Broadcast system notification
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        XCTAssertEqual(manager.windows.count, 2, "Notification observer must automatically trigger reloadDisplays()")
        XCTAssertNotNil(manager.windows[99])
    }

    // MARK: - 5. State Forwarding

    func testIsInteractiveToggle_propagatesToAllWindows() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        XCTAssertFalse(manager.isInteractive)
        XCTAssertFalse(manager.windows[1]!.isInteractive)
        XCTAssertFalse(manager.windows[2]!.isInteractive)

        manager.isInteractive = true
        XCTAssertTrue(manager.isInteractive)
        XCTAssertTrue(manager.windows[1]!.isInteractive)
        XCTAssertTrue(manager.windows[2]!.isInteractive)

        manager.isInteractive = false
        XCTAssertFalse(manager.isInteractive)
        XCTAssertFalse(manager.windows[1]!.isInteractive)
        XCTAssertFalse(manager.windows[2]!.isInteractive)
    }

    func testNewWindowInheritsActiveInteractionMode() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        manager.isInteractive = true

        // Hot-plug while interactive
        mockProvider.screens.append(DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)))
        manager.reloadDisplays()

        XCTAssertTrue(manager.windows[2]!.isInteractive, "Hot-plugged window must inherit manager's current interactive state")
    }

    func testSetWallpaper_storesActiveWallpaper() {
        let manager = DesktopWindowManager(screenProvider: MockScreenProvider())
        defer { manager.terminate() }

        let item = WallpaperItem(
            title: "Test Canvas",
            type: .web,
            pathOrURL: "/tmp/sample_canvas"
        )
        manager.setWallpaper(item)
        XCTAssertEqual(manager.activeWallpaper?.title, "Test Canvas")
    }

    func testPlaybackAndAudioControls_clampValues() {
        let manager = DesktopWindowManager(screenProvider: MockScreenProvider())
        defer { manager.terminate() }

        manager.setPaused(true)
        XCTAssertTrue(manager.isPaused)
        manager.setPaused(false)
        XCTAssertFalse(manager.isPaused)

        manager.setMuted(true)
        XCTAssertTrue(manager.isMuted)
        manager.setMuted(false)
        XCTAssertFalse(manager.isMuted)

        manager.setVolume(0.75)
        XCTAssertEqual(manager.volume, 0.75, accuracy: 0.001)

        manager.setVolume(-0.5)
        XCTAssertEqual(manager.volume, 0.0, "Volume must clamp below 0.0")

        manager.setVolume(1.5)
        XCTAssertEqual(manager.volume, 1.0, "Volume must clamp above 1.0")

        manager.setVolume(.nan)
        XCTAssertEqual(manager.volume, 0.0, "NaN volume must safely clamp to 0.0")
    }

    func testTerminate_tearsDownAllWindowsAndCleansUp() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        XCTAssertEqual(manager.windows.count, 2)

        manager.terminate()
        XCTAssertEqual(manager.windows.count, 0, "Terminate must remove and close all windows")
        XCTAssertNil(manager.activeWallpaper)
    }

    // MARK: - 6. Edge Cases & Resilience

    func testEmptyScreenProvider_handlesZeroDisplaysGracefully() {
        let emptyProvider = MockScreenProvider(screens: [])
        let manager = DesktopWindowManager(screenProvider: emptyProvider)
        defer { manager.terminate() }

        XCTAssertEqual(manager.windows.count, 0)
        manager.reloadDisplays()
        XCTAssertEqual(manager.windows.count, 0)
    }

    func testRapidReloadCalls_maintainsConsistentState() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        for _ in 1...50 {
            manager.reloadDisplays()
        }

        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertNotNil(manager.windows[1])
        XCTAssertNotNil(manager.windows[2])
    }

    func testUpdateFrameAndScreenMethods() {
        let window = DesktopWindow(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        window.updateFrame(CGRect(x: 10, y: 10, width: 500, height: 500))
        XCTAssertEqual(window.frame, CGRect(x: 10, y: 10, width: 500, height: 500))
    }
}
