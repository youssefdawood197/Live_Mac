import XCTest
import AppKit
import AVFoundation
import WebKit
@testable import WallpaperCore

// MARK: - Mock Engine & Delegate

@MainActor
final class MockWallpaperEngine: WallpaperEngine {
    let view: NSView
    let item: WallpaperItem
    weak var delegate: WallpaperEngineDelegate?

    var isMuted: Bool = true {
        didSet { mutedChanges.append(isMuted) }
    }
    var volume: Float = 1.0 {
        didSet { volumeChanges.append(volume) }
    }
    var isInteractive: Bool = false {
        didSet { interactiveChanges.append(isInteractive) }
    }
    private(set) var isPlaying: Bool = false {
        didSet {
            playbackStateChanges.append(isPlaying)
            delegate?.engineDidChangePlaybackState(self, isPlaying: isPlaying)
        }
    }

    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var terminateCallCount = 0
    private(set) var isTerminated = false

    var mutedChanges: [Bool] = []
    var volumeChanges: [Float] = []
    var interactiveChanges: [Bool] = []
    var playbackStateChanges: [Bool] = []

    init(item: WallpaperItem, frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)) {
        self.item = item
        self.view = NSView(frame: frame)
    }

    func play() {
        guard !isTerminated else { return }
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        guard !isTerminated else { return }
        pauseCallCount += 1
        isPlaying = false
    }

    func terminate() {
        terminateCallCount += 1
        isTerminated = true
        isPlaying = false
    }

    func simulateError(_ error: Error) {
        delegate?.engineDidEncounterError(self, error: error)
    }
}

@MainActor
final class MockEngineDelegate: WallpaperEngineDelegate {
    var errors: [(engine: WallpaperEngine, error: Error)] = []
    var stateChanges: [(engine: WallpaperEngine, isPlaying: Bool)] = []

    func engineDidEncounterError(_ engine: WallpaperEngine, error: Error) {
        errors.append((engine, error))
    }

    func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool) {
        stateChanges.append((engine, isPlaying))
    }
}

// MARK: - EngineTests

@MainActor
final class EngineTests: XCTestCase {

    // MARK: - Suite 1: Protocol & Factory Verification

    func testFactoryRoutesVideoTypeToVideoWallpaperEngine() {
        let item = WallpaperItem(title: "Video", type: .video, pathOrURL: "/test.mp4")
        let engine = WallpaperEngineFactory.createEngine(for: item)
        defer { engine.terminate() }

        XCTAssertTrue(engine is VideoWallpaperEngine)
        XCTAssertEqual(engine.item.type, .video)
        XCTAssertNotNil(engine.view)
    }

    func testFactoryRoutesWebTypeToWebWallpaperEngine() {
        let item = WallpaperItem(title: "Web", type: .web, pathOrURL: "/test_dir")
        let engine = WallpaperEngineFactory.createEngine(for: item)
        defer { engine.terminate() }

        XCTAssertTrue(engine is WebWallpaperEngine)
        XCTAssertEqual(engine.item.type, .web)
        XCTAssertNotNil(engine.view)
    }

    func testFactoryRoutesURLTypeToWebWallpaperEngine() {
        let item = WallpaperItem(title: "URL", type: .url, pathOrURL: "https://example.com")
        let engine = WallpaperEngineFactory.createEngine(for: item)
        defer { engine.terminate() }

        XCTAssertTrue(engine is WebWallpaperEngine)
        XCTAssertEqual(engine.item.type, .url)
        XCTAssertNotNil(engine.view)
    }

