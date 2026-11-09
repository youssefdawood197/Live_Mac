import XCTest
import AppKit
import WebKit
import CoreGraphics
@testable import WallpaperCore

/// Milestone 3 Adversarial Challenge Suite: Web Rendering Engine & Window Manager Integration
/// Empirically stress-tests:
/// 1. Dual-gate hit testing behavior (passthrough when !isInteractive, delegation to super when isInteractive)
/// 2. Context menu suppression across all mouse event types
/// 3. 3-tier pause suspension (WebKit native media suspension, JS RAF loop throttling, resume playback)
/// 4. WebContent process crash recovery simulation
/// 5. Multi-display independent engine instances and synchronous state propagation
/// 6. Dynamic display diffing on hot-plug and unplugging
/// 7. Input validation, security scheme rejection, and boundary robustness
@MainActor
final class Milestone3WebManagerChallengeTests: XCTestCase {

    // MARK: - Helpers

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint = .zero,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        if let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        ) {
            return event
        }
        return NSEvent.otherEvent(
            with: .applicationDefined,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        )!
    }

    private func createTempCanvasDirectory() throws -> (tempDir: URL, canvasDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let canvasDir = tempDir.appendingPathComponent("sample_canvas")
        let generator = SampleAssetGenerator()
        try generator.generateSampleCanvas(at: canvasDir)
        return (tempDir, canvasDir)
    }

    // MARK: - 1. Hit Testing Behavior Verification

    func testWebHitTesting_DefaultMode_StrictPassthrough() {
        let webView = WallpaperWebView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        webView.isInteractive = false

        // In non-interactive mode, hitTest MUST return nil for any coordinate
        let testPoints: [NSPoint] = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: 960, y: 540),
            NSPoint(x: 1919, y: 1079),
            NSPoint(x: -100, y: -100),
            NSPoint(x: 2500, y: 1500)
        ]

        for pt in testPoints {
            XCTAssertNil(
                webView.hitTest(pt),
                "WallpaperWebView must return nil on hitTest when isInteractive is false at point \(pt)"
            )
        }

        // Test in full window hierarchy
        let window = DesktopWindow(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isInteractive: false)
        window.contentView = webView

        XCTAssertTrue(window.ignoresMouseEvents)
        for pt in testPoints {
            let hit = window.hitTest(pt)
            XCTAssertNil(hit, "DesktopWindow hitTest must return nil in default passthrough mode at point \(pt)")
        }
    }

    func testWebHitTesting_InteractiveMode_DelegatesToSuper() {
        let webView = WallpaperWebView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        webView.isInteractive = true

        // Points inside the view bounds must return a hit view (super.hitTest)
        let insidePoint = NSPoint(x: 960, y: 540)
        let hitInside = webView.hitTest(insidePoint)
        XCTAssertNotNil(hitInside, "WallpaperWebView must delegate to super.hitTest when isInteractive is true")

        // Points outside view bounds must return nil
        let outsidePoints: [NSPoint] = [
            NSPoint(x: -10, y: -10),
            NSPoint(x: 2000, y: 1200)
        ]
        for pt in outsidePoints {
            XCTAssertNil(
                webView.hitTest(pt),
                "WallpaperWebView must return nil for points outside bounds when isInteractive is true at \(pt)"
            )
        }

        // Test in full window hierarchy
        let window = DesktopWindow(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isInteractive: true)
        window.contentView = webView
        XCTAssertFalse(window.ignoresMouseEvents)

        let windowHit = window.hitTest(CGPoint(x: 960, y: 540))
        XCTAssertNotNil(windowHit, "DesktopWindow hitTest must return a target view in interactive mode")

        let windowHitOutside = window.hitTest(CGPoint(x: 3000, y: 3000))
        XCTAssertNil(windowHitOutside, "DesktopWindow hitTest must return nil for points outside the window frame")
    }

    func testWebHitTesting_RapidInteractivityTogglingStress() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Interactive Web", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let window = manager.windows[1],
              let engine = manager.engines[1] as? WebWallpaperEngine else {
            XCTFail("Failed to initialize DesktopWindowManager with WebWallpaperEngine")
            return
        }

        let testPoint = CGPoint(x: 500, y: 500)

        for cycle in 1...100 {
            let makeInteractive = (cycle % 2 == 1)
            manager.isInteractive = makeInteractive

            XCTAssertEqual(manager.isInteractive, makeInteractive)
            XCTAssertEqual(window.isInteractive, makeInteractive)
            XCTAssertEqual(engine.isInteractive, makeInteractive)
            XCTAssertEqual(engine.webView.isInteractive, makeInteractive)
            XCTAssertEqual(window.ignoresMouseEvents, !makeInteractive)

            if makeInteractive {
                XCTAssertNotNil(window.hitTest(testPoint), "Cycle \(cycle): expected non-nil hit in interactive mode")
                XCTAssertNotNil(engine.webView.hitTest(NSPoint(x: 500, y: 500)))
            } else {
                XCTAssertNil(window.hitTest(testPoint), "Cycle \(cycle): expected nil hit in passthrough mode")
                XCTAssertNil(engine.webView.hitTest(NSPoint(x: 500, y: 500)))
            }
        }
    }

    // MARK: - 2. Context Menu Suppression Verification

    func testContextMenuSuppression_AcrossAllEventVariants() {
        let webView = WallpaperWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let passthroughView = PassthroughView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        passthroughView.contentView = webView

        let events: [NSEvent] = [
            makeMouseEvent(type: .rightMouseDown, location: NSPoint(x: 100, y: 100)),
            makeMouseEvent(type: .rightMouseUp, location: NSPoint(x: 100, y: 100)),
            makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 100, y: 100), modifierFlags: [.control]),
            makeMouseEvent(type: .otherMouseDown, location: NSPoint(x: 100, y: 100))
        ]

        for isInteractive in [false, true] {
            webView.isInteractive = isInteractive
            passthroughView.isInteractive = isInteractive

            for event in events {
                XCTAssertNil(
                    webView.menu(for: event),
                    "WallpaperWebView must return nil menu(for:) regardless of interactivity (isInteractive: \(isInteractive))"
                )
                XCTAssertNil(
                    passthroughView.menu(for: event),
                    "PassthroughView must return nil menu(for:) regardless of interactivity (isInteractive: \(isInteractive))"
                )
            }
        }
    }

    // MARK: - 3. 3-Tier Pause Suspension Verification

    func testWebPauseSuspension_RealWebKitJavaScriptEvaluation() async throws {
        let (tempDir, canvasDir) = try createTempCanvasDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let item = WallpaperItem(title: "Canvas Pause Test", type: .web, pathOrURL: canvasDir.path)
        let delegate = MockEngineDelegate()
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        // Wait for page to finish loading
        let loadedExpectation = expectation(description: "WebKit navigation finished")
        var attempts = 0
        while attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if !engine.webView.isLoading {
                loadedExpectation.fulfill()
                break
            }
            attempts += 1
        }
        await fulfillment(of: [loadedExpectation], timeout: 5.0)

        // Verify initial playing state
        XCTAssertTrue(engine.isPlaying)
        let initialPausedState = try await engine.webView.evaluateJavaScript("window.__wallpaper_isPaused === false") as? Bool
        XCTAssertEqual(initialPausedState, true, "window.__wallpaper_isPaused must be false when engine is playing")

        // 1. Trigger Pause (Tier 1: native media, Tier 2: JS RAF loop, Tier 3: Lively notification)
        engine.pause()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, false)

        let pausedState = try await engine.webView.evaluateJavaScript("window.__wallpaper_isPaused === true") as? Bool
        XCTAssertEqual(pausedState, true, "window.__wallpaper_isPaused must be true after engine.pause()")

        // 2. Trigger Play / Resume
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, true)

        let resumedState = try await engine.webView.evaluateJavaScript("window.__wallpaper_isPaused === false") as? Bool
        XCTAssertEqual(resumedState, true, "window.__wallpaper_isPaused must be false after engine.play()")
    }

    func testWebPauseSuspension_IdempotentAndRapidTransitions() {
        let item = WallpaperItem(title: "Idempotent Pause", type: .url, pathOrURL: "https://example.com")
        let delegate = MockEngineDelegate()
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertTrue(engine.isPlaying)

        // Multiple pause calls in sequence
        for _ in 1...10 {
            engine.pause()
            XCTAssertFalse(engine.isPlaying)
        }
        // Exactly 1 state change notification should have occurred
        XCTAssertEqual(delegate.stateChanges.count, 1)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, false)

        // Multiple play calls in sequence
        for _ in 1...10 {
            engine.play()
            XCTAssertTrue(engine.isPlaying)
        }
        // Exactly 2 state change notifications total
        XCTAssertEqual(delegate.stateChanges.count, 2)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, true)

        // Rapid 50-cycle oscillation
        for cycle in 1...50 {
            engine.pause()
            XCTAssertFalse(engine.isPlaying)
            engine.play()
            XCTAssertTrue(engine.isPlaying)
            XCTAssertEqual(delegate.stateChanges.count, 2 + cycle * 2)
        }
    }

    func testWebPauseSuspension_EnforcedOnLateNavigationCompletion() {
        let item = WallpaperItem(title: "Late Nav", type: .url, pathOrURL: "https://example.com")
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        // Immediately pause before navigation completes
        engine.pause()
        XCTAssertFalse(engine.isPlaying)

        // Simulate navigation completion while engine is paused
        engine.webView(engine.webView, didFinish: nil)

        // Engine must stay paused
        XCTAssertFalse(engine.isPlaying)
    }

    // MARK: - 4. WebContent Process Crash Recovery Simulation

    func testWebContentProcessCrash_DelegateNotificationAndAutoReload() {
        let item = WallpaperItem(title: "Crash Recovery", type: .url, pathOrURL: "https://example.com")
        let delegate = MockEngineDelegate()
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertFalse(engine.hasError)
        XCTAssertNil(engine.lastEncounteredError)

        // Simulate WebContent process termination (crash / OOM by OS)
        engine.webViewWebContentProcessDidTerminate(engine.webView)

        XCTAssertTrue(engine.hasError)
        XCTAssertEqual(engine.lastEncounteredError as? WebWallpaperEngineError, .processCrashed)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first?.error as? WebWallpaperEngineError, .processCrashed)
    }

    func testWebContentProcessCrash_IntegrationWithDesktopWindowManager() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        var capturedError: Error?
        var errorCallCount = 0
        manager.onEngineError = { _, error in
            capturedError = error
            errorCallCount += 1
        }

        let item = WallpaperItem(title: "Crash Under Manager", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let webEngine = manager.engines[1] as? WebWallpaperEngine else {
            XCTFail("Expected WebWallpaperEngine on display 1")
            return
        }

        // Trigger crash simulation
        webEngine.webViewWebContentProcessDidTerminate(webEngine.webView)

        XCTAssertEqual(errorCallCount, 1)
        XCTAssertEqual(capturedError as? WebWallpaperEngineError, .processCrashed)

        // Window manager must remain intact
        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.engines.count, 1)
        XCTAssertNotNil(manager.windows[1]?.contentView)
    }

    // MARK: - 5. Multi-Display Independent Engines & Synchronous State Propagation

    func testMultiDisplay_IndependentWebEnginesPerDisplay() {
        let screens = [
            DisplayDescriptor(displayID: 10, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 20, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440)),
            DisplayDescriptor(displayID: 30, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Multi Web", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        XCTAssertEqual(manager.engines.count, 3)
        XCTAssertEqual(manager.windows.count, 3)

        guard let e1 = manager.engines[10] as? WebWallpaperEngine,
              let e2 = manager.engines[20] as? WebWallpaperEngine,
              let e3 = manager.engines[30] as? WebWallpaperEngine else {
            XCTFail("Expected all 3 engines to be WebWallpaperEngine")
            return
        }

        // Verify reference inequality (each display MUST own an independent instance)
        XCTAssertTrue(e1 !== e2)
        XCTAssertTrue(e2 !== e3)
        XCTAssertTrue(e1 !== e3)
        XCTAssertTrue(e1.webView !== e2.webView)
        XCTAssertTrue(e2.webView !== e3.webView)

        // Verify window contentViews host the respective webViews
        XCTAssertTrue(manager.windows[10]?.contentView === e1.webView)
        XCTAssertTrue(manager.windows[20]?.contentView === e2.webView)
        XCTAssertTrue(manager.windows[30]?.contentView === e3.webView)
    }

    func testMultiDisplay_SynchronousStatePropagationAcrossAllDisplays() {
        let screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Sync Test", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let e1 = manager.engines[1] as? WebWallpaperEngine,
              let e2 = manager.engines[2] as? WebWallpaperEngine,
              let w1 = manager.windows[1],
              let w2 = manager.windows[2] else {
            XCTFail("Engines or windows missing")
            return
        }

        // 1. Pause / Resume propagation
        manager.setPaused(true)
        XCTAssertTrue(manager.isPaused)
        XCTAssertFalse(e1.isPlaying)
        XCTAssertFalse(e2.isPlaying)

        manager.setPaused(false)
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(e1.isPlaying)
        XCTAssertTrue(e2.isPlaying)

        // 2. Mute / Unmute propagation
        manager.setMuted(false)
        XCTAssertFalse(manager.isMuted)
        XCTAssertFalse(e1.isMuted)
        XCTAssertFalse(e2.isMuted)

        manager.setMuted(true)
        XCTAssertTrue(manager.isMuted)
        XCTAssertTrue(e1.isMuted)
        XCTAssertTrue(e2.isMuted)

        // 3. Volume propagation & clamping
        manager.setVolume(0.42)
        XCTAssertEqual(manager.volume, 0.42, accuracy: 0.001)
        XCTAssertEqual(e1.volume, 0.42, accuracy: 0.001)
        XCTAssertEqual(e2.volume, 0.42, accuracy: 0.001)

        manager.setVolume(-1.0)
        XCTAssertEqual(manager.volume, 0.0)
        XCTAssertEqual(e1.volume, 0.0)
        XCTAssertEqual(e2.volume, 0.0)

        manager.setVolume(5.0)
        XCTAssertEqual(manager.volume, 1.0)
        XCTAssertEqual(e1.volume, 1.0)
        XCTAssertEqual(e2.volume, 1.0)

        manager.setVolume(Float.nan)
        XCTAssertEqual(manager.volume, 0.0)
        XCTAssertEqual(e1.volume, 0.0)
        XCTAssertEqual(e2.volume, 0.0)

        // 4. Interactive mode propagation
        manager.isInteractive = true
        XCTAssertTrue(manager.isInteractive)
        XCTAssertTrue(w1.isInteractive)
        XCTAssertTrue(w2.isInteractive)
        XCTAssertTrue(e1.isInteractive)
        XCTAssertTrue(e2.isInteractive)
        XCTAssertTrue(e1.webView.isInteractive)
        XCTAssertTrue(e2.webView.isInteractive)

        manager.isInteractive = false
        XCTAssertFalse(manager.isInteractive)
        XCTAssertFalse(w1.isInteractive)
        XCTAssertFalse(w2.isInteractive)
        XCTAssertFalse(e1.isInteractive)
        XCTAssertFalse(e2.isInteractive)
        XCTAssertFalse(e1.webView.isInteractive)
        XCTAssertFalse(e2.webView.isInteractive)
    }

    // MARK: - 6. Dynamic Display Diffing: Hot-Plug & Unplugging

    func testDynamicDisplayDiffing_HotPlugPreservesExistingEnginesWithoutRestart() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        manager.setVolume(0.77)
        manager.setMuted(false)
        manager.isInteractive = true
        let item = WallpaperItem(title: "HotPlug Web", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let initialEngine1 = manager.engines[1] as? WebWallpaperEngine else {
            XCTFail("Initial engine missing")
            return
        }

        // Hot-plug display 2
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ]
        manager.reloadDisplays()

        XCTAssertEqual(manager.engines.count, 2)
        XCTAssertEqual(manager.windows.count, 2)

        // Existing engine on Display 1 MUST NOT be recreated or restarted!
        XCTAssertTrue(manager.engines[1] === initialEngine1)
        XCTAssertFalse(initialEngine1.isTerminated)

        // Newly added Display 2 MUST inherit all manager properties
        guard let engine2 = manager.engines[2] as? WebWallpaperEngine else {
            XCTFail("Engine 2 missing or wrong type")
            return
        }
        XCTAssertEqual(engine2.volume, 0.77, accuracy: 0.001)
        XCTAssertFalse(engine2.isMuted)
        XCTAssertTrue(engine2.isInteractive)
        XCTAssertTrue(engine2.webView.isInteractive)
        XCTAssertTrue(manager.windows[2]?.isInteractive == true)
        XCTAssertTrue(manager.windows[2]?.contentView === engine2.webView)
    }

    func testDynamicDisplayDiffing_UnpluggingOneScreenKeepsRemainingScreenIntact() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Unplug Web", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let engine1 = manager.engines[1] as? WebWallpaperEngine,
              let engine2 = manager.engines[2] as? WebWallpaperEngine else {
            XCTFail("Engines missing")
            return
        }

        // Unplug Display 2
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ]
        manager.reloadDisplays()

        // Display 2 was cleanly terminated and removed
        XCTAssertEqual(manager.engines.count, 1)
        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertNil(manager.engines[2])
        XCTAssertNil(manager.windows[2])
        XCTAssertTrue(engine2.isTerminated)

        // Display 1 remains running undisturbed
        XCTAssertTrue(manager.engines[1] === engine1)
        XCTAssertFalse(engine1.isTerminated)
        XCTAssertTrue(engine1.isPlaying)
    }

    func testDynamicDisplayDiffing_ResolutionChangeUpdatesWindowFrameWithoutRestart() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Resize Test", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let engine1 = manager.engines[1] as? WebWallpaperEngine else {
            XCTFail("Engine 1 missing")
            return
        }

        // Resolution changes to 4K (3840x2160)
        let updatedFrame = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: updatedFrame)
        ]
        manager.reloadDisplays()

        // Window frame resized
        XCTAssertEqual(manager.windows[1]?.frame, updatedFrame)
        // Engine preserved without restart
        XCTAssertTrue(manager.engines[1] === engine1)
        XCTAssertFalse(engine1.isTerminated)
    }

    func testDynamicDisplayDiffing_AllDisplaysUnpluggedAndReconnected() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "All Unplug", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)

        guard let initialEngine = manager.engines[1] as? WebWallpaperEngine else {
            XCTFail("Engine missing")
            return
        }

        // Unplug all displays
        mockProvider.screens = []
        manager.reloadDisplays()

        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertTrue(manager.engines.isEmpty)
        XCTAssertTrue(initialEngine.isTerminated)

        // Reconnect display
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ]
        manager.reloadDisplays()

        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.engines.count, 1)
        guard let reconnectedEngine = manager.engines[1] as? WebWallpaperEngine else {
            XCTFail("Reconnected engine missing")
            return
        }
        XCTAssertFalse(reconnectedEngine.isTerminated)
        XCTAssertTrue(manager.windows[1]?.contentView === reconnectedEngine.webView)
    }

    // MARK: - 7. Adversarial Input Validation & Security Boundaries

    func testWebEngine_SecuritySchemeRejection() {
        let forbiddenSchemes = [
            "javascript:alert('pwned')",
            "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
            "ftp://files.example.com/exploit.html",
            "about:blank",
            "blob:http://example.com/uuid"
        ]

        for urlString in forbiddenSchemes {
            let item = WallpaperItem(title: "Malicious Scheme", type: .url, pathOrURL: urlString)
            let delegate = MockEngineDelegate()
            let engine = WebWallpaperEngine(item: item, delegate: delegate)
            defer { engine.terminate() }

            XCTAssertTrue(
                engine.hasError,
                "WebWallpaperEngine must reject non-http/https URL scheme: \(urlString)"
            )
            XCTAssertEqual(
                engine.lastEncounteredError as? WebWallpaperEngineError,
                .invalidURLScheme(urlString)
            )
            XCTAssertEqual(delegate.errors.count, 1)
        }
    }

    func testWebEngine_LocalFileErrorHandling() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Missing directory / file
        let missingPath = tempDir.appendingPathComponent("nonexistent_dir").path
        let item1 = WallpaperItem(title: "Missing", type: .web, pathOrURL: missingPath)
        let delegate1 = MockEngineDelegate()
        let engine1 = WebWallpaperEngine(item: item1, delegate: delegate1)
        defer { engine1.terminate() }

        XCTAssertTrue(engine1.hasError)
        XCTAssertEqual(delegate1.errors.count, 1)
        XCTAssertEqual(
            delegate1.errors.first?.error as? WebWallpaperEngineError,
            .fileNotFound(URL(fileURLWithPath: missingPath).standardizedFileURL)
        )

        // 2. Directory missing index.html
        let emptyDir = tempDir.appendingPathComponent("empty_web_folder")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let item2 = WallpaperItem(title: "No Index", type: .web, pathOrURL: emptyDir.path)
        let delegate2 = MockEngineDelegate()
        let engine2 = WebWallpaperEngine(item: item2, delegate: delegate2)
        defer { engine2.terminate() }

        XCTAssertTrue(engine2.hasError)
        XCTAssertEqual(delegate2.errors.count, 1)
        XCTAssertEqual(
            delegate2.errors.first?.error as? WebWallpaperEngineError,
            .missingIndexHTML(emptyDir.standardizedFileURL)
        )

        // 3. Unsupported file type (.txt, .exe, .py)
        let textFile = tempDir.appendingPathComponent("malicious.exe")
        try "MZ9000".write(to: textFile, atomically: true, encoding: .utf8)

        let item3 = WallpaperItem(title: "Bad File", type: .web, pathOrURL: textFile.path)
        let delegate3 = MockEngineDelegate()
        let engine3 = WebWallpaperEngine(item: item3, delegate: delegate3)
        defer { engine3.terminate() }

        XCTAssertTrue(engine3.hasError)
        XCTAssertEqual(delegate3.errors.count, 1)
        XCTAssertEqual(
            delegate3.errors.first?.error as? WebWallpaperEngineError,
            .unsupportedFileType("exe")
        )
    }

    func testWebEngine_DoubleTerminationSafety() {
        let item = WallpaperItem(title: "Double Term", type: .url, pathOrURL: "https://example.com")
        let delegate = MockEngineDelegate()
        let engine = WebWallpaperEngine(item: item, delegate: delegate)

        // Multiple terminate calls must be completely idempotent and safe
        for _ in 1...10 {
            engine.terminate()
            XCTAssertTrue(engine.isTerminated)
            XCTAssertFalse(engine.isPlaying)
        }

        // Calling play / pause after terminate must be safe no-ops
        engine.play()
        XCTAssertFalse(engine.isPlaying)
        engine.pause()
        XCTAssertFalse(engine.isPlaying)
    }

    func testWebEngineAndWindowManager_DeallocationWithoutRetainCycles() async throws {
        weak var weakEngineRef: WebWallpaperEngine?
        weak var weakManagerRef: DesktopWindowManager?

        autoreleasepool {
            let mockProvider = MockScreenProvider(screens: [
                DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            ])
            let manager = DesktopWindowManager(screenProvider: mockProvider)
            weakManagerRef = manager

            let item = WallpaperItem(title: "Dealloc Web", type: .url, pathOrURL: "https://example.com")
            manager.setWallpaper(item)

            if let engine = manager.engines[1] as? WebWallpaperEngine {
                weakEngineRef = engine
            }

            manager.terminate()
        }

        for _ in 0..<10 {
            if weakEngineRef == nil && weakManagerRef == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNil(weakEngineRef, "WebWallpaperEngine must be deallocated without retain cycle after termination")
        XCTAssertNil(weakManagerRef, "DesktopWindowManager must be deallocated without retain cycle after termination")
    }
}
