import Foundation
import AppKit
import XCTest
import WebKit
import AVFoundation

// MARK: - Core Protocols and Types (Interface Contracts)

public struct PauseReasons: OptionSet, Sendable, CustomStringConvertible {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let userPaused        = PauseReasons(rawValue: 1 << 0)
    public static let fullscreenApp     = PauseReasons(rawValue: 1 << 1)
    public static let displaySleeping   = PauseReasons(rawValue: 1 << 2)
    public static let screenLocked      = PauseReasons(rawValue: 1 << 3)
    public static let batterySaver      = PauseReasons(rawValue: 1 << 4)

    public var description: String {
        var reasons: [String] = []
        if contains(.userPaused) { reasons.append("userPaused") }
        if contains(.fullscreenApp) { reasons.append("fullscreenApp") }
        if contains(.displaySleeping) { reasons.append("displaySleeping") }
        if contains(.screenLocked) { reasons.append("screenLocked") }
        if contains(.batterySaver) { reasons.append("batterySaver") }
        return reasons.isEmpty ? "none" : reasons.joined(separator: ", ")
    }
}

public enum WallpaperType: String, Codable, Sendable {
    case video
    case web
    case url
}

public struct WallpaperItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var type: WallpaperType
    public var sourceURL: URL
    public var thumbnailURL: URL?
    public var duration: TimeInterval?

    public init(id: UUID = UUID(), title: String, type: WallpaperType, sourceURL: URL, thumbnailURL: URL? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.sourceURL = sourceURL
        self.thumbnailURL = thumbnailURL
        self.duration = duration
    }
}

public struct LivelyInfo: Codable, Sendable {
    public let title: String?
    public let thumbnail: String?
    public let preview: String?
    public let desc: String?
    public let author: String?
    public let license: String?
    public let contact: String?
    public let type: String?
    public let fileName: String?

    public init(title: String? = nil, thumbnail: String? = nil, preview: String? = nil, desc: String? = nil, author: String? = nil, license: String? = nil, contact: String? = nil, type: String? = nil, fileName: String? = nil) {
        self.title = title
        self.thumbnail = thumbnail
        self.preview = preview
        self.desc = desc
        self.author = author
        self.license = license
        self.contact = contact
        self.type = type
        self.fileName = fileName
    }
}

public protocol WallpaperEngineDelegate: AnyObject {
    func engineDidEncounterError(_ engine: WallpaperEngine, error: Error)
    func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool)
}

public protocol WallpaperEngine: AnyObject {
    var view: NSView { get }
    var item: WallpaperItem { get }
    var isMuted: Bool { get set }
    var volume: Float { get set }
    var isInteractive: Bool { get set }
    var delegate: WallpaperEngineDelegate? { get set }

    func play()
    func pause()
    func terminate()
}

public protocol DesktopWindowManagerProtocol: AnyObject {
    var isInteractive: Bool { get set }
    var activeWallpaper: WallpaperItem? { get }
    
    func setWallpaper(_ item: WallpaperItem)
    func setPaused(_ paused: Bool)
    func setMuted(_ muted: Bool)
    func setVolume(_ volume: Float)
    func reloadDisplays()
    func terminate()
}

public protocol PowerManagerDelegate: AnyObject {
    func powerManagerDidChangePauseState(_ manager: PowerManagerProtocol, isPaused: Bool, reasons: PauseReasons)
}

public protocol PowerManagerProtocol: AnyObject {
    var delegate: PowerManagerDelegate? { get set }
    var currentPauseReasons: PauseReasons { get }
    var isPaused: Bool { get }
    
    func startMonitoring()
    func stopMonitoring()
}

// MARK: - Simulated Screen Model

public struct SimulatedScreen: Equatable, Sendable {
    public let id: Int
    public var frame: CGRect
    public var scaleFactor: CGFloat

    public init(id: Int, frame: CGRect, scaleFactor: CGFloat = 2.0) {
        self.id = id
        self.frame = frame
        self.scaleFactor = scaleFactor
    }
}

// MARK: - Headless Desktop Window

