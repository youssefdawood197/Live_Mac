import AppKit
import AVFoundation

// MARK: - VideoEngineError

public enum VideoEngineError: LocalizedError, Sendable, Equatable {
    case missingFile(URL)
    case zeroByteFile(URL)
    case corruptFile(URL)
    case missingVideoTrack(URL)
    case unsupportedFormat(String)
    case playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let url):
            return "Video file does not exist at path: \(url.path)"
        case .zeroByteFile(let url):
            return "Video file is 0 bytes at path: \(url.path)"
        case .corruptFile(let url):
            return "Video file is corrupt or unreadable at path: \(url.path)"
        case .missingVideoTrack(let url):
            return "Video file contains no video tracks at path: \(url.path)"
        case .unsupportedFormat(let ext):
            return "Unsupported video format: '\(ext)'. Only MP4, MOV, and M4V are supported."
        case .playbackFailed(let reason):
            return "Video playback failed: \(reason)"
        }
    }
}

// MARK: - VideoPlayerView

public final class VideoPlayerView: NSView {
    public override func makeBackingLayer() -> CALayer {
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return playerLayer
    }

    public var playerLayer: AVPlayerLayer {
        guard let layer = self.layer as? AVPlayerLayer else {
            fatalError("Backing layer is unexpectedly not an AVPlayerLayer")
        }
        return layer
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        autoresizingMask = [.width, .height]
    }
}

// MARK: - VideoWallpaperEngine

@MainActor
public final class VideoWallpaperEngine: WallpaperEngine {

    // MARK: - Properties

    public let item: WallpaperItem
    public private(set) var lastEncounteredError: Error?

    public weak var delegate: WallpaperEngineDelegate? {
        didSet {
            if let error = lastEncounteredError {
                delegate?.engineDidEncounterError(self, error: error)
            }
        }
    }

    public var isInteractive: Bool = false

    private let playerView: VideoPlayerView
    public var view: NSView { playerView }

    public let player: AVQueuePlayer
    public private(set) var looper: AVPlayerLooper?
    public private(set) var playerItem: AVPlayerItem?

    public private(set) var isPlaying: Bool = false
    public private(set) var isTerminated: Bool = false
    public private(set) var hasError: Bool = false
    public private(set) var loopCount: Int = 0
    public private(set) var duration: TimeInterval = 0.0

    // MARK: - Audio Helpers

    /// Sanitizes and defensively clamps volume values into the valid [0.0, 1.0] audio range.
    /// Non-finite values (NaN, +Infinity, -Infinity) are safely muted to 0.0.
    public static func clampVolume(_ value: Float) -> Float {
        guard !value.isNaN, !value.isInfinite else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }

    private var _volume: Float = 1.0
    public var volume: Float {
        get { _volume }
        set {
            _volume = VideoWallpaperEngine.clampVolume(newValue)
            player.volume = _volume
        }
    }

    private var _isMuted: Bool = true
    public var isMuted: Bool {
        get { _isMuted }
        set {
            _isMuted = newValue
            player.isMuted = newValue
        }
    }

