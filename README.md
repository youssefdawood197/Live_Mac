# Lively Wallpaper for macOS 🌟

A pure native macOS replica of the popular Windows [Lively Wallpaper](https://github.com/rocksdanister/lively) application, built from the ground up using **Swift 6**, **SwiftUI**, and **AppKit**.

Optimized specifically for Apple Silicon and macOS 14+ (Sonoma & Sequoia) to deliver smooth live wallpapers with near-zero idle CPU footprint and battery-conscious power management.

---

## ✨ Features

* **Desktop Level Windowing (`kCGDesktopWindowLevel`)**: Renders animated wallpapers directly on the desktop layer behind Finder icons and widgets, persisting smoothly across virtual spaces and Mission Control.
* **Dual-Gate Event Passthrough**:
  * *Default Mode*: Normal mouse clicks and drag events pass directly through to your desktop files without latency.
  * *Interactive Desktop Mode*: Dynamically elevates wallpaper to capture clicks and keyboard input for interactive WebGL/HTML5 shaders.
* **Hardware-Accelerated Video Engine**:
  * Powered by `AVFoundation` (`AVQueuePlayer` & `AVPlayerLooper`) for seamless, gapless looping without black frame flickers.
  * Supports MP4, MOV, and M4V video formats with hardware H.264 / HEVC decoding.
  * Audio mute toggle and dynamic volume slider.
* **Interactive Web & Shader Engine**:
  * Powered by `WebKit` (`WKWebView`) with transparent background backing (`drawsBackground = false`).
  * Supports local HTML5/Canvas/WebGL packages (folders containing `index.html`) and live remote URLs (Shadertoy, web dashboards).
  * Auto-suspends JavaScript `requestAnimationFrame` and HTML5 media when paused to preserve battery.
* **Menu Bar Companion (`NSStatusItem`)**:
  * Accessory application living in the macOS top menu bar (`sparkles.tv` icon).
  * Quick controls: Play/Pause, Mute/Unmute, Interactive Desktop toggle, Wallpaper quick-picker submenu, and Settings.
* **SwiftUI Wallpaper Manager**:
  * Modern `NavigationSplitView` gallery interface with search and category filters (`Videos`, `HTML5 Web`, `URLs`).
  * Modal sheet to import local video files, HTML5 canvas folders, or remote web URLs with drag-and-drop support.
  * Built-in preview and wallpaper library management.
* **Smart Power & Auto-Pause Engine**:
  * **Fullscreen Occlusion Detection**: Zero-TCC permission detection via `CGWindowListCopyWindowInfo` geometry matching—automatically pauses rendering when gaming or using full-screen apps.
  * **Display Sleep & Lock**: Automatically pauses when displays go to sleep or the lock screen activates (`NSWorkspace.screensDidSleepNotification` & `com.apple.screenIsLocked`).
  * **Battery Saver**: Automatically halts video/web rendering when unplugged from AC power (optional toggle).
* **Multi-Display Support**:
  * Coordinates wallpaper windows across multiple monitors with dynamic hot-plugging support (`NSApplication.didChangeScreenParametersNotification`).

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Menu Bar & UI (SwiftUI)              │
│  - StatusItemController (NSStatusItem menu bar companion)│
│  - ManagerView (SwiftUI NavigationSplitView Gallery)   │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│         Desktop Window Controller (AppKit)             │
│  - Borderless NSWindow at CGWindowLevelForKey(.desktopWindow)
│  - PassthroughView (Dual-gate hit-testing)             │
│  - Space Persistence (.canJoinAllSpaces, .stationary)  │
└───────────────────────────┬────────────────────────────┘
                            │
       ┌────────────────────┴────────────────────┐
       ▼                                         ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│     Video Playback Engine    │  │       WebKit Web Engine      │
│  - AVQueuePlayer + Looper    │  │  - WKWebView                 │
│  - AVPlayerLayer backing     │  │  - Local HTML5 & Remote URLs │
│  - Seamless zero-gap looping │  │  - JS / Media suspension     │
└──────────────────────────────┘  └──────────────────────────────┘
                            ▲
┌───────────────────────────┴────────────────────────────┐
│              Power & Auto-Pause Manager                │
│  - Zero-TCC Fullscreen Detector (CGWindowList)         │
│  - Display Sleep & Screen Lock Observers               │
│  - IOKit Battery Power Monitor                         │
└────────────────────────────────────────────────────────┘
```

---

## 🚀 Building & Running

### Prerequisites
* macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
* Xcode 15+ / Swift 6.0+ toolchain

### Compile with Swift Package Manager
```bash
# Clone the repository
git clone https://github.com/youssefdawood197/Live_Mac.git
cd Live_Mac

# Build debug binary
swift build

# Run automated test suite (243 tests)
swift test
```

### Package Standalone Application Bundle (`.app`)
Use the included bundling script to produce an ad-hoc signed, standalone `LivelyWallpaper.app`:
```bash
./scripts/bundle_app.sh -c release
```

Launch the application:
```bash
open build/LivelyWallpaper.app
```

---

## 🧪 Testing & Verification

The project includes an extensive test suite comprising unit tests, integration tests, adversarial stress tests, and end-to-end scenario tests:

```bash
swift test
```

* **`Tier1_FeatureTests`**: 50 equivalence-class feature tests covering all 10 core subsystems.
* **`Tier2_BoundaryTests`**: 50 boundary condition and edge/error tests.
* **`Tier3_CombinationTests`**: Combinatorial state-transition and multi-display hot-plugging tests.
* **`Tier4_ScenarioTests`**: End-to-end user workflows and full app lifecycle tests.
* **`WallpaperCoreTests`**: Unit, adversarial stress, and memory stability test suites.

---

## 📄 License
Apache License 2.0.
