import Foundation

/// Defines the underlying rendering engine and media classification for a wallpaper.
public enum WallpaperType: String, Codable, CaseIterable, Sendable, Hashable {
    /// Local video file played via AVFoundation (AVPlayer / AVPlayerLooper).
    case video = "video"
    
    /// Local HTML5, WebGL, or Canvas folder containing an index.html file rendered in WKWebView.
    case web = "web"
    
    /// Remote live web URL loaded over HTTP/HTTPS in WKWebView.
    case url = "url"

    /// User-facing display title for UI representation.
    public var displayName: String {
        switch self {
        case .video:
            return "Video"
        case .web:
            return "Web Page"
        case .url:
            return "Web URL"
        }
    }

    /// System SF Symbol icon name representing the wallpaper type.
    public var systemIconName: String {
        switch self {
        case .video:
            return "video.fill"
        case .web:
            return "safari.fill"
        case .url:
            return "link"
        }
    }

    /// Alias for systemIconName for SF symbol rendering.
    public var sfSymbolName: String {
        systemIconName
    }

    /// Indicates whether this type is rendered via the WebKit web engine.
    public var isWebBased: Bool {
        self == .web || self == .url
    }

    /// Indicates whether this wallpaper type can contain or produce audio output.
    public var supportsAudio: Bool {
        self == .video || self == .web
    }

    /// Indicates whether desktop user interaction (mouse clicks, keyboard) can be enabled.
    public var supportsInteraction: Bool {
        self == .web || self == .url
    }

    /// Attempts to infer the wallpaper type from a file extension.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm", "avi", "mkv":
            self = .video
        case "html", "htm", "zip", "lively":
            self = .web
        default:
            return nil
        }
    }

    /// Attempts to infer the wallpaper type from a local or remote URL.
    public init?(url: URL) {
        if url.isFileURL {
            self.init(fileExtension: url.pathExtension)
        } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            self = .url
        } else {
            return nil
        }
    }
}