    // Observers & Async Tasks
    private var didPlayToEndObserver: (any NSObjectProtocol)?
    private var looperStatusObservation: NSKeyValueObservation?
    private var looperCountObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var durationTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        item: WallpaperItem,
        initialVolume: Float? = nil,
        initialMuted: Bool? = nil,
        delegate: WallpaperEngineDelegate? = nil
    ) {
        self.item = item
        self.delegate = delegate
        self.playerView = VideoPlayerView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        self.player = AVQueuePlayer()
        self.playerView.playerLayer.player = player

        // Configure initial volume & mute
        let chosenVolume = initialVolume ?? item.volume
        self._volume = VideoWallpaperEngine.clampVolume(chosenVolume)
        self.player.volume = self._volume

        self._isMuted = initialMuted ?? item.isMuted
        self.player.isMuted = self._isMuted

        setupEngine()
    }

    isolated deinit {
        terminate()
    }

    // MARK: - Container Pre-flight Validation

    /// Validates that the local file at `url` conforms to the ISO Base Media File Format (MP4 / M4V)
    /// or Apple QuickTime File Format (MOV) container structure.
    ///
    /// Inspects the initial 8–16 bytes to ensure a valid container box/atom header exists:
    /// - Minimum file size of 8 bytes (4-byte box size + 4-byte FourCC type).
    /// - Box size syntax validity (size cannot be in 2..<8, and cannot exceed file size unless 0 or 1).
    /// - Valid top-level container box FourCC ('ftyp', 'moov', 'wide', 'free', 'skip', 'pnot', 'mdat').
    /// - Specific structural check for 'ftyp' boxes requiring minimum 16 bytes.
    private static func isValidContainerHeader(at url: URL) -> Bool {
        guard url.isFileURL else { return true }
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? fileHandle.close() }

        guard let headerData = try? fileHandle.read(upToCount: 16), headerData.count >= 8 else {
            return false
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        guard fileSize >= 8 else {
            return false
        }

        let boxSize = headerData.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard let fourCC = String(data: headerData.subdata(in: 4..<8), encoding: .ascii) else {
            return false
        }

        let validInitialBoxTypes: Set<String> = [
            "ftyp", // ISO Base Media File Type (MP4, M4V, modern QuickTime MOV)
            "moov", // Movie Resource Atom (classic QuickTime MOV)
            "wide", // QuickTime 64-bit expansion atom placeholder
            "free", // Free space placeholder atom
            "skip", // Skip space placeholder atom
            "pnot", // QuickTime Preview atom
            "mdat"  // Media Data atom
        ]

        guard validInitialBoxTypes.contains(fourCC) else {
            return false
        }

        // Structural validation: A box size in 2..<8 is illegal syntax in ISO BMFF / QTFF
        if boxSize >= 2 && boxSize < 8 {
            return false
        }

        // Specific 'ftyp' requirement: Header requires size + 'ftyp' + major_brand + minor_version >= 16 bytes
        if fourCC == "ftyp" && boxSize < 16 && boxSize != 1 {
            return false
        }

        // Box size cannot exceed total physical file size on disk unless 0 (extends to EOF) or 1 (64-bit largesize)
        if boxSize != 0 && boxSize != 1 && UInt64(boxSize) > fileSize {
            return false
        }

        return true
    }

    // MARK: - Engine Setup & Pre-flight

    private func setupEngine() {
        guard let url = item.resolvedURL else {
            failWithError(VideoEngineError.missingFile(URL(fileURLWithPath: item.pathOrURL)))
            return
        }

        let path = url.path

        // 1. Pre-flight check: File existence
        guard FileManager.default.fileExists(atPath: path) else {
            failWithError(VideoEngineError.missingFile(url))
            return
        }

        // 2. Pre-flight check: File size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size == 0 {
            failWithError(VideoEngineError.zeroByteFile(url))
            return
        }

        // 3. Pre-flight check: Extension support
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else {
            failWithError(VideoEngineError.unsupportedFormat(ext))
            return
        }

        // 4. Pre-flight check: Container format & structural header validation
        guard Self.isValidContainerHeader(at: url) else {
            failWithError(VideoEngineError.corruptFile(url))
            return
        }

        // 5. Initialize AVPlayerItem & AVPlayerLooper
        let asset = AVURLAsset(url: url)
        let templateItem = AVPlayerItem(asset: asset)
        self.playerItem = templateItem

        // Setup notification fallback observer
        setupNotificationObserver(for: templateItem)

        // Setup AVPlayerLooper
        let playerLooper = AVPlayerLooper(player: player, templateItem: templateItem)
        self.looper = playerLooper

        setupLooperObservations(playerLooper)
        setupItemObservations(templateItem)

        // Extract duration asynchronously using modern AVFoundation API
        durationTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            if let duration = try? await asset.load(.duration) {
                guard !Task.isCancelled else { return }
                let sec = CMTimeGetSeconds(duration)
                await MainActor.run { [weak self] in
                    guard let self = self, !self.isTerminated else { return }
                    if !sec.isNaN && !sec.isInfinite && sec > 0 {
                        self.duration = sec
                    }
                }
            }
        }
    }

    private func failWithError(_ error: Error) {
        hasError = true
        isPlaying = false
        lastEncounteredError = error
        delegate?.engineDidEncounterError(self, error: error)
    }

    // MARK: - Observations

    private func setupLooperObservations(_ looper: AVPlayerLooper) {
        looperStatusObservation = looper.observe(\.status, options: [.new]) { [weak self] observedLooper, _ in
            MainActor.assumeIsolated {
                guard let self = self, !self.isTerminated else { return }
                if observedLooper.status == .failed {
                    let message = observedLooper.error?.localizedDescription ?? "AVPlayerLooper status failed"
                    self.failWithError(VideoEngineError.playbackFailed(message))
                }
            }
        }

        looperCountObservation = looper.observe(\.loopCount, options: [.new]) { [weak self] observedLooper, _ in
            MainActor.assumeIsolated {
                guard let self = self, !self.isTerminated else { return }
                self.loopCount = observedLooper.loopCount
            }
        }
    }

    private func setupItemObservations(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if observedItem.status == .failed {
                    self.failWithError(VideoEngineError.corruptFile(self.item.resolvedURL ?? URL(fileURLWithPath: self.item.pathOrURL)))
                } else if observedItem.status == .readyToPlay {
                    let sec = CMTimeGetSeconds(observedItem.duration)
                    if !sec.isNaN && !sec.isInfinite && sec > 0 {
                        self.duration = sec
                    }
                }
            }
        }
    }

    private func setupNotificationObserver(for item: AVPlayerItem) {
        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let notifItem = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self = self, !self.isTerminated else { return }
                guard let notifItem = notifItem,
                      notifItem === self.playerItem || self.player.items().contains(notifItem) else { return }
                // If looper is nil or failed, execute fallback zero-tolerance seek
                if self.looper == nil || self.looper?.status == .failed {
                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                        Task { @MainActor [weak self] in
                            guard finished, let self = self, !self.isTerminated, self.isPlaying else { return }
                            self.player.play()
                        }
                    }
                    self.loopCount += 1
                }
            }
        }
    }

    // MARK: - Playback Controls

    public func play() {
        guard !isTerminated, !hasError else { return }
        guard !isPlaying else { return }
        player.play()
        isPlaying = true
        delegate?.engineDidChangePlaybackState(self, isPlaying: true)
    }

    public func pause() {
        guard !isTerminated else { return }
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        delegate?.engineDidChangePlaybackState(self, isPlaying: false)
    }

    // For testing and simulation
    public func simulateLoopIteration() {
        guard isPlaying else { return }
        loopCount += 1
    }

    // MARK: - Teardown

    public func terminate() {
        guard !isTerminated else { return }
        isTerminated = true
        isPlaying = false

        // 1. Cancel background duration task
        durationTask?.cancel()
        durationTask = nil

        // 2. Unregister notification observer
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }

        // 3. Invalidate and clear KVO observations
        looperStatusObservation?.invalidate()
        looperStatusObservation = nil
        looperCountObservation?.invalidate()
        looperCountObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        // 4. Dismantle playback pipeline
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.replaceCurrentItem(with: nil)
        player.removeAllItems()
        self.playerItem = nil

        // 5. Detach presentation layer and superview
        playerView.playerLayer.player = nil
        playerView.removeFromSuperview()
    }
}
