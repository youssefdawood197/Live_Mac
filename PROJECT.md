# Project: Lively Wallpaper for macOS

## Architecture
A native macOS live wallpaper replica built with pure Swift, SwiftUI, and AppKit. Operates as an accessory application (`LSUIElement`) managed via an `NSStatusItem` menu bar companion, rendering hardware-accelerated video and WebKit wallpapers on borderless desktop windows positioned at `CGWindowLevelForKey(.desktopWindow)` behind Finder desktop icons. Dynamic window elevation enables direct mouse/keyboard interaction for web wallpapers. An event-driven `PowerManager` coordinates zero-TCC fullscreen occlusion detection, display sleep, screen lock, and battery states to automatically pause rendering engines.

### Subsystem Boundaries
1. **Core & Data Models (`WallpaperCore/Models`)**: Wallpaper definitions, Lively schema parsers, persistent library management, and observable application state.
2. **Desktop Window Subsystem (`WallpaperCore/Desktop`)**: Multi-display window lifecycle, space persistence (`.canJoinAllSpaces`), window levels, dual-gate mouse event passthrough, and interactive mode elevation.
3. **Rendering Engines (`WallpaperCore/Engines`)**: `AVFoundation` video engine with `AVPlayerLooper` for seamless playback and WebKit engine (`WKWebView`) for local and remote HTML5/WebGL/Canvas wallpapers.
4. **Power & Lifecycle Management (`WallpaperCore/Power`)**: Multi-source pause manager observing fullscreen apps, screen sleep/lock, and battery power.
5. **User Interface (`WallpaperCore/UI` & `WallpaperApp`)**: `NSStatusItem` companion with real-time menu synchronization and SwiftUI Wallpaper Manager (`NavigationSplitView` gallery, live previews, file/URL import, settings).
6. **E2E & Verification Suite (`Tests`)**: Automated unit, integration, and opaque-box E2E test harness covering Tiers 1-4.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Swift Package Configuration | Standalone modular `Package.swift` targeting macOS 14+ | M1 | Survey / R5 |
| 2 | Wallpaper Data Models | `WallpaperItem`, `WallpaperType`, `LivelyInfo` parser, library persistence | M1 | Survey / R4 |
| 3 | Sample Test Asset Generator | Native `AVAssetWriter` MP4 loop generator and HTML5/Canvas assets | M1 | Survey / R5 |
| 4 | Desktop Window Leveling | Borderless windows pinned at `CGWindowLevelForKey(.desktopWindow)` (-2147483623) | M2 | Survey / R1 |
| 5 | Space & Mission Control Persistence | Window collection behavior (`.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenAuxiliary`) | M2 | Survey / R1 |
| 6 | Multi-Display NSScreen Management | Dynamic creation, resizing, and teardown of desktop windows per display | M2 | Survey / R1 |
| 7 | Default Mouse Passthrough | `ignoresMouseEvents = true` and `hitTest(_:) -> nil` allowing clicks to pass to Finder | M2 | Survey / R1 |
| 8 | Interactive Mode Toggle | Elevates window to `.desktopIconWindow + 1` (-2147483602), enables `canBecomeKey` and mouse inputs | M2 | Survey / R1 |
| 9 | Hardware-Accelerated Video Playback | `AVQueuePlayer` and `AVPlayerLayer` backing in `NSView.makeBackingLayer()` | M3 | Survey / R2 |
| 10 | Seamless Gapless Video Looping | `AVPlayerLooper` pre-buffering 3 items with zero-tolerance seek fallback | M3 | Survey / R2 |
| 11 | Video Audio & Volume Controls | Dynamic volume slider, mute/unmute toggle | M3 | Survey / R2 |
| 12 | Video Format Compatibility | MP4 and MOV playback with duration validation | M3 | Survey / R2 |
| 13 | Local Web Wallpaper Engine | `WKWebView` rendering local HTML5/WebGL/Canvas folders via `loadFileURL(_:allowingReadAccessTo:)` | M3 | Survey / R3 |
| 14 | Remote Web Wallpaper Engine | `WKWebView` live URL loading via `load(URLRequest)` | M3 | Survey / R3 |
| 15 | Web Transparency & UI Cleanup | Transparent WebKit background (`drawsBackground = false`), AppKit context menu suppression | M3 | Survey / R3 |
| 16 | Web Resource & Audio Suspension | Suspending JS RAF and WebKit media playback on pause | M3 | Survey / R3 |
| 17 | Zero-TCC Fullscreen Occlusion Detection | Polling on-screen layer 0 windows via `CGWindowListCopyWindowInfo` to detect full-screen apps/games | M4 | Survey / R5 |
| 18 | Display Sleep & Wake Handling | Observing `NSWorkspace.screensDidSleepNotification` & `screensDidWakeNotification` | M4 | Survey / R5 |
| 19 | Screen Lock & Screensaver Handling | Observing `DistributedNotificationCenter` for `com.apple.screenIsLocked` & `com.apple.screenIsUnlocked` | M4 | Survey / R5 |
| 20 | Battery Power State Monitoring | IOKit power source observer (`IOPSNotificationCreateRunLoopSource`) for battery auto-pause | M4 | Survey / R5 |
| 21 | Additive Pause State Machine | Race-condition-free `OptionSet` managing multi-source pause reasons | M4 | Survey / R5 |
| 22 | Menu Bar Companion (`NSStatusItem`) | Status item with `sparkles.tv` icon and `NSMenuDelegate` dynamic synchronization | M5 | Survey / R4 |
| 23 | Menu Bar Quick Controls | Play/Pause, Mute/Unmute, Interaction Mode, Active Wallpaper Switching, Quit | M5 | Survey / R4 |
| 24 | SwiftUI Wallpaper Manager Gallery | Modern `NavigationSplitView` with adaptive `LazyVGrid` and hover-sensitive cards | M5 | Survey / R4 |
| 25 | Live / Static Wallpaper Previews | Thumbnail generation and mini-preview player for selected wallpapers | M5 | Survey / R4 |
| 26 | File Ingestion (Browser & Drag-and-Drop) | `NSOpenPanel` and `.onDrop` support for videos, HTML5 folders, and lively zip packages | M5 | Survey / R4 |
| 27 | Remote URL Ingestion Sheet | Modal sheet to input and validate live web wallpaper URLs | M5 | Survey / R4 |
| 28 | Settings & Preferences Panel | Configurable auto-pause triggers, audio defaults, and launch behavior | M5 | Survey / R4 |
| 29 | Application Activation Policy | `LSUIElement = true` accessory policy with auxiliary Edit menu for clipboard support | M5 | Survey / R4 |
| 30 | Opaque-Box E2E Test Suite | Automated test harness executing Tiers 1-4 via `swift test` | M6 / E2E Track | Survey / R5 |
| 31 | Adversarial Coverage Hardening | White-box stress tests, edge cases, and crash resilience verification (Tier 5) | M6 / E2E Track | Survey / R5 |
| 32 | Production App Bundling & Docs | Standalone `LivelyWallpaper.app` bundle script and comprehensive documentation | M6 | Survey / R5 |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Foundation & Test Assets | Package structure, models, Lively parser, sample asset generation | none | DONE |
| M2 | Desktop Window & Passthrough Engine | Desktop window, window levels, space persistence, multi-display, hit testing | M1 | DONE |
| M3 | Media & Web Rendering Engines | Video wallpaper engine (AVPlayerLooper), Web wallpaper engine (WKWebView), protocol | M1, M2 | DONE |
| M4 | Energy Saver & Auto-Pause Engine | Fullscreen app detection, display sleep/wake, lock/unlock, battery monitoring | M1, M3 | IN_PROGRESS |
| M5 | Menu Bar Companion & SwiftUI Manager | NSStatusItem companion, SwiftUI Manager gallery, preview, file/URL intake, settings | M1, M2, M3, M4 | PLANNED |
| M6 | Final Verification & Hardening | 100% E2E test pass (Tiers 1-4), Tier 5 adversarial hardening, app bundle & docs | M1-M5, TEST_READY | PLANNED |