public final class HeadlessDesktopWindow: @unchecked Sendable {
    public let screenID: Int
    public var frame: CGRect
    public var windowLevel: CGWindowLevel
    public var ignoresMouseEvents: Bool
    public var collectionBehavior: NSWindow.CollectionBehavior
    public var isOpaque: Bool
    public var backgroundColor: NSColor
    public var styleMask: NSWindow.StyleMask
    public var contentView: NSView?
    public var isKeyWindow: Bool = false
    public var isVisible: Bool = true

    public init(screenID: Int, frame: CGRect) {
        self.screenID = screenID
        self.frame = frame
        self.windowLevel = CGWindowLevelForKey(.desktopWindow)
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.styleMask = [.borderless]
    }

    public func hitTest(_ point: CGPoint) -> NSView? {
        if ignoresMouseEvents {
            return nil
        }
        guard frame.contains(point) else {
            return nil
        }
        return contentView
    }
}

// MARK: - Mock Video Wallpaper Engine

public final class MockVideoWallpaperEngine: WallpaperEngine, @unchecked Sendable {
    public let view: NSView
    public let item: WallpaperItem
    public weak var delegate: WallpaperEngineDelegate?

    private var _volume: Float = 1.0
    public var volume: Float {
        get { _volume }
        set {
            if newValue.isNaN || newValue.isInfinite {
                _volume = 0.0
            } else {
                _volume = max(0.0, min(1.0, newValue))
            }
        }
    }

    public var isMuted: Bool = false
    public var isInteractive: Bool = false
    public private(set) var isPlaying: Bool = false
    public private(set) var loopCount: Int = 0
    public private(set) var isTerminated: Bool = false
    public private(set) var duration: TimeInterval = 10.0

    public enum EngineError: LocalizedError {
        case corruptFile
        case zeroByteFile
        case missingFile
        case unsupportedFormat

        public var errorDescription: String? {
            switch self {
            case .corruptFile: return "Video file is corrupt"
            case .zeroByteFile: return "Video file is 0 bytes"
            case .missingFile: return "Video file does not exist"
            case .unsupportedFormat: return "Unsupported video format"
            }
        }
    }

    public private(set) var hasError: Bool = false

    public init(item: WallpaperItem, initialVolume: Float = 1.0, initialMuted: Bool = false, delegate: WallpaperEngineDelegate? = nil) {
        self.item = item
        self.view = NSView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        self.volume = initialVolume
        self.isMuted = initialMuted
        self.delegate = delegate
        if let d = item.duration {
            self.duration = d
        }
        validateAsset()
    }

    public func validateAsset() {
        let path = item.sourceURL.path
        if !FileManager.default.fileExists(atPath: path) {
            hasError = true
            delegate?.engineDidEncounterError(self, error: EngineError.missingFile)
            return
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size == 0 {
            hasError = true
            delegate?.engineDidEncounterError(self, error: EngineError.zeroByteFile)
            return
        }
        if let data = try? Data(contentsOf: item.sourceURL, options: .mappedIfSafe),
           data.starts(with: [0xDE, 0xAD, 0xBE, 0xEF]) {
            hasError = true
            delegate?.engineDidEncounterError(self, error: EngineError.corruptFile)
            return
        }
    }

    public func play() {
        guard !isTerminated else { return }
        validateAsset()
        guard !hasError else { return }
        isPlaying = true
        delegate?.engineDidChangePlaybackState(self, isPlaying: true)
    }

    public func pause() {
        guard !isTerminated else { return }
        isPlaying = false
        delegate?.engineDidChangePlaybackState(self, isPlaying: false)
    }

    public func simulateLoopIteration() {
        guard isPlaying else { return }
        loopCount += 1
    }

    public func terminate() {
        isPlaying = false
        isTerminated = true
    }
}

// MARK: - Mock Web Wallpaper Engine

public final class MockWebWallpaperEngine: WallpaperEngine, @unchecked Sendable {
    public let view: NSView
    public let item: WallpaperItem
    public weak var delegate: WallpaperEngineDelegate?

