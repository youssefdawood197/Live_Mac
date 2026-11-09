import AppKit
import WebKit

// MARK: - WebWallpaperEngineError

public enum WebWallpaperEngineError: LocalizedError, Sendable, Equatable {
    case invalidPath(String)
    case fileNotFound(URL)
    case missingIndexHTML(URL)
    case unsupportedFileType(String)
    case invalidURLScheme(String)
    case unreachableHost(URL)
    case navigationFailed(String)
    case processCrashed
    case unsupportedWallpaperType(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid wallpaper path: \(path)"
        case .fileNotFound(let url):
            return "Wallpaper file or directory not found at: \(url.path)"
        case .missingIndexHTML(let url):
            return "Directory at \(url.path) is missing an index.html file"
        case .unsupportedFileType(let ext):
            return "Unsupported file extension for web wallpaper: .\(ext)"
        case .invalidURLScheme(let urlString):
            return "Invalid URL scheme in \"\(urlString)\"; only http:// and https:// are supported"
        case .unreachableHost(let url):
            return "Remote host unreachable for URL: \(url.absoluteString)"
        case .navigationFailed(let message):
            return "Web navigation failed: \(message)"
        case .processCrashed:
            return "WebKit WebContent process crashed unexpectedly"
        case .unsupportedWallpaperType(let type):
            return "Unsupported wallpaper type for WebWallpaperEngine: \(type)"
        }
    }

    public static func == (lhs: WebWallpaperEngineError, rhs: WebWallpaperEngineError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidPath(let a), .invalidPath(let b)):
            return a == b
        case (.fileNotFound(let a), .fileNotFound(let b)):
            return a.standardizedFileURL.path == b.standardizedFileURL.path
        case (.missingIndexHTML(let a), .missingIndexHTML(let b)):
            return a.standardizedFileURL.path == b.standardizedFileURL.path
        case (.unsupportedFileType(let a), .unsupportedFileType(let b)):
            return a == b
        case (.invalidURLScheme(let a), .invalidURLScheme(let b)):
            return a == b
        case (.unreachableHost(let a), .unreachableHost(let b)):
            return a.absoluteString == b.absoluteString
        case (.navigationFailed(let a), .navigationFailed(let b)):
            return a == b
        case (.processCrashed, .processCrashed):
            return true
        case (.unsupportedWallpaperType(let a), .unsupportedWallpaperType(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Custom WallpaperWebView

@MainActor
public final class WallpaperWebView: WKWebView {
    public var isInteractive: Bool = false

    public override func menu(for event: NSEvent) -> NSMenu? {
        // Suppress default Safari context menu
        return nil
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - WebWallpaperEngine

@MainActor
public final class WebWallpaperEngine: NSObject, WallpaperEngine {

    // MARK: - Properties

    public let item: WallpaperItem
    public private(set) var lastEncounteredError: Error?
    public private(set) var hasError: Bool = false

    public weak var delegate: WallpaperEngineDelegate? {
        didSet {
            if let error = lastEncounteredError {
                delegate?.engineDidEncounterError(self, error: error)
            }
        }
    }

    public private(set) lazy var webView: WallpaperWebView = {
        let config = makeConfiguration()
        let wv = WallpaperWebView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), configuration: config)
        wv.underPageBackgroundColor = .clear
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isInteractive = self._isInteractive
        return wv
    }()

    public var view: NSView {
        webView
    }

    private var _isMuted: Bool = true
    public var isMuted: Bool {
        get { _isMuted }
        set {
            guard _isMuted != newValue else { return }
            _isMuted = newValue
            syncAudioState()
        }
    }

    private var _volume: Float = 1.0
    public var volume: Float {
        get { _volume }
        set {
            let clamped: Float
            if newValue.isNaN || newValue.isInfinite {
                clamped = 0.0
            } else {
                clamped = max(0.0, min(1.0, newValue))
            }
            guard _volume != clamped else { return }
            _volume = clamped
            syncAudioState()
        }
    }

    private var _isInteractive: Bool = false
    public var isInteractive: Bool {
        get { _isInteractive }
        set {
            guard _isInteractive != newValue else { return }
            _isInteractive = newValue
            webView.isInteractive = newValue
            let js = "window.dispatchEvent(new CustomEvent(\"wallpaperInteractionModeChanged\", { detail: { isInteractive: \(newValue) } }));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    public private(set) var isPlaying: Bool = true
    public private(set) var isTerminated: Bool = false

    // MARK: - Initialization

    public init(item: WallpaperItem, delegate: WallpaperEngineDelegate? = nil) {
        self.item = item
        self._isMuted = item.isMuted
        if item.volume.isNaN || item.volume.isInfinite {
            self._volume = 0.0
        } else {
            self._volume = max(0.0, min(1.0, item.volume))
        }
        self._isInteractive = item.isInteractive
        self.delegate = delegate
        super.init()

        loadContent()
    }

    isolated deinit {
        terminate()
    }

    // MARK: - Configuration & Injected Scripts

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let scriptSource = """
        (function() {
            // 1. Inject styling to suppress scrollbars, elastic overscroll, and selection
            const style = document.createElement("style");
            style.id = "__wallpaper_injected_style__";
            style.textContent = `
                html, body {
                    margin: 0 !important;
                    padding: 0 !important;
                    width: 100vw !important;
                    height: 100vh !important;
                    overflow: hidden !important;
                    overscroll-behavior: none !important;
                    user-select: none !important;
                    -webkit-user-select: none !important;
                }
                ::-webkit-scrollbar {
                    display: none !important;
                    width: 0px !important;
                    height: 0px !important;
                }
            `;
            if (document.head) {
                document.head.appendChild(style);
            } else {
                document.addEventListener("DOMContentLoaded", function() {
                    if (document.head) document.head.appendChild(style);
                });
            }

            // 2. RequestAnimationFrame & Lifecycle Bridge
            window.__wallpaper_isPaused = false;
            const __orig_raf = window.requestAnimationFrame.bind(window);
            const __orig_caf = window.cancelAnimationFrame.bind(window);
            const __pendingCallbacks = new Map();
            let __nextId = 1;

            window.requestAnimationFrame = function(callback) {
                const id = __nextId++;
                if (window.__wallpaper_isPaused) {
                    __pendingCallbacks.set(id, callback);
                    return id;
                }
                __orig_raf(function(timestamp) {
                    __pendingCallbacks.delete(id);
                    if (!window.__wallpaper_isPaused) {
                        callback(timestamp);
                    } else {
                        __pendingCallbacks.set(id, callback);
                    }
                });
                return id;
            };

            window.cancelAnimationFrame = function(id) {
                __pendingCallbacks.delete(id);
                __orig_caf(id);
            };

            window.__wallpaper_pause = function() {
                window.__wallpaper_isPaused = true;
                document.querySelectorAll("video, audio").forEach(function(el) {
                    try { el.pause(); } catch(e) {}
                });
                if (typeof window.livelyPropertyListener === "function") {
                    window.livelyPropertyListener("isPaused", true);
                }
                window.dispatchEvent(new CustomEvent("wallpaperPause"));
            };

            window.__wallpaper_resume = function() {
                window.__wallpaper_isPaused = false;
                const callbacks = Array.from(__pendingCallbacks.values());
                __pendingCallbacks.clear();
                callbacks.forEach(function(cb) {
                    window.requestAnimationFrame(cb);
                });
                document.querySelectorAll("video, audio").forEach(function(el) {
                    try { el.play(); } catch(e) {}
                });
                if (typeof window.livelyPropertyListener === "function") {
                    window.livelyPropertyListener("isPaused", false);
                }
                window.dispatchEvent(new CustomEvent("wallpaperResume"));
            };
        })();
        """

        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)
        return configuration
    }

    // MARK: - Loading

    public func loadContent() {
        guard !isTerminated else { return }

        switch item.type {
        case .web:
            loadLocalContent()
        case .url:
            loadRemoteContent()
        case .video:
            reportError(WebWallpaperEngineError.unsupportedWallpaperType(item.type.rawValue))
        }
    }

    private func reportError(_ error: Error) {
        hasError = true
        lastEncounteredError = error
        delegate?.engineDidEncounterError(self, error: error)
    }

    private func loadLocalContent() {
        let rawPath = item.pathOrURL
        let fileURL: URL
        if rawPath.hasPrefix("file://") {
            guard let u = URL(string: rawPath) else {
                reportError(WebWallpaperEngineError.invalidPath(rawPath))
                return
            }
            fileURL = u
        } else {
            fileURL = URL(fileURLWithPath: rawPath)
        }

        let canonicalURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDir) else {
            reportError(WebWallpaperEngineError.fileNotFound(canonicalURL))
            return
        }

        let indexURL: URL
        let readAccessURL: URL
        if isDir.boolValue {
            indexURL = canonicalURL.appendingPathComponent("index.html")
            readAccessURL = canonicalURL
            guard FileManager.default.fileExists(atPath: indexURL.path) else {
                reportError(WebWallpaperEngineError.missingIndexHTML(canonicalURL))
                return
            }
        } else {
            let ext = canonicalURL.pathExtension.lowercased()
            guard ext == "html" || ext == "htm" else {
                reportError(WebWallpaperEngineError.unsupportedFileType(canonicalURL.pathExtension))
                return
            }
            indexURL = canonicalURL
            readAccessURL = canonicalURL.deletingLastPathComponent()
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: readAccessURL)
    }

    private func loadRemoteContent() {
        guard let url = item.resolvedURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            reportError(WebWallpaperEngineError.invalidURLScheme(item.pathOrURL))
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 30.0
        webView.load(request)
    }

    public func reload() {
        guard !isTerminated else { return }
        webView.reload()
    }

    // MARK: - Audio Sync

    private func syncAudioState() {
        guard !isTerminated else { return }
        let js = """
        (function() {
            const muted = \(_isMuted);
            const vol = \(_volume);
            document.querySelectorAll("video, audio").forEach(function(el) {
                el.muted = muted;
                el.volume = vol;
            });
            if (typeof window.livelyPropertyListener === "function") {
                window.livelyPropertyListener("isMuted", muted);
                window.livelyPropertyListener("volume", vol);
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Lifecycle: Play, Pause, Terminate

    public func play() {
        guard !isTerminated else { return }
        guard !isPlaying else { return }
        isPlaying = true

        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        let resumeSel = Selector(("resumeAllMediaPlayback:"))
        if webView.responds(to: resumeSel) {
            webView.perform(resumeSel, with: nil)
        }

        let js = "window.__wallpaper_resume && window.__wallpaper_resume();"
        webView.evaluateJavaScript(js, completionHandler: nil)

        delegate?.engineDidChangePlaybackState(self, isPlaying: true)
    }

    public func pause() {
        guard !isTerminated else { return }
        guard isPlaying else { return }
        isPlaying = false

        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)

        let js = "window.__wallpaper_pause && window.__wallpaper_pause();"
        webView.evaluateJavaScript(js, completionHandler: nil)

        delegate?.engineDidChangePlaybackState(self, isPlaying: false)
    }

    public func terminate() {
        guard !isTerminated else { return }
        isTerminated = true
        isPlaying = false

        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)

        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        webView.configuration.userContentController.removeAllUserScripts()
        webView.removeFromSuperview()

        delegate?.engineDidChangePlaybackState(self, isPlaying: false)
    }
}

// MARK: - WKNavigationDelegate & WKUIDelegate

extension WebWallpaperEngine: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncAudioState()
        if !isPlaying {
            let js = "window.__wallpaper_pause && window.__wallpaper_pause();"
            webView.evaluateJavaScript(js, completionHandler: nil)
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorCannotFindHost || nsError.code == NSURLErrorCannotConnectToHost {
                if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                    reportError(WebWallpaperEngineError.unreachableHost(failingURL))
                    return
                }
            }
        }
        reportError(WebWallpaperEngineError.navigationFailed(error.localizedDescription))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportError(WebWallpaperEngineError.navigationFailed(error.localizedDescription))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reportError(WebWallpaperEngineError.processCrashed)
        webView.reload()
    }
}

extension WebWallpaperEngine: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        completionHandler()
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        completionHandler(false)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        completionHandler(nil)
    }
}
