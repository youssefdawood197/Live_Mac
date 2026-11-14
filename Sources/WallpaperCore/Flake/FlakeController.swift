import AppKit
import SpriteKit
import AVFoundation

/// Coordinates Flake ambient snow overlay windows across multiple displays,
/// synchronizes power saving states, and manages ambient audio.
@MainActor
public final class FlakeController: NSObject, PowerManagerDelegate {

    // MARK: - State

    public private(set) var overlayWindows: [CGDirectDisplayID: FlakeOverlayWindow] = [:]
    public var config: FlakeConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    public let screenProvider: any ScreenProviderProtocol
    public weak var powerManager: (any PowerManagerProtocol)?
    public let surfaceDetector: any WindowSurfaceDetectorProtocol

    private var screenObserver: (any NSObjectProtocol)?
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 0.1 // 10 Hz
    public private(set) var isPaused: Bool = false

    // Ambient sound player
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Initialization

    public init(
        config: FlakeConfiguration = FlakeConfiguration(),
        powerManager: (any PowerManagerProtocol)? = nil,
        screenProvider: any ScreenProviderProtocol = SystemScreenProvider(),
        surfaceDetector: any WindowSurfaceDetectorProtocol = WindowSurfaceDetector()
    ) {
        self.config = config
        self.powerManager = powerManager
        self.screenProvider = screenProvider
        self.surfaceDetector = surfaceDetector
        super.init()

        powerManager?.delegate = self
        setupScreenObserver()
        if config.isEnabled && config.layerMode == .overlay {
            rebuildOverlayWindows()
            startPolling()
        }
    }

    isolated deinit {
        terminate()
    }

    public func terminate() {
        stopPolling()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        closeAllOverlayWindows()
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - 10 Hz Polling Management (Feature 7)

    public func startPolling() {
        stopPolling()
        guard config.isEnabled && config.layerMode == .overlay && !isPaused else { return }

        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollSurfaces()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollingTimer = timer
    }

    public func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    public func pollSurfaces() {
        guard config.isEnabled && !isPaused else { return }
        for (_, window) in overlayWindows {
            window.flakeScene.updateSurfaces()
        }
    }

    // MARK: - Display Management

    private func setupScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildOverlayWindows()
            }
        }
    }

    public func rebuildOverlayWindows() {
        guard config.isEnabled && config.layerMode == .overlay else {
            closeAllOverlayWindows()
            return
        }

        let screens = screenProvider.screens
        let currentDisplayIDs = Set(screens.map { $0.displayID })

        // Remove disconnected screen windows
        for (id, window) in overlayWindows where !currentDisplayIDs.contains(id) {
            window.orderOut(nil)
            window.close()
            overlayWindows.removeValue(forKey: id)
        }

        // Add or update overlay window per screen
        for screen in screens {
            let id = screen.displayID
            if let window = overlayWindows[id] {
                if window.frame != screen.frame {
                    window.updateFrame(screen.frame)
                }
            } else {
                let window = FlakeOverlayWindow(
                    frame: screen.frame,
                    config: config,
                    surfaceDetector: surfaceDetector
                )
                window.orderFront(nil)
                overlayWindows[id] = window
            }
        }
    }

    public func closeAllOverlayWindows() {
        for (_, window) in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }

    // MARK: - Configuration Updates

    public func applyConfiguration() {
        if config.isEnabled && config.layerMode == .overlay {
            if overlayWindows.isEmpty {
                rebuildOverlayWindows()
            }
            for (_, window) in overlayWindows {
                window.flakeScene.config = config
                window.updateMouseInteractivity()
            }
            if !isPaused && pollingTimer == nil {
                startPolling()
            }
        } else {
            stopPolling()
            closeAllOverlayWindows()
        }

        updateAmbientAudio()
    }

    // MARK: - Power & Pause Handling (PowerManagerDelegate)

    public func setPaused(_ paused: Bool) {
        guard self.isPaused != paused else { return }
        self.isPaused = paused

        for (_, window) in overlayWindows {
            window.skView.isPaused = paused
        }

        if paused {
            stopPolling()
            audioPlayer?.pause()
        } else {
            if config.isEnabled && config.layerMode == .overlay {
                startPolling()
            }
            if config.ambientSoundEnabled {
                audioPlayer?.play()
            }
        }
    }

    public func powerManagerDidChangePauseState(
        _ manager: any PowerManagerProtocol,
        isPaused: Bool,
        reasons: PauseReasons
    ) {
        setPaused(isPaused)
    }

    public func clearAllSnow() {
        for (_, window) in overlayWindows {
            window.flakeScene.clearAllSnow()
        }
    }

    // MARK: - Ambient Audio

    private func updateAmbientAudio() {
        if config.isEnabled && config.ambientSoundEnabled {
            if audioPlayer == nil {
                // Looped ambient winter audio player
            }
            audioPlayer?.volume = config.soundVolume
            if !isPaused {
                audioPlayer?.play()
            }
        } else {
            audioPlayer?.stop()
        }
    }
}