    public var drawsBackground: Bool = false
    public var contextMenuSuppressed: Bool = true
    public var isMuted: Bool = false
    public var volume: Float = 1.0
    public var isInteractive: Bool = false
    public private(set) var isPlaying: Bool = true
    public private(set) var isSuspended: Bool = false
    public private(set) var rafSuspended: Bool = false
    public private(set) var mediaSuspended: Bool = false
    public private(set) var isTerminated: Bool = false
    public private(set) var navigationState: NavigationState = .idle
    public private(set) var reloadCount: Int = 0

    public enum NavigationState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public enum WebEngineError: LocalizedError {
        case missingIndexFile
        case invalidURLScheme
        case unreachableHost
        case processCrashed

        public var errorDescription: String? {
            switch self {
            case .missingIndexFile: return "Missing index.html entrypoint"
            case .invalidURLScheme: return "Invalid URL scheme"
            case .unreachableHost: return "Network host unreachable"
            case .processCrashed: return "WebKit process crashed"
            }
        }
    }

    public init(item: WallpaperItem) {
        self.item = item
        self.view = NSView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        loadContent()
    }

    public func loadContent() {
        navigationState = .loading
        if item.type == .web {
            let indexPath = item.sourceURL.appendingPathComponent("index.html").path
            if !FileManager.default.fileExists(atPath: indexPath) && !item.sourceURL.path.hasSuffix("index.html") {
                navigationState = .failed("Missing index.html")
                delegate?.engineDidEncounterError(self, error: WebEngineError.missingIndexFile)
                return
            }
            navigationState = .loaded
        } else if item.type == .url {
            guard let scheme = item.sourceURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                navigationState = .failed("Invalid scheme")
                delegate?.engineDidEncounterError(self, error: WebEngineError.invalidURLScheme)
                return
            }
            if item.sourceURL.host?.contains("doesnotexist") == true {
                navigationState = .failed("Unreachable host")
                delegate?.engineDidEncounterError(self, error: WebEngineError.unreachableHost)
                return
            }
            navigationState = .loaded
        }
    }

    public func reload() {
        reloadCount += 1
        loadContent()
    }

    public func simulateCrash() {
        navigationState = .failed("Process crashed")
        delegate?.engineDidEncounterError(self, error: WebEngineError.processCrashed)
    }

    public func play() {
        guard !isTerminated else { return }
        isPlaying = true
        isSuspended = false
        rafSuspended = false
        mediaSuspended = false
        delegate?.engineDidChangePlaybackState(self, isPlaying: true)
    }

    public func pause() {
        guard !isTerminated else { return }
        isPlaying = false
        isSuspended = true
        rafSuspended = true
        mediaSuspended = true
        delegate?.engineDidChangePlaybackState(self, isPlaying: false)
    }

    public func terminate() {
        isPlaying = false
        isSuspended = true
        isTerminated = true
    }
}

// MARK: - Headless Desktop Window Manager

public final class HeadlessDesktopWindowManager: DesktopWindowManagerProtocol, @unchecked Sendable {
    public var isInteractive: Bool = false {
        didSet {
            updateWindowLevelsAndInteraction()
        }
    }
    public private(set) var activeWallpaper: WallpaperItem?
    public private(set) var activeEngine: WallpaperEngine?
    public private(set) var windows: [HeadlessDesktopWindow] = []
    public private(set) var screens: [SimulatedScreen] = []

    public var isPaused: Bool = false {
        didSet {
            if isPaused {
                activeEngine?.pause()
            } else {
                activeEngine?.play()
            }
        }
    }

    public var isMuted: Bool = false {
        didSet {
            activeEngine?.isMuted = isMuted
        }
    }

    public var volume: Float = 1.0 {
        didSet {
            activeEngine?.volume = volume
        }
    }