---

## Interface Contracts

### 1. `WallpaperEngine` Protocol
```swift
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
```

### 2. `DesktopWindowManagerProtocol`
```swift
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
```

### 3. `PowerManagerProtocol`
```swift
public struct PauseReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let userPaused        = PauseReasons(rawValue: 1 << 0)
    public static let fullscreenApp     = PauseReasons(rawValue: 1 << 1)
    public static let displaySleeping   = PauseReasons(rawValue: 1 << 2)
    public static let screenLocked      = PauseReasons(rawValue: 1 << 3)
    public static let batterySaver      = PauseReasons(rawValue: 1 << 4)
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
```

---

## Code Layout
```
wallpaper/
├── Package.swift
├── Sources/
│   ├── WallpaperCore/
│   │   ├── Models/
│   │   │   ├── WallpaperItem.swift
│   │   │   ├── WallpaperType.swift
│   │   │   ├── LivelyInfo.swift
│   │   │   └── AppState.swift
│   │   ├── Desktop/
│   │   │   ├── DesktopWindow.swift
│   │   │   ├── DesktopWindowManager.swift
│   │   │   └── PassthroughView.swift
│   │   ├── Engines/
│   │   │   ├── WallpaperEngine.swift
│   │   │   ├── VideoWallpaperEngine.swift
│   │   │   └── WebWallpaperEngine.swift
│   │   ├── Power/
│   │   │   ├── PowerManager.swift
│   │   │   ├── FullscreenDetector.swift
│   │   │   └── BatteryMonitor.swift
│   │   ├── UI/
│   │   │   ├── StatusItemController.swift
│   │   │   ├── ManagerView.swift
│   │   │   ├── WallpaperGalleryView.swift
│   │   │   ├── WallpaperCardView.swift
│   │   │   ├── AddWallpaperSheet.swift
│   │   │   └── SettingsView.swift
│   │   └── Assets/
│   │       ├── AssetManager.swift
│   │       └── SampleAssetGenerator.swift
│   └── WallpaperApp/
│       ├── main.swift
│       └── AppDelegate.swift
├── Tests/
│   ├── WallpaperCoreTests/
│   │   ├── ModelTests.swift
│   │   ├── DesktopWindowTests.swift
│   │   ├── EngineTests.swift
│   │   ├── PowerManagerTests.swift
│   │   └── AssetTests.swift
│   └── WallpaperE2ETests/
│       ├── E2ETestHarness.swift
│       ├── Tier1_FeatureTests.swift
│       ├── Tier2_BoundaryTests.swift
│       ├── Tier3_CombinationTests.swift
│       └── Tier4_ScenarioTests.swift
├── Resources/
│   ├── Samples/
│   │   ├── sample_loop.mp4
│   │   └── sample_canvas/
│   │       └── index.html
│   └── Info.plist
└── scripts/
    └── bundle_app.sh
```
