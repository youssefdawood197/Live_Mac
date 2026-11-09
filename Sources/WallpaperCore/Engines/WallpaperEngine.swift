import AppKit
import Foundation

// MARK: - WallpaperEngineDelegate

/// Delegate protocol receiving playback state transitions and runtime errors from a `WallpaperEngine`.
@MainActor
public protocol WallpaperEngineDelegate: AnyObject {
    /// Notifies the delegate that the engine encountered an error during loading or playback.
    func engineDidEncounterError(_ engine: WallpaperEngine, error: Error)

    /// Notifies the delegate that the engine transitioned playback state (playing vs paused).
    func engineDidChangePlaybackState(_ engine: WallpaperEngine, isPlaying: Bool)
}

// MARK: - WallpaperEngine Protocol

/// Core protocol governing live wallpaper rendering engines across video, web, and shader backends.
@MainActor
public protocol WallpaperEngine: AnyObject {
    /// The root AppKit view that hosts the visual content of the wallpaper.
    var view: NSView { get }

    /// The associated wallpaper model defining source path/URL and configuration.
    var item: WallpaperItem { get }

    /// Controls whether audio output is silenced.
    var isMuted: Bool { get set }

    /// Playback audio volume level clamped between 0.0 and 1.0.
    var volume: Float { get set }

    /// Controls whether user inputs (mouse and keyboard) are accepted and processed.
    var isInteractive: Bool { get set }

    /// Indicates whether the engine is actively rendering or playing media.
    var isPlaying: Bool { get }

    /// Optional delegate for playback notifications and error events.
    var delegate: WallpaperEngineDelegate? { get set }

    /// Starts or resumes wallpaper playback and rendering.
    func play()

    /// Pauses wallpaper playback, halts video decoding, and suspends web scripts.
    func pause()

    /// Permanently halts rendering, terminates background players/processes, and releases resources.
    func terminate()
}

// MARK: - WallpaperEngineError

/// Domain-specific errors thrown or reported by wallpaper rendering engines.
public enum WallpaperEngineError: LocalizedError, Equatable, Sendable {
    case assetNotFound(String)
    case emptyAsset(String)
    case corruptMedia(String)
    case unplayableFormat(String)
    case missingIndexHTML(String)
    case navigationFailed(String)
    case webProcessCrashed(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .assetNotFound(let path):
            return "Wallpaper asset not found at path: \(path)"
        case .emptyAsset(let path):
            return "Wallpaper asset at '\(path)' is 0 bytes or empty."
        case .corruptMedia(let reason):
            return "Media file is corrupt or unreadable: \(reason)"
        case .unplayableFormat(let format):
            return "Media format '\(format)' is unplayable or unsupported."
        case .missingIndexHTML(let dir):
            return "Web wallpaper folder does not contain an index.html file: \(dir)"
        case .navigationFailed(let reason):
            return "Web wallpaper navigation failed: \(reason)"
        case .webProcessCrashed(let reason):
            return "WebKit WebContent process crashed or terminated: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid engine configuration: \(reason)"
        }
    }
}

// MARK: - WallpaperEngineFactory

/// Factory responsible for instantiating concrete `WallpaperEngine` instances based on `WallpaperType`.
@MainActor
public enum WallpaperEngineFactory {

    /// Creates and returns the appropriate `WallpaperEngine` implementation for the provided `WallpaperItem`.
    ///
    /// - Parameter item: The wallpaper model to instantiate an engine for.
    /// - Returns: A `VideoWallpaperEngine` for `.video` types, or a `WebWallpaperEngine` for `.web` and `.url` types.
    public static func createEngine(for item: WallpaperItem) -> WallpaperEngine {
        switch item.type {
        case .video:
            return VideoWallpaperEngine(item: item)
        case .web, .url:
            return WebWallpaperEngine(item: item)
        }
    }
}