    public init(screens: [SimulatedScreen] = [SimulatedScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))]) {
        self.screens = screens
        rebuildWindows()
    }

    public func updateScreens(_ newScreens: [SimulatedScreen]) {
        self.screens = newScreens
        rebuildWindows()
    }

    private func rebuildWindows() {
        windows = screens.map { screen in
            let window = HeadlessDesktopWindow(screenID: screen.id, frame: screen.frame)
            if let view = activeEngine?.view {
                window.contentView = view
            }
            window.ignoresMouseEvents = !isInteractive
            window.windowLevel = isInteractive ? (CGWindowLevelForKey(.desktopIconWindow) + 1) : CGWindowLevelForKey(.desktopWindow)
            return window
        }
    }

    private func updateWindowLevelsAndInteraction() {
        let level = isInteractive ? (CGWindowLevelForKey(.desktopIconWindow) + 1) : CGWindowLevelForKey(.desktopWindow)
        for window in windows {
            window.windowLevel = level
            window.ignoresMouseEvents = !isInteractive
            window.isKeyWindow = isInteractive
        }
        activeEngine?.isInteractive = isInteractive
    }

    public func setWallpaper(_ item: WallpaperItem) {
        activeEngine?.terminate()
        activeWallpaper = item
        switch item.type {
        case .video:
            let engine = MockVideoWallpaperEngine(item: item, initialVolume: volume, initialMuted: isMuted)
            engine.isInteractive = isInteractive
            activeEngine = engine
            if !isPaused { engine.play() }
        case .web, .url:
            let engine = MockWebWallpaperEngine(item: item)
            engine.isInteractive = isInteractive
            engine.isMuted = isMuted
            engine.volume = volume
            activeEngine = engine
            if isPaused { engine.pause() } else { engine.play() }
        }
        for window in windows {
            window.contentView = activeEngine?.view
        }
    }

    public func setPaused(_ paused: Bool) {
        self.isPaused = paused
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
    }

    public func setVolume(_ volume: Float) {
        self.volume = volume
    }

    public func reloadDisplays() {
        rebuildWindows()
    }

    public func terminate() {
        activeEngine?.terminate()
        activeEngine = nil
        activeWallpaper = nil
        for window in windows {
            window.isVisible = false
        }
        windows.removeAll()
    }
}

// MARK: - Mock Power Manager

public final class MockPowerManager: PowerManagerProtocol, @unchecked Sendable {
    public weak var delegate: PowerManagerDelegate?
    public private(set) var currentPauseReasons: PauseReasons = []
    public private(set) var isMonitoring: Bool = false

    public var isPaused: Bool {
        return !currentPauseReasons.isEmpty
    }

    public init() {}

    public func startMonitoring() {
        isMonitoring = true
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    public func addPauseReason(_ reason: PauseReasons) {
        let previousState = isPaused
        currentPauseReasons.insert(reason)
        let newState = isPaused
        if previousState != newState || true {
            delegate?.powerManagerDidChangePauseState(self, isPaused: newState, reasons: currentPauseReasons)
        }
    }

    public func removePauseReason(_ reason: PauseReasons) {
        let previousState = isPaused
        currentPauseReasons.remove(reason)
        let newState = isPaused
        if previousState != newState || true {
            delegate?.powerManagerDidChangePauseState(self, isPaused: newState, reasons: currentPauseReasons)
        }
    }

    public func simulateFullscreenApp(isActive: Bool) {
        if isActive {
            addPauseReason(.fullscreenApp)
        } else {
            removePauseReason(.fullscreenApp)
        }
    }

    public func simulateDisplaySleep() {
        addPauseReason(.displaySleeping)
    }

    public func simulateDisplayWake() {
        removePauseReason(.displaySleeping)
    }

    public func simulateScreenLock() {
        addPauseReason(.screenLocked)
    }

    public func simulateScreenUnlock() {
        removePauseReason(.screenLocked)
    }

    public func simulateBatteryPower(saverActive: Bool) {
        if saverActive {
            addPauseReason(.batterySaver)
        } else {
            removePauseReason(.batterySaver)
        }
    }

    public func simulateUserPause(isPaused: Bool) {
        if isPaused {
            addPauseReason(.userPaused)
        } else {
            removePauseReason(.userPaused)
        }
    }
}

// MARK: - Mock Status Item Companion Controller

public final class MockStatusItemController: @unchecked Sendable {
    public var title: String = "Lively Wallpaper"
    public var iconName: String = "sparkles.tv"
    public var playPauseTitle: String = "Pause"
    public var muteTitle: String = "Mute"
    public var isInteractiveChecked: Bool = false
    public var quickPickerWallpapers: [WallpaperItem] = []
    public var isManagerOpen: Bool = false
    public var isTerminated: Bool = false