    func testWallpaperEngineErrorDescriptions() {
        let errors: [WallpaperEngineError] = [
            .assetNotFound("/test/path"),
            .emptyAsset("/test/empty"),
            .corruptMedia("corrupt header"),
            .unplayableFormat("avi"),
            .missingIndexHTML("/test/dir"),
            .navigationFailed("timeout"),
            .webProcessCrashed("out of memory"),
            .invalidConfiguration("bad config")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    // MARK: - Suite 2: Video Engine Verification (Real AVFoundation)

    func testVideoEngineInitializationAndBackingLayer() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoURL = tempDir.appendingPathComponent("test.mp4")
        let generator = SampleAssetGenerator()
        try await generator.generateSampleVideo(at: videoURL, duration: 0.5)

        let item = WallpaperItem(title: "Test Video", type: .video, pathOrURL: videoURL.path)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        XCTAssertTrue(engine.view.wantsLayer)
        XCTAssertTrue(engine.view.layer is AVPlayerLayer)
        let playerLayer = engine.view.layer as? AVPlayerLayer
        XCTAssertEqual(playerLayer?.videoGravity, .resizeAspectFill)
    }

    func testVideoEngineVolumeAndMuteControls() {
        let item = WallpaperItem(title: "Vol Test", type: .video, pathOrURL: "/dummy.mp4", volume: 0.8, isMuted: true)
        let engine = VideoWallpaperEngine(item: item)
        defer { engine.terminate() }

        XCTAssertEqual(engine.volume, 0.8)
        XCTAssertTrue(engine.isMuted)

        // Dynamic adjustment
        engine.volume = 0.5
        XCTAssertEqual(engine.volume, 0.5)
        XCTAssertTrue(engine.isMuted) // Mute state preserved

        // Clamping upper
        engine.volume = 1.5
        XCTAssertEqual(engine.volume, 1.0)

        // Clamping lower
        engine.volume = -0.5
        XCTAssertEqual(engine.volume, 0.0)

        // NaN safety
        engine.volume = Float.nan
        XCTAssertEqual(engine.volume, 0.0)

        // Infinity safety
        engine.volume = Float.infinity
        XCTAssertEqual(engine.volume, 0.0)

        // Unmute
        engine.isMuted = false
        XCTAssertFalse(engine.isMuted)
        XCTAssertEqual(engine.player.isMuted, false)
    }

    func testVideoEnginePlayPauseTransitions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoURL = tempDir.appendingPathComponent("test.mp4")
        let generator = SampleAssetGenerator()
        try await generator.generateSampleVideo(at: videoURL, duration: 0.5)

        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "PlayPause", type: .video, pathOrURL: videoURL.path)
        let engine = VideoWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertFalse(engine.hasError)
        XCTAssertFalse(engine.isPlaying)

