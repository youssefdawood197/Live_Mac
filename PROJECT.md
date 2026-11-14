# Project: Lively Wallpaper with Native Flake Mode & Windows Scaffolding

## Architecture
A native desktop live wallpaper and ambient snowfall application supporting both macOS (Swift 6 / AppKit / SwiftUI / SpriteKit) and Windows (.NET 8 / C# 12 / WinUI 3 / Win2D / CsWin32).
Operates as an accessory desktop application that renders hardware-accelerated video/web live wallpapers and realistic physical snowfall simulations on application window borders, system Dock/Taskbar, and display bottoms.

### Subsystem Boundaries
1. **Core & Data Models (`WallpaperCore/Models`, `Live.Core`)**: Wallpaper definitions, Lively schema parsers, persistent library management, and observable application state.
2. **Desktop Window Subsystem (`WallpaperCore/Desktop`, `Live.Interop.Win32`)**: Multi-display window lifecycle, space persistence (`.canJoinAllSpaces`), window levels, dual-gate mouse event passthrough, WorkerW injection (`0x052C`), and interactive mode elevation.
3. **Flake Engine & Window Tracking (`WallpaperCore/Flake`, `Live.Engine.Flake`)**:
   - `WindowSurfaceDetector` / `Win32WindowSurfaceDetector`: Zero-TCC window querying via Quartz Window Services (`CGWindowListCopyWindowInfo`) on macOS and Win32 `EnumWindows` + `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` on Windows.
   - `FlakeScene`: GPU-accelerated particle snowfall, 360° trigonometric wind acceleration math, 10px-bin column heightmaps, 3-point angle of repose smoothing, window movement re-anchoring, snowplow sweeps (`avgDepth > 32px`), festive fairy lights, and tool clearing.
   - `FlakeOverlayWindow`: Borderless transparent floating window (`.floating` / `WS_EX_TOPMOST | WS_EX_LAYERED`) with dynamic mouse event passthrough toggling (`ignoresMouseEvents` / `WS_EX_TRANSPARENT`).
   - `FlakeController`: Multi-monitor lifecycle, screen parameter change handling, and power coordination.
4. **Interactive Tools & Sweepers**: Mitten tool (circular radius brush), shovel tool (rectangular scoop), automated snowplow sweeps (threshold trigger, traversal animation, multiple vehicle models), and decorative fairy lights.
5. **Power & Lifecycle Management (`WallpaperCore/Power`, `Live.Core/Power`)**: Multi-source pause manager observing fullscreen apps, screen sleep, screen lock, and battery states to automatically pause rendering engines (< 1.5% idle CPU).
6. **User Interface (`WallpaperCore/UI`, `Live.App`)**: Menu bar companion (`StatusItemController` / system tray) with quick toggles, SwiftUI / WinUI 3 Manager view (`FlakeSettingsView`), and 360° interactive `WindCompassView`.
7. **E2E & Verification Suite (`Tests`, `Live.Core.Tests`)**: Automated unit, integration, and opaque-box E2E test harness covering Tiers 1-4 (392/392 tests pass).

---

## Feature Inventory
| # | Feature | Description | Milestone | Source | Status |
|---|---------|-------------|-----------|--------|--------|
| 1 | Zero-TCC Window Querying | Query on-screen windows via Quartz Window Services without Accessibility/Screen Recording | M1 | Survey / R1, R2 | DONE |
| 2 | Window Surface Filtering | Filter normal layer windows, on-screen only, alpha > 0.05, min dimensions | M1 | Survey / R1 | DONE |
| 3 | Coordinate System Inversion | Transform Quartz top-left coordinates to Cocoa bottom-left coordinates | M1 | Survey / R1 | DONE |
| 4 | Dock Surface Extraction | Extract Dock top ledge from screen and visible frame geometry | M1 | Survey / R1 | DONE |
| 5 | Bottom Display Shelf | Baseline snowbank along bottom of display (id: 0) | M1 | Survey / R1 | DONE |
| 6 | Window Occlusion Culling | Cull hidden window surfaces obscured by higher-z windows | M1 | Survey / R1 | DONE |
| 7 | 10 Hz Polling Throttle | Throttle Quartz polling to 10 Hz while rendering particles at 60 Hz | M1 | Survey / R2 | DONE |
| 8 | SpriteKit Particle Dynamics | GPU-accelerated snowfall simulation with SKEmitterNode (< 1.5% CPU) | M1 | Survey / R1, R2 | DONE |
| 9 | Snowfall Intensity Tiers | Light (150 flakes/20bps), Steady (400 flakes/50bps), Blizzard (900 flakes/120bps) | M1 | Survey / R1 | DONE |
| 10 | 360° Directional Wind Acceleration | Dynamic trigonometric vector acceleration on falling particles | M1 | Survey / R1 | DONE |
| 11 | Wind Speed Variation | Dynamic wind velocity adjustment from 0 to 600 px/s² | M1 | Survey / R1 | DONE |
| 12 | Column-Based Heightmap Accumulation | 10px binning per surface id tracking snow depth across ledges | M1 | Survey / R1 | DONE |
| 13 | Angle of Repose Smoothing | 3-point smoothing convolution `(bins[i-1] + 2*bins[i] + bins[i+1])/4` | M1 | Survey / R1 | DONE |
| 14 | Window Movement Re-anchoring | Re-anchor snowdrifts tracking moving windows via delta (dx, dy) | M1 | Survey / R1 | DONE |
| 15 | Surface Accumulation Cap | Cap snow height to prevent overflow above window boundaries | M1 | Survey / R1 | DONE |
| 16 | Interactive Mitten Tool | Cursor tool clearing snow within circular radius on drag | M2 | Survey / R1 | DONE |
| 17 | Interactive Shovel Tool | Cursor tool clearing wide scoop rectangular area on drag | M2 | Survey / R1 | DONE |
| 18 | Dynamic Mouse Event Passthrough | `ignoresMouseEvents = true` when idle, toggles to false when tool active | M2 | Survey / R1 | DONE |
| 19 | Automated Snowplow Trigger | Trigger snowplow sweep when bottom snowbank exceeds height threshold (>32px) | M2 | Survey / R1 | DONE |
| 20 | Snowplow Vehicle Models | Support classic tractor, vintage tractor, snowmobile, penguin, custom | M2 | Survey / R1 | DONE |
| 21 | Snowplow Traversal Animation | Traverse across bottom ledge and clear accumulation | M2 | Survey / R1 | DONE |
| 22 | Window Fairy Lights | Toggleable multi-colored festive lights string along top window borders | M2 | Survey / R1 | DONE |
| 23 | Fairy Lights Twinkling Animation | Phased pulsating glow animation for festive bulbs | M2 | Survey / R1 | DONE |
| 24 | 360° Wind Compass Control UI | Circular interactive compass with draggable needle & direction readouts | M3 | Survey / R1 | DONE |
| 25 | Dual Layer Modes | Support .overlay (floating above windows) and .desktop (pinned behind icons) | M3 | Survey / R1 | DONE |
| 26 | Multi-Display Management | Per-screen FlakeOverlayWindow lifecycle across connected displays | M3 | Survey / R1 | DONE |
| 27 | Display Parameter Change Handling | Dynamic resize & rebuild on screen connection/resolution change | M3 | Survey / R1 | DONE |
| 28 | PowerManager Integration | Automatic pause state coordination via PowerManagerProtocol | M3 | Survey / R2 | DONE |
| 29 | Display Sleep Auto-Pause | Pause simulation immediately on display sleep notification | M3 | Survey / R2 | DONE |
| 30 | Screen Lock Auto-Pause | Pause simulation immediately on screen lock notification | M3 | Survey / R2 | DONE |
| 31 | Fullscreen Occlusion Auto-Pause | Pause simulation when frontmost application is fullscreen | M3 | Survey / R2 | DONE |
| 32 | Menu Bar Companion Controls | StatusItemController submenu for Flake mode toggles, presets, and clearing | M3 | Survey / R1 | DONE |
| 33 | Wallpaper Manager Settings UI | FlakeSettingsView integrated into ManagerView navigation | M3 | Survey / R1 | DONE |
| 34 | Windows Architecture Blueprint | Architecture specification for .NET 8 / WinUI 3 / Win2D Windows edition | M4 | Survey / R3 | DONE |
| 35 | Windows Solution & Project Scaffolding | Establish `Live_Windows/` directory with buildable `.sln` and `.csproj` projects | M4 | Survey / R3 | DONE |
| 36 | Windows WorkerW Injection & Transparency | Scaffolding for WorkerW Progman injection and WS_EX_TRANSPARENT overlay | M4 | Survey / R3 | DONE |
| 37 | Windows Surface & Ledge Detection | Scaffolding for `DwmGetWindowAttribute` ledge extraction and DWMWA_CLOAKED | M4 | Survey / R3 | DONE |
| 38 | Windows Parity Models & Engine | Scaffolding for `Live.Core` parity models and `Live.Engine.Flake` Win2D canvas | M4 | Survey / R3 | DONE |
| 39 | E2E Test Suite Pass (Tiers 1-4) | 100% pass on requirement-driven opaque-box E2E test suite (392/392 pass) | M5 | Survey / Acceptance | DONE |
| 40 | Adversarial Coverage Hardening (Tier 5) | Challenger-driven white-box adversarial stress testing & coverage audit (50/50 pass) | M5 | Survey / Acceptance | DONE |

---

## Milestones
| # | Name | Scope | Dependencies | Status | Outputs |
|---|------|-------|-------------|--------|---------|
| M1 | macOS Flake Core Simulation & Window Tracking | Features 1-15: WindowSurfaceDetector, coordinate inversion, zero-TCC window querying, Dock & bottom ledges, occlusion, SKEmitterNode particle physics, 3-tier intensity, 360° wind acceleration, heightmap accumulation, angle of repose smoothing, window movement re-anchoring, Swift 6 concurrency cleanup | none | DONE | 25/25 FlakeTests pass, 165/165 Tier 1 tests pass, 50/50 Challenger tests pass, clean forensic audit |
| M2 | Interactive Tools, Automated Snowplow & Fairy Lights | Features 16-23: Mitten & shovel interactive tools, hit testing, dynamic `ignoresMouseEvents` passthrough switching, snowplow height threshold triggering, traversal animation, plow models, fairy lights ledges and twinkling | M1 | DONE | Mitten & shovel tools verified, snowplow triggers & sweeps verified, fairy lights twinkling verified |
| M3 | UI Integration, Wind Compass, Companion & Power Lifecycle | Features 24-33: 360° WindCompassView, FlakeSettingsView in ManagerView, StatusItemController companion menu, dual layer modes, multi-screen FlakeController, PowerManager pause on display sleep / screen lock / fullscreen occlusion | M1, M2 | DONE | WindCompassView 360° dial verified, StatusItemController menu verified, FlakeSettingsView verified, PowerManager auto-pause verified |
| M4 | Windows Version Architecture & Scaffolding | Features 34-38: Establish `Live_Windows/` structure, `Live_Windows.sln`, `Live.Core`, `Live.Interop.Win32`, `Live.Engine.Flake`, `Live.App`, `Live.Core.Tests`, buildable initial project files, documentation | none | DONE | 64 files scaffolded across 8 projects, Live_Windows.sln, Directory.Build.props, 34 challenge tests pass |
| M5 | Final Milestone: E2E Test Pass (Tiers 1-4) & Adversarial Hardening (Tier 5) | Features 39-40: Pass 100% E2E test suite from E2E Testing Track, followed by Tier 5 Challenger-driven adversarial coverage hardening | M1-M4 | DONE | 392/392 automated Flake tests pass (100% success rate); swift build exit code 0 under Swift 6 |

---

## Code Layout
```
Live_Mac/
├── Package.swift
├── Sources/
│   ├── WallpaperCore/
│   │   ├── Models/
│   │   ├── Desktop/
│   │   ├── Engines/
│   │   ├── Power/
│   │   ├── UI/
│   │   │   ├── StatusItemController.swift
│   │   │   ├── ManagerView.swift
│   │   │   ├── FlakeSettingsView.swift
│   │   │   └── WindCompassView.swift
│   │   └── Flake/
│   │       ├── CollisionSurface.swift
│   │       ├── FlakeConfiguration.swift
│   │       ├── WindowSurfaceDetector.swift
│   │       ├── FlakeScene.swift
│   │       ├── FlakeOverlayWindow.swift
│   │       └── FlakeController.swift
│   └── WallpaperApp/
├── Tests/
│   ├── WallpaperCoreTests/
│   │   └── FlakeTests.swift
│   └── WallpaperE2ETests/
│       ├── FlakeTestHarness.swift
│       ├── Tier1_FlakeFeatureTests.swift
│       ├── Tier2_FlakeBoundaryTests.swift
│       └── Tier3_FlakeCombinationTests.swift
└── Live_Windows/
    ├── Live_Windows.sln
    ├── Directory.Build.props
    ├── README.md
    ├── src/
    │   ├── Live.Core/
    │   ├── Live.Interop.Win32/
    │   ├── Live.Engine.Flake/
    │   ├── Live.Engine.Video/
    │   ├── Live.Engine.Web/
    │   └── Live.App/
    └── tests/
        ├── Live.Core.Tests/
        ├── Live.Interop.Tests/
        └── verification/
```