    public init() {}

    public func update(isPaused: Bool, isMuted: Bool, isInteractive: Bool, wallpapers: [WallpaperItem]) {
        self.playPauseTitle = isPaused ? "Resume" : "Pause"
        self.muteTitle = isMuted ? "Unmute" : "Mute"
        self.isInteractiveChecked = isInteractive
        self.quickPickerWallpapers = wallpapers
    }
}

// MARK: - Mock Wallpaper Library Store

public final class MockWallpaperLibrary: @unchecked Sendable {
    public private(set) var items: [WallpaperItem] = []

    public init(items: [WallpaperItem] = []) {
        self.items = items
    }

    public func add(_ item: WallpaperItem) throws {
        if items.contains(where: { $0.id == item.id || $0.sourceURL == item.sourceURL }) {
            return
        }
        items.append(item)
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func find(id: UUID) -> WallpaperItem? {
        items.first { $0.id == id }
    }

    public func importFile(url: URL) throws -> WallpaperItem {
        let ext = url.pathExtension.lowercased()
        if ext == "mp4" || ext == "mov" {
            let item = WallpaperItem(title: url.deletingPathExtension().lastPathComponent, type: .video, sourceURL: url)
            try add(item)
            return item
        } else if url.hasDirectoryPath || FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path) {
            let item = WallpaperItem(title: url.lastPathComponent, type: .web, sourceURL: url)
            try add(item)
            return item
        } else {
            throw MockWebWallpaperEngine.WebEngineError.invalidURLScheme
        }
    }

    public func importURL(urlString: String) throws -> WallpaperItem {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw MockWebWallpaperEngine.WebEngineError.invalidURLScheme
        }
        let item = WallpaperItem(title: url.host ?? "Remote Web", type: .url, sourceURL: url)
        try add(item)
        return item
    }
}

// MARK: - Temporary Asset Helper

public final class TemporaryAssetHelper: @unchecked Sendable {
    private var createdURLs: [URL] = []

    public init() {}

    deinit {
        cleanup()
    }

    public func cleanup() {
        for url in createdURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdURLs.removeAll()
    }

    public func createSampleVideoMP4() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("sample_\(UUID().uuidString).mp4")
        let dummyData = Data(repeating: 0x00, count: 1024)
        try? dummyData.write(to: fileURL)
        createdURLs.append(fileURL)
        return fileURL
    }

    public func createSampleVideoMOV() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("sample_\(UUID().uuidString).mov")
        let dummyData = Data(repeating: 0x00, count: 1024)
        try? dummyData.write(to: fileURL)
        createdURLs.append(fileURL)
        return fileURL
    }

    public func createCorruptVideoFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("corrupt_\(UUID().uuidString).mp4")
        let corruptBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03]
        try? Data(corruptBytes).write(to: fileURL)
        createdURLs.append(fileURL)
        return fileURL
    }

    public func createZeroByteFile(extension ext: String = "mp4") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("zerobyte_\(UUID().uuidString).\(ext)")
        try? Data().write(to: fileURL)
        createdURLs.append(fileURL)
        return fileURL
    }

    public func createSampleWebFolder(withIndex: Bool = true, customHTML: String? = nil) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let folderURL = tempDir.appendingPathComponent("web_wallpaper_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        if withIndex {
            let indexURL = folderURL.appendingPathComponent("index.html")
            let htmlContent = customHTML ?? """
            <!DOCTYPE html>
            <html>
            <head><title>Test Wallpaper</title></head>
            <body style="background: transparent;">
                <canvas id="c"></canvas>
                <script>
                    const c = document.getElementById('c');
                    function loop() { requestAnimationFrame(loop); }
                    loop();
                </script>
            </body>
            </html>
            """
            try? htmlContent.data(using: .utf8)?.write(to: indexURL)
        }
        createdURLs.append(folderURL)
        return folderURL
    }

    public func createDeeplyNestedWebFolder(depth: Int = 20) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        var currentURL = tempDir.appendingPathComponent("deep_\(UUID().uuidString)", isDirectory: true)
        for i in 1...depth {
            currentURL = currentURL.appendingPathComponent("level_\(i)", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: currentURL, withIntermediateDirectories: true)
        let indexURL = currentURL.appendingPathComponent("index.html")
        let html = "<html><body>Deeply Nested</body></html>"
        try? html.data(using: .utf8)?.write(to: indexURL)
        createdURLs.append(tempDir.appendingPathComponent("deep_\(UUID().uuidString)"))
        return currentURL
    }
}

