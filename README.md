# Lively Wallpaper with Flake Ambient Snow Mode ❄️🌟

A pure native macOS live wallpaper and ambient winter snowfall application, built from the ground up using **Swift 6**, **SwiftUI**, **SpriteKit**, and **AppKit**, accompanied by a modern **Windows version** (.NET 8 / WinUI 3 / Win2D / CsWin32).

Optimized specifically for Apple Silicon and macOS 14+ (Sonoma & Sequoia) to deliver ultra-smooth 60 FPS live wallpapers and realistic physical snowdrifts with near-zero idle CPU footprint (< 1.5%) and battery-conscious power management.

---

## ✨ Features

### ❄️ Native Flake Ambient Winter Snowfall Mode (Inspired by [Flake](https://tryflake.ru))
* **Zero-TCC Window Ledge Querying**: Uses Quartz Window Services (`CGWindowListCopyWindowInfo`) to inspect on-screen windows and the macOS Dock border in real time without requesting Accessibility or Screen Recording permissions.
* **GPU-Accelerated SpriteKit Physics**: Particle simulation powered by `SKEmitterNode` with 3 intensity tiers:
  * *Light* (150 flakes, 20 bps)
  * *Steady* (400 flakes, 50 bps)
  * *Blizzard* (900 flakes, 120 bps)
* **360° Directional Wind Acceleration**: Dynamic trigonometric vector physics (`ax = S · cos(θ)`, `ay = -G + S · sin(θ)`) controlled via a custom draggable 360° `WindCompassView` dial.
* **Physical Snowbank Accumulation**:
  * 10px-bin column heightmaps accumulating snow on active application window headers, Dock borders, and display bottom shelves.
  * 3-point angle of repose convolution smoothing (`(bins[i-1] + 2*bins[i] + bins[i+1])/4`).
  * Dynamic window movement re-anchoring preserving drifts when windows are dragged across the desktop.
* **Interactive Clearing Tools**:
  * *Mitten Tool*: Circular radius brush clearing snowdrifts on cursor drag.
  * *Shovel Tool*: Wide rectangular scoop clearing large swaths of snow.
  * *Dynamic Mouse Event Passthrough*: Overlay window maintains `ignoresMouseEvents = true` for complete click-through when idle, instantly capturing cursor inputs when tools are active.
* **Automated Snowplow Sweepers**: Automatically triggers a vehicle sweep when bottom drifts exceed 32px depth, featuring 5 selectable vehicle models (Classic Tractor, Vintage Tractor, Snowmobile, Penguin with Shovel, and Custom User Image).
* **Festive Window Fairy Lights**: Multi-colored Christmas bulbs strung along top window borders with phased pulsing glow animations.
* **Winter Ambient Soundscapes**: Looping cozy winter wind audio with smooth volume control.

### 🌟 Desktop Live Wallpaper System
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
  * Quick controls: Play/Pause, Mute/Unmute, Interactive Desktop toggle, Flake Snow Mode submenu (intensity presets, clear drifts), Wallpaper quick-picker submenu, and Settings.
* **SwiftUI Wallpaper Manager**:
  * Modern `NavigationSplitView` gallery interface with search, category filters, and dedicated Flake Snow Mode configuration tab.
  * Modal sheet to import local video files, HTML5 canvas folders, or remote web URLs with drag-and-drop support.
  * Built-in preview and wallpaper library management with dynamic thumbnail generation.
* **Smart Power & Auto-Pause Engine**:
  * **Fullscreen Occlusion Detection**: Zero-TCC permission detection via `CGWindowListCopyWindowInfo` geometry matching—automatically pauses rendering when gaming or using full-screen apps.
  * **Display Sleep & Lock**: Automatically pauses when displays go to sleep or the lock screen activates (`NSWorkspace.screensDidSleepNotification` & `com.apple.screenIsLocked`).
  * **Battery Saver**: Automatically halts video/web rendering when unplugged from AC power (optional toggle).
* **Multi-Display Support**:
  * Coordinates wallpaper windows and Flake overlay windows across multiple monitors with dynamic hot-plugging support (`NSApplication.didChangeScreenParametersNotification`).

---

## 🪟 Windows Version (`Live_Windows/`)

The repository includes a modern Windows desktop version in [Live_Windows/](Live_Windows/):
* **Target Framework**: .NET 8, C# 12, WinUI 3 / WPF, Win2D, and CsWin32.
* **Architecture**:
  * `Live.App`: Main desktop application host and system tray companion icon.
  * `Live.Core`: Cross-platform models, Lively JSON schema parsers, and AppState.
  * `Live.Engine.Flake`: Ambient snowfall physics, heightmap snowbank accumulation, and snowplow sweeps.
  * `Live.Engine.Video`: Windows Media Foundation video loop engine.
  * `Live.Engine.Web`: Microsoft Edge WebView2 web/shader engine.
  * `Live.Interop.Win32`: Native P/Invoke layer (`WorkerW` message `0x052C` desktop parenting, DWM `DwmGetWindowAttribute` ledge queries, and `WS_EX_TRANSPARENT` styles).

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Menu Bar & UI (SwiftUI)              │
│  - StatusItemController (NSStatusItem menu bar companion)│
│  - ManagerView (SwiftUI NavigationSplitView Gallery)   │
│  - FlakeSettingsView & 360° WindCompassView            │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│         Desktop Window Controller (AppKit)             │
│  - Borderless NSWindow at CGWindowLevelForKey(.desktopWindow)
│  - PassthroughView (Dual-gate hit-testing)             │
│  - Space Persistence (.canJoinAllSpaces, .stationary)  │
└───────────────────────────┬────────────────────────────┘
                            │
       ┌────────────────────┼────────────────────┐
       ▼                    ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌────────────────────────┐
│ Video Engine │    │  Web Engine  │    │ Flake Ambient Engine   │
│ - AVLooper   │    │ - WKWebView  │    │ - SpriteKit SKEmitter  │
│ - Hardware   │    │ - WebGL/HTML5│    │ - Quartz Window Ledges │
│   Decoders   │    │ - JS Suspend │    │ - Heightmaps & Plows   │
└──────────────┘    └──────────────┘    └────────────────────────┘
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

# Run automated test suite (805 tests)
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
# Run all macOS tests (805 tests, 0 failures)
swift test

# Run Windows architecture verification suite (34 tests, 0 failures)
python3 Live_Windows/tests/verification/run_all_challenges.py
```

* **`WallpaperCoreTests`**: Unit, adversarial stress, Flake physics, and memory stability test suites (322 tests).
* **`WallpaperE2ETests`**: 4-tier requirement and scenario-driven E2E test harness (483 tests).
* **`Live_Windows/tests`**: Challenger tests verifying WorkerW injection, DWM window detection, and bitmask pause states (34 tests).

---

## 📄 License
Apache License 2.0.
