import XCTest
import AppKit
import WebKit
import CoreGraphics
@testable import WallpaperCore

/// Additional Adversarial Deep Stress Tests for WebWallpaperEngine and DesktopWindowManager
/// Created by m3_r2_challenger_2
@MainActor
final class WebManagerAdversarialDeepTests: XCTestCase {

    // MARK: - Helpers

    private final class TestEngineDelegate: WallpaperEngineDelegate {
        var errors: [(engine: WallpaperEngine, error: Error)] = []
        var stateChanges: [(engine: WallpaperEngine, isPlaying: Bool)] = []

        func engineDidEncounterError(_ engine: WallpaperEngine, error: Error) {
            errors.append((engine, error))
        }

        func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool) {
            stateChanges.append((engine, isPlaying))
        }
    }

    private func createTempHTML(content: String) throws -> (tempDir: URL, htmlURL: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let htmlURL = tempDir.appendingPathComponent("index.html")
        try content.write(to: htmlURL, atomically: true, encoding: .utf8)
        return (tempDir, htmlURL)
    }

    // MARK: - 1. Hit-Testing & Coordinate Boundary Stress

    func testHitTesting_BoundaryExtremeCoordinates() {
        let rect = NSRect(x: 100, y: 100, width: 1920, height: 1080)
        let window = DesktopWindow(displayID: 42, frame: rect, isInteractive: false)
        let webView = WallpaperWebView(frame: NSRect(origin: .zero, size: rect.size))
        webView.isInteractive = false
        window.contentView = webView

        // 1. Default passthrough mode: ALL points return nil
        let boundaryPoints: [CGPoint] = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100 + 1920 - 1, y: 100 + 1080 - 1),
            CGPoint(x: 100 + 1920, y: 100 + 1080),
            CGPoint(x: 99, y: 99),
            CGPoint(x: 0, y: 0),
            CGPoint(x: -500, y: -500),
            CGPoint(x: 10000, y: 10000)
        ]

        for pt in boundaryPoints {
            XCTAssertNil(window.hitTest(pt), "Default mode must hitTest nil for screen point \(pt)")
        }

        // 2. Interactive mode: boundary points inside return non-nil, outside return nil
        window.isInteractive = true
        webView.isInteractive = true

        let insidePoints: [CGPoint] = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100 + 960, y: 100 + 540),
            CGPoint(x: 100 + 1919, y: 100 + 1079)
        ]
        for pt in insidePoints {
            XCTAssertNotNil(window.hitTest(pt), "Interactive mode must hitTest inside point \(pt)")
        }

        let outsidePoints: [CGPoint] = [
            CGPoint(x: 99, y: 99),
            CGPoint(x: 100 + 1921, y: 100 + 1081),
            CGPoint(x: -1, y: -1),
            CGPoint(x: 5000, y: 5000)
        ]
        for pt in outsidePoints {
            XCTAssertNil(window.hitTest(pt), "Interactive mode must return nil for outside point \(pt)")
        }
    }

    func testWebEngine_ModalDialogSuppressionDoesNotBlock() async throws {
        let (tempDir, _) = try createTempHTML(content: """
        <!DOCTYPE html><html><body><h1>Dialog Test</h1></body></html>
        """)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let item = WallpaperItem(title: "Dialog Test", type: .web, pathOrURL: tempDir.path)
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        // Wait for page load
        for _ in 0..<30 {
            if !engine.webView.isLoading { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Evaluating alert(), confirm(), and prompt() must resolve immediately without hanging or blocking
        let result = try await engine.webView.evaluateJavaScript("""
            (function() {
                alert("Non-blocking alert");
                const confirmed = confirm("Non-blocking confirm");
                const prompted = prompt("Non-blocking prompt", "default");
                return { confirmed: confirmed, prompted: prompted };
            })()
        """) as? [String: Any]

        XCTAssertNotNil(result, "JavaScript dialog evaluation must resolve cleanly")
        XCTAssertEqual(result?["confirmed"] as? Bool, false, "Confirm must return false")
        XCTAssertNil(result?["prompted"] as? String, "Prompt must return null/nil")
    }

    // MARK: - 3. Rapid Alternating Wallpaper Switching Under Manager

    func testManager_AlternatingVideoAndWebWallpapersStress() {
        let screens = [
            DisplayDescriptor(displayID: 101, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 102, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        let mockProvider = MockScreenProvider(screens: screens)
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let webItem = WallpaperItem(title: "Web", type: .url, pathOrURL: "https://example.com")
        let videoItem = WallpaperItem(title: "Video", type: .video, pathOrURL: "/tmp/sample.mp4")

        for iteration in 1...10 {
            let item = (iteration % 2 == 1) ? webItem : videoItem
            manager.setWallpaper(item)

            XCTAssertEqual(manager.engines.count, 2)
            XCTAssertEqual(manager.windows.count, 2)
            XCTAssertEqual(manager.activeWallpaper?.id, item.id)

            if iteration % 2 == 1 {
                XCTAssertTrue(manager.engines[101] is WebWallpaperEngine)
                XCTAssertTrue(manager.engines[102] is WebWallpaperEngine)
            } else {
                XCTAssertTrue(manager.engines[101] is VideoWallpaperEngine)
                XCTAssertTrue(manager.engines[102] is VideoWallpaperEngine)
            }
        }
    }

    // MARK: - 4. Rapid Multiple WebContent Process Crashes Recovery

    func testWebEngine_ConsecutiveProcessCrashesRecovery() {
        let item = WallpaperItem(title: "Crash Storm", type: .url, pathOrURL: "https://example.com")
        let delegate = TestEngineDelegate()
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        // Simulate 5 consecutive WebContent crashes
        for crashIndex in 1...5 {
            engine.webViewWebContentProcessDidTerminate(engine.webView)
            XCTAssertTrue(engine.hasError)
            XCTAssertEqual(engine.lastEncounteredError as? WebWallpaperEngineError, .processCrashed)
            XCTAssertEqual(delegate.errors.count, crashIndex)
            XCTAssertEqual(delegate.errors.last?.error as? WebWallpaperEngineError, .processCrashed)
        }
    }

    // MARK: - 5. Audio and Volume Edge Values

    func testWebEngine_VolumeExtremeEdgeValues() {
        let item = WallpaperItem(title: "Audio Edge", type: .url, pathOrURL: "https://example.com")
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        // Test normal assignment
        engine.volume = 0.5
        XCTAssertEqual(engine.volume, 0.5, accuracy: 0.001)

        // Test negative clamp
        engine.volume = -100.0
        XCTAssertEqual(engine.volume, 0.0)

        // Test upper clamp
        engine.volume = 999.0
        XCTAssertEqual(engine.volume, 1.0)

        // Test NaN clamp
        engine.volume = Float.nan
        XCTAssertEqual(engine.volume, 0.0)

        // Test Infinity clamp
        engine.volume = Float.infinity
        XCTAssertEqual(engine.volume, 0.0)

        // Test -Infinity clamp
        engine.volume = -Float.infinity
        XCTAssertEqual(engine.volume, 0.0)
    }

    // MARK: - 6. Manager Display Churn with Active Engine

    func testManager_ViolentDisplayTopologyChurn() {
        let mockProvider = MockScreenProvider(screens: [])
        let manager = DesktopWindowManager(screenProvider: mockProvider)
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Churn", type: .url, pathOrURL: "https://example.com")
        manager.setWallpaper(item)
        XCTAssertEqual(manager.engines.count, 0)

        // Add 5 displays
        mockProvider.screens = (1...5).map {
            DisplayDescriptor(displayID: CGDirectDisplayID($0), frame: CGRect(x: ($0 - 1) * 1920, y: 0, width: 1920, height: 1080))
        }
        manager.reloadDisplays()
        XCTAssertEqual(manager.engines.count, 5)
        XCTAssertEqual(manager.windows.count, 5)

        // Drop display 2 and 4, resize display 1 and 3, add display 6
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440)),
            DisplayDescriptor(displayID: 3, frame: CGRect(x: 2560, y: 0, width: 2560, height: 1440)),
            DisplayDescriptor(displayID: 5, frame: CGRect(x: 5120, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 6, frame: CGRect(x: 7040, y: 0, width: 1920, height: 1080))
        ]
        manager.reloadDisplays()

        XCTAssertEqual(manager.engines.count, 4)
        XCTAssertEqual(manager.windows.count, 4)
        XCTAssertNil(manager.engines[2])
        XCTAssertNil(manager.engines[4])
        XCTAssertNotNil(manager.engines[1])
        XCTAssertNotNil(manager.engines[3])
        XCTAssertNotNil(manager.engines[5])
        XCTAssertNotNil(manager.engines[6])

        XCTAssertEqual(manager.windows[1]?.frame, CGRect(x: 0, y: 0, width: 2560, height: 1440))
        XCTAssertEqual(manager.windows[3]?.frame, CGRect(x: 2560, y: 0, width: 2560, height: 1440))
    }
}