        engine.play()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, true)

        engine.pause()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, false)
    }

    func testVideoEngineTerminate() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoURL = tempDir.appendingPathComponent("test.mp4")
        let generator = SampleAssetGenerator()
        try await generator.generateSampleVideo(at: videoURL, duration: 0.5)

        let item = WallpaperItem(title: "Term", type: .video, pathOrURL: videoURL.path)
        let engine = VideoWallpaperEngine(item: item)

        engine.play()
        XCTAssertTrue(engine.isPlaying)

        engine.terminate()
        XCTAssertTrue(engine.isTerminated)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(engine.looper)
        XCTAssertNil((engine.view as? VideoPlayerView)?.playerLayer.player)
    }

    func testVideoEngineErrorResilience() throws {
        let delegate = MockEngineDelegate()

        // 1. Missing file error
        let missingItem = WallpaperItem(title: "Missing", type: .video, pathOrURL: "/nonexistent_path/video.mp4")
        let engine1 = VideoWallpaperEngine(item: missingItem, delegate: delegate)
        defer { engine1.terminate() }

        XCTAssertTrue(engine1.hasError)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first?.error as? VideoEngineError, .missingFile(URL(fileURLWithPath: missingItem.pathOrURL)))

        // 2. 0-byte file error
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zeroURL = tempDir.appendingPathComponent("empty.mp4")
        FileManager.default.createFile(atPath: zeroURL.path, contents: Data())

        let delegate2 = MockEngineDelegate()
        let zeroItem = WallpaperItem(title: "Empty", type: .video, pathOrURL: zeroURL.path)
        let engine2 = VideoWallpaperEngine(item: zeroItem, delegate: delegate2)
        defer { engine2.terminate() }

        XCTAssertTrue(engine2.hasError)
        XCTAssertEqual(delegate2.errors.count, 1)
        XCTAssertEqual(delegate2.errors.first?.error as? VideoEngineError, .zeroByteFile(zeroURL))

        // 3. Corrupt file error
        let corruptURL = tempDir.appendingPathComponent("corrupt.mp4")
        let corruptData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00])
        try corruptData.write(to: corruptURL)

        let delegate3 = MockEngineDelegate()
        let corruptItem = WallpaperItem(title: "Corrupt", type: .video, pathOrURL: corruptURL.path)
        let engine3 = VideoWallpaperEngine(item: corruptItem, delegate: delegate3)
        defer { engine3.terminate() }

        XCTAssertTrue(engine3.hasError)
        XCTAssertEqual(delegate3.errors.count, 1)
        XCTAssertEqual(delegate3.errors.first?.error as? VideoEngineError, .corruptFile(corruptURL))
    }

    // MARK: - Suite 3: Web Engine Verification (Real WebKit)

    func testWebEngineLocalDirectoryLoading() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let canvasDir = tempDir.appendingPathComponent("canvas_wallpaper")
        let generator = SampleAssetGenerator()
        try generator.generateSampleCanvas(at: canvasDir)

        let item = WallpaperItem(title: "Canvas Test", type: .web, pathOrURL: canvasDir.path)
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        XCTAssertTrue(engine.view is WallpaperWebView)
        let webView = engine.view as! WallpaperWebView
        XCTAssertEqual(webView.underPageBackgroundColor?.alphaComponent, 0.0)
    }

    func testWebEngineRemoteURLLoading() {
        let item = WallpaperItem(title: "Remote URL", type: .url, pathOrURL: "https://example.com")
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        XCTAssertFalse(engine.hasError)
        XCTAssertNotNil(engine.webView)
    }

    func testWebEngineTransparencyAndContextMenuSuppression() {
        let item = WallpaperItem(title: "Web Test", type: .url, pathOrURL: "https://example.com")
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        let webView = engine.webView
        XCTAssertEqual(webView.underPageBackgroundColor?.alphaComponent, 0.0)

        // Suppresses context menu
        let event = NSEvent()
        XCTAssertNil(webView.menu(for: event))
    }

    func testWebEngineInteractionMode() {
        let item = WallpaperItem(title: "Web Interactivity", type: .url, pathOrURL: "https://example.com", isInteractive: false)
        let engine = WebWallpaperEngine(item: item)
        defer { engine.terminate() }

        let webView = engine.webView
        XCTAssertFalse(engine.isInteractive)
        XCTAssertFalse(webView.isInteractive)
        XCTAssertNil(webView.hitTest(NSPoint(x: 100, y: 100)))

        engine.isInteractive = true
        XCTAssertTrue(engine.isInteractive)
        XCTAssertTrue(webView.isInteractive)
        XCTAssertNotNil(webView.hitTest(NSPoint(x: 100, y: 100)))
    }

    func testWebEnginePauseMediaSuspension() {
        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "Web Pause", type: .url, pathOrURL: "https://example.com")
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertTrue(engine.isPlaying)
        engine.pause()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, false)

        engine.play()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(delegate.stateChanges.last?.isPlaying, true)
    }

    func testWebEngineMissingIndexHTMLReporting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "Missing Index", type: .web, pathOrURL: tempDir.path)
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        XCTAssertTrue(engine.hasError)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first?.error as? WebWallpaperEngineError, .missingIndexHTML(tempDir))
    }

    func testWebEngineProcessCrashSelfHealing() {
        let delegate = MockEngineDelegate()
        let item = WallpaperItem(title: "Crash Test", type: .url, pathOrURL: "https://example.com")
        let engine = WebWallpaperEngine(item: item, delegate: delegate)
        defer { engine.terminate() }

        engine.webViewWebContentProcessDidTerminate(engine.webView)
        XCTAssertTrue(engine.hasError)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.errors.first?.error as? WebWallpaperEngineError, .processCrashed)
    }

    // MARK: - Suite 4: DesktopWindowManager Engine Integration

    func testWindowManagerMountsEngineViewOnSetWallpaper() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        var factoryCallCount = 0
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            factoryCallCount += 1
            return MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Test", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(manager.engines.count, 1)
        XCTAssertNotNil(manager.engines[1])
        let window = manager.windows[1]
        XCTAssertNotNil(window)
        XCTAssertTrue(window?.contentView === manager.engines[1]?.view)
    }

    func testWindowManagerMultiDisplayCreatesIndependentEnginesPerWindow() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440)),
            DisplayDescriptor(displayID: 3, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Multi Test", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)

        XCTAssertEqual(manager.engines.count, 3)
        XCTAssertNotNil(manager.engines[1])
        XCTAssertNotNil(manager.engines[2])
        XCTAssertNotNil(manager.engines[3])

        // Verify each display has an independent engine instance
        XCTAssertTrue(manager.engines[1] !== manager.engines[2])
        XCTAssertTrue(manager.engines[2] !== manager.engines[3])
        XCTAssertTrue(manager.engines[1] !== manager.engines[3])

        for (displayID, window) in manager.windows {
            XCTAssertTrue(window.contentView === manager.engines[displayID]?.view)
        }
    }

    func testWindowManagerForwardingControls() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 10, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 20, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Forwarding", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)

        let e1 = manager.engines[10] as! MockWallpaperEngine
        let e2 = manager.engines[20] as! MockWallpaperEngine

        // Pause / Resume
        manager.setPaused(true)
        XCTAssertTrue(manager.isPaused)
        XCTAssertEqual(e1.pauseCallCount, 1)
        XCTAssertEqual(e2.pauseCallCount, 1)

        manager.setPaused(false)
        XCTAssertFalse(manager.isPaused)
        XCTAssertEqual(e1.playCallCount, 2) // 1 from setWallpaper + 1 from setPaused(false)
        XCTAssertEqual(e2.playCallCount, 2)

        // Muted
        manager.setMuted(false)
        XCTAssertFalse(manager.isMuted)
        XCTAssertFalse(e1.isMuted)
        XCTAssertFalse(e2.isMuted)

        // Volume
        manager.setVolume(0.75)
        XCTAssertEqual(manager.volume, 0.75)
        XCTAssertEqual(e1.volume, 0.75)
        XCTAssertEqual(e2.volume, 0.75)

        // NaN Volume
        manager.setVolume(Float.nan)
        XCTAssertEqual(manager.volume, 0.0)
        XCTAssertEqual(e1.volume, 0.0)
        XCTAssertEqual(e2.volume, 0.0)

        // Interactive
        manager.isInteractive = true
        XCTAssertTrue(manager.isInteractive)
        XCTAssertTrue(e1.isInteractive)
        XCTAssertTrue(e2.isInteractive)
        XCTAssertTrue(manager.windows[10]?.isInteractive == true)
        XCTAssertTrue(manager.windows[20]?.isInteractive == true)
    }

    func testWindowManagerChangingWallpaperTerminatesPreviousEngines() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        let itemA = WallpaperItem(title: "Wallpaper A", type: .video, pathOrURL: "/a.mp4")
        manager.setWallpaper(itemA)
        let engineA = manager.engines[1] as! MockWallpaperEngine

        let itemB = WallpaperItem(title: "Wallpaper B", type: .web, pathOrURL: "/b")
        manager.setWallpaper(itemB)
        let engineB = manager.engines[1] as! MockWallpaperEngine

        XCTAssertTrue(engineA.isTerminated)
        XCTAssertEqual(engineA.terminateCallCount, 1)
        XCTAssertFalse(engineB.isTerminated)
        XCTAssertTrue(manager.windows[1]?.contentView === engineB.view)
    }

    func testWindowManagerHotPluggingDisplayMountsEngine() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        manager.setVolume(0.65)
        manager.setMuted(false)
        manager.isInteractive = true
        let item = WallpaperItem(title: "HotPlug", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)

        XCTAssertEqual(manager.engines.count, 1)

        // Add display 2
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        manager.reloadDisplays()

        XCTAssertEqual(manager.engines.count, 2)
        let engine2 = manager.engines[2] as! MockWallpaperEngine
        XCTAssertEqual(engine2.volume, 0.65)
        XCTAssertFalse(engine2.isMuted)
        XCTAssertTrue(engine2.isInteractive)
        XCTAssertTrue(manager.windows[2]?.contentView === engine2.view)
    }

    func testWindowManagerUnpluggingDisplayTerminatesEngine() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayDescriptor(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        let item = WallpaperItem(title: "Unplug", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)

        let engine2 = manager.engines[2] as! MockWallpaperEngine

        // Unplug display 2
        mockProvider.screens = [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ]
        manager.reloadDisplays()

        XCTAssertEqual(manager.engines.count, 1)
        XCTAssertNil(manager.engines[2])
        XCTAssertNil(manager.windows[2])
        XCTAssertTrue(engine2.isTerminated)
        XCTAssertEqual(engine2.terminateCallCount, 1)
    }

    func testWindowManagerTerminateTearsDownEverything() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }

        let item = WallpaperItem(title: "Term", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)
        let engine = manager.engines[1] as! MockWallpaperEngine

        manager.terminate()

        XCTAssertTrue(engine.isTerminated)
        XCTAssertEqual(manager.engines.count, 0)
        XCTAssertEqual(manager.windows.count, 0)
        XCTAssertNil(manager.activeWallpaper)
    }

    func testWindowManagerErrorForwardingToDelegate() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        let delegate = MockEngineDelegate()
        manager.engineDelegate = delegate

        var errorCallbackReceived = false
        manager.onEngineError = { _, _ in
            errorCallbackReceived = true
        }

        let item = WallpaperItem(title: "Err", type: .video, pathOrURL: "/test.mp4")
        manager.setWallpaper(item)

        let engine = manager.engines[1] as! MockWallpaperEngine
        engine.simulateError(WallpaperEngineError.corruptMedia("corrupt"))

        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertTrue(errorCallbackReceived)
    }

    func testWindowManagerRapidWallpaperSwitchingUnderConcurrency() {
        let mockProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        let manager = DesktopWindowManager(screenProvider: mockProvider) { item in
            MockWallpaperEngine(item: item)
        }
        defer { manager.terminate() }

        var createdEngines: [MockWallpaperEngine] = []
        for i in 1...30 {
            let item = WallpaperItem(title: "Switch \(i)", type: .video, pathOrURL: "/v\(i).mp4")
            manager.setWallpaper(item)
            if let currentEngine = manager.engines[1] as? MockWallpaperEngine {
                createdEngines.append(currentEngine)
            }
        }

        XCTAssertEqual(createdEngines.count, 30)
        for i in 0..<29 {
            XCTAssertTrue(createdEngines[i].isTerminated)
            XCTAssertEqual(createdEngines[i].terminateCallCount, 1)
        }
        XCTAssertFalse(createdEngines[29].isTerminated)
        XCTAssertEqual(manager.engines.count, 1)
        XCTAssertTrue(manager.windows[1]?.contentView === createdEngines[29].view)
    }
}