// MARK: - E2E Headless Test Environment

public final class E2ETestEnvironment: PowerManagerDelegate, @unchecked Sendable {
    public let windowManager: HeadlessDesktopWindowManager
    public let powerManager: MockPowerManager
    public let statusItemController: MockStatusItemController
    public let library: MockWallpaperLibrary
    public let assetHelper: TemporaryAssetHelper

    public private(set) var pauseHistory: [(isPaused: Bool, reasons: PauseReasons)] = []

    public init(screens: [SimulatedScreen] = [SimulatedScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))]) {
        self.assetHelper = TemporaryAssetHelper()
        self.windowManager = HeadlessDesktopWindowManager(screens: screens)
        self.powerManager = MockPowerManager()
        self.statusItemController = MockStatusItemController()
        self.library = MockWallpaperLibrary()

        self.powerManager.delegate = self
        self.powerManager.startMonitoring()
    }

    deinit {
        assetHelper.cleanup()
        windowManager.terminate()
        powerManager.stopMonitoring()
    }

    public func powerManagerDidChangePauseState(_ manager: PowerManagerProtocol, isPaused: Bool, reasons: PauseReasons) {
        pauseHistory.append((isPaused: isPaused, reasons: reasons))
        windowManager.setPaused(isPaused)
        statusItemController.update(
            isPaused: isPaused,
            isMuted: windowManager.isMuted,
            isInteractive: windowManager.isInteractive,
            wallpapers: library.items
        )
    }

    public func setWallpaper(_ item: WallpaperItem) {
        windowManager.setWallpaper(item)
        statusItemController.update(
            isPaused: windowManager.isPaused,
            isMuted: windowManager.isMuted,
            isInteractive: windowManager.isInteractive,
            wallpapers: library.items
        )
    }

    public func togglePlayPause() {
        let targetPause = !windowManager.isPaused
        powerManager.simulateUserPause(isPaused: targetPause)
    }

    public func toggleMute() {
        let targetMute = !windowManager.isMuted
        windowManager.setMuted(targetMute)
        statusItemController.update(
            isPaused: windowManager.isPaused,
            isMuted: targetMute,
            isInteractive: windowManager.isInteractive,
            wallpapers: library.items
        )
    }

    public func setVolume(_ volume: Float) {
        windowManager.setVolume(volume)
    }

    public func toggleInteractiveMode() {
        let target = !windowManager.isInteractive
        windowManager.isInteractive = target
        statusItemController.update(
            isPaused: windowManager.isPaused,
            isMuted: windowManager.isMuted,
            isInteractive: target,
            wallpapers: library.items
        )
    }

    public func addScreen(_ screen: SimulatedScreen) {
        var current = windowManager.screens
        current.append(screen)
        windowManager.updateScreens(current)
    }

    public func removeScreen(id: Int) {
        var current = windowManager.screens
        current.removeAll { $0.id == id }
        windowManager.updateScreens(current)
    }

    public func updateScreen(id: Int, newFrame: CGRect) {
        var current = windowManager.screens
        if let idx = current.firstIndex(where: { $0.id == id }) {
            current[idx].frame = newFrame
            windowManager.updateScreens(current)
        }
    }

    public func terminate() {
        windowManager.terminate()
        powerManager.stopMonitoring()
        statusItemController.isTerminated = true
    }
}
