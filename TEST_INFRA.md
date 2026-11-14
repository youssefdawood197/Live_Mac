# E2E Test Infrastructure: Lively Wallpaper & Native Flake Mode

## 1. Test Philosophy

The testing architecture for Lively Wallpaper macOS and its native Flake ambient snowfall simulation is designed around four foundational tenets:

1. **Opaque-Box Verification**: Tests interact strictly with public contracts, protocol boundaries, and observable system state. Test suites treat engines, surface detectors, windows, and controllers as black boxes, asserting external behavior, geometrical accuracy, particle trajectories, heightmap states, and lifecycle responses without relying on private implementation details.
2. **Requirement-Driven Traceability**: Every test case traces directly to specific numbered functional requirements in `PROJECT.md § Feature Inventory` and `spec.md`. No test exists in isolation or merely tests synthetic code paths; each verifies a verifiable product invariant.
3. **Progressive Testability (Tiered Hierarchy)**: Verification progresses through four distinct tiers:
   - **Tier 1 (Feature / Equivalence Classes)**: Tests standard valid operational equivalence classes for every feature (≥5 tests per feature).
   - **Tier 2 (Boundary & Extreme Stress)**: Tests numerical boundaries, zero/extreme inputs, display edges, offscreen geometry, and rapid state transitions (≥5 tests per feature).
   - **Tier 3 (Combinatorial / Pairwise Interactions)**: Tests multi-feature permutations, concurrent triggers, and intersecting subsystem states (≥33 tests).
   - **Tier 4 (Real-World Application Scenarios)**: Tests multi-step end-to-end workflows, simulating actual macOS user sessions, display hotplug events, power transitions, and long-running ambient sessions (≥17 scenarios).
4. **Strict Concurrency & Zero-Regression Mandate**: All test executions run under Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`). The test suites enforce zero compiler warnings, zero deadlocks, zero actor-isolation breaches, and 100% pass rates across existing Live Wallpaper features (Features 1–10) and all Flake features (Features 1–33).

---

## 2. Feature Inventory: Flake Ambient Snowfall Mode

All 33 Flake Mode features defined in `PROJECT.md` are mapped across Tiers 1–3:

| # | Feature | Source (Requirement) | Tier 1 (Equiv.) | Tier 2 (Boundary) | Tier 3 (Comb.) |
|---|---------|----------------------|:---------------:|:-----------------:|:--------------:|
| 1 | Zero-TCC Window Querying | PROJECT.md F1, spec §4.1.1 | ≥5 | ≥5 | ✓ |
| 2 | Window Surface Filtering | PROJECT.md F2, spec §4.1.2 | ≥5 | ≥5 | ✓ |
| 3 | Coordinate System Inversion | PROJECT.md F3, spec §4.1.3 | ≥5 | ≥5 | ✓ |
| 4 | Dock Surface Extraction | PROJECT.md F4, spec §4.1.2 | ≥5 | ≥5 | ✓ |
| 5 | Bottom Display Shelf | PROJECT.md F5, spec §4.1.1 | ≥5 | ≥5 | ✓ |
| 6 | Window Occlusion Culling | PROJECT.md F6, spec §4.1.2 | ≥5 | ≥5 | ✓ |
| 7 | 10 Hz Polling Throttle | PROJECT.md F7, spec §4.2.5 | ≥5 | ≥5 | ✓ |
| 8 | SpriteKit Particle Dynamics | PROJECT.md F8, spec §4.2.1 | ≥5 | ≥5 | ✓ |
| 9 | Snowfall Intensity Tiers | PROJECT.md F9, spec §4.2.3 | ≥5 | ≥5 | ✓ |
| 10 | 360° Directional Wind Acceleration | PROJECT.md F10, spec §4.2.4 | ≥5 | ≥5 | ✓ |
| 11 | Wind Speed Variation | PROJECT.md F11, spec §4.2.4 | ≥5 | ≥5 | ✓ |
| 12 | Column-Based Heightmap Accumulation | PROJECT.md F12, spec §4.3.1 | ≥5 | ≥5 | ✓ |
| 13 | Angle of Repose Smoothing | PROJECT.md F13, spec §4.3.3 | ≥5 | ≥5 | ✓ |
| 14 | Window Movement Re-anchoring | PROJECT.md F14, spec §4.3.5 | ≥5 | ≥5 | ✓ |
| 15 | Surface Accumulation Cap | PROJECT.md F15, spec §4.3.2 | ≥5 | ≥5 | ✓ |
| 16 | Interactive Mitten Tool | PROJECT.md F16, spec §4.4.1 | ≥5 | ≥5 | ✓ |
| 17 | Interactive Shovel Tool | PROJECT.md F17, spec §4.4.1 | ≥5 | ≥5 | ✓ |
| 18 | Dynamic Mouse Event Passthrough | PROJECT.md F18, spec §4.4.1 | ≥5 | ≥5 | ✓ |
| 19 | Automated Snowplow Trigger | PROJECT.md F19, spec §4.5.1 | ≥5 | ≥5 | ✓ |
| 20 | Snowplow Vehicle Models | PROJECT.md F20, spec §4.5.3 | ≥5 | ≥5 | ✓ |
| 21 | Snowplow Traversal Animation | PROJECT.md F21, spec §4.5.2 | ≥5 | ≥5 | ✓ |
| 22 | Window Fairy Lights | PROJECT.md F22, spec §4.6.1 | ≥5 | ≥5 | ✓ |
| 23 | Fairy Lights Twinkling Animation | PROJECT.md F23, spec §4.6.1 | ≥5 | ≥5 | ✓ |
| 24 | 360° Wind Compass Control UI | PROJECT.md F24, spec §4.6.2 | ≥5 | ≥5 | ✓ |
| 25 | Dual Layer Modes | PROJECT.md F25, spec §4.7.1 | ≥5 | ≥5 | ✓ |
| 26 | Multi-Display Management | PROJECT.md F26, spec §4.7.2 | ≥5 | ≥5 | ✓ |
| 27 | Display Parameter Change Handling | PROJECT.md F27, spec §4.7.2 | ≥5 | ≥5 | ✓ |
| 28 | PowerManager Integration | PROJECT.md F28, spec §4.8.1 | ≥5 | ≥5 | ✓ |
| 29 | Display Sleep Auto-Pause | PROJECT.md F29, spec §4.8.1 | ≥5 | ≥5 | ✓ |
| 30 | Screen Lock Auto-Pause | PROJECT.md F30, spec §4.8.1 | ≥5 | ≥5 | ✓ |
| 31 | Fullscreen Occlusion Auto-Pause | PROJECT.md F31, spec §4.8.1 | ≥5 | ≥5 | ✓ |
| 32 | Menu Bar Companion Controls | PROJECT.md F32, spec §4.9.1 | ≥5 | ≥5 | ✓ |
| 33 | Wallpaper Manager Settings UI | PROJECT.md F33, spec §4.9.2 | ≥5 | ≥5 | ✓ |

*(Note: Live Wallpaper Features 1–10 continue to be verified via `Tier1_FeatureTests.swift`, `Tier2_BoundaryTests.swift`, `Tier3_CombinationTests.swift`, and `Tier4_ScenarioTests.swift`).*

---

## 3. Test Architecture

### 3.1 Test Runner Commands
- **Full E2E Test Suite**:
  ```bash
  swift test --filter WallpaperE2ETests
  ```
- **Tier 1 Flake Feature Suite**:
  ```bash
  swift test --filter Tier1_FlakeFeatureTests
  ```
- **Tier 2 Flake Boundary Suite**:
  ```bash
  swift test --filter Tier2_FlakeBoundaryTests
  ```
- **Tier 3 Flake Combinatorial Suite**:
  ```bash
  swift test --filter Tier3_FlakeCombinationTests
  ```
- **Tier 4 Flake Scenario Suite**:
  ```bash
  swift test --filter Tier4_FlakeScenarioTests
  ```
- **Full Suite Build & Static Concurrency Check**:
  ```bash
  swift build --build-tests
  ```

### 3.2 Pass/Fail Semantics
- **100% Deterministic Pass**: All test cases must evaluate to green. Any test timeout, assertion failure, or uncaught exception constitutes immediate build failure.
- **Zero Warnings**: Compilation under Swift 6 strict concurrency (`-warnings-as-errors` compatible) must emit 0 compiler warnings.
- **Headless Isolation**: Tests execute in headless environments (such as CI runners and headless terminal sessions) utilizing simulated virtual displays (`SimulatedScreen`), `MockWindowInfoProvider`, and offscreen SpriteKit render passes.
- **Actor Isolation Enforcement**: All AppKit and SpriteKit interactions are strictly dispatched on `@MainActor` to prevent data races and runtime concurrency faults.

### 3.3 Directory Layout
```
Tests/WallpaperE2ETests/
├── E2ETestHarness.swift                 // Core Live Wallpaper test harness & mocks
├── Tier1_FeatureTests.swift             // Live Wallpaper Features 1–10 (50 tests)
├── Tier2_BoundaryTests.swift            // Live Wallpaper Features 1–10 (50 tests)
├── Tier3_CombinationTests.swift         // Live Wallpaper Pairwise Combinations (10 tests)
├── Tier4_ScenarioTests.swift            // Live Wallpaper End-to-End Workflows (6 tests)
│
├── FlakeTestHarness.swift               // Flake fixtures, simulated screens, mock windows, deterministic clock
├── Tier1_FlakeFeatureTests.swift        // Flake Features 1–33 Equivalence Tests (≥165 tests)
├── Tier2_FlakeBoundaryTests.swift       // Flake Features 1–33 Boundary Tests (≥165 tests)
├── Tier3_FlakeCombinationTests.swift    // Flake Cross-Feature Interaction Matrix (≥33 tests)
└── Tier4_FlakeScenarioTests.swift       // Flake Real-World User Scenarios (≥17 scenarios)
```

---

## 4. Real-World Application Scenarios (Tier 4)

Tier 4 tests execute complete, high-complexity multi-step user workflows simulating realistic daily desktop sessions:

| # | Scenario | Features Exercised | Complexity | Description |
|---|----------|--------------------|:----------:|-------------|
| 1 | Clean Desktop Winter Ambiance | F5, F8, F9, F12, F19, F21 | High | Launch Flake on empty desktop, run steady snowfall, observe floor accumulation, trigger automated tractor sweep, verify clean baseline. |
| 2 | Multi-Window Desktop Session | F1, F2, F3, F6, F12, F14, F16 | High | Open Safari and Xcode, accumulate snow on window tops, drag Safari across desktop, verify drift tracking, use mitten tool to brush snow off Xcode. |
| 3 | Blizzard Storm & Snowplow Evacuation | F9, F10, F11, F12, F15, F19, F20 | High | Switch to Blizzard mode with high wind, watch accumulation hit surface caps, verify automated snowmobile plow triggers and clears floor. |
| 4 | Power & Sleep Interruption Lifecycle | F8, F28, F29, F30, F31 | High | Run simulation, trigger display sleep notification (pause), wake display (resume), trigger screen lock (pause), unlock (resume), activate fullscreen app. |
| 5 | Interactive Weather Steering via Compass | F10, F11, F24, F8 | High | Drag wind compass needle from 0° East to 180° West and 270° Updraft, adjusting wind speed slider, assert real-time particle acceleration vector updates. |
| 6 | Festive Holiday Garland Evening | F2, F22, F23, F25 | High | Enable fairy lights on multi-window setup, observe alternating multi-color bulbs, assert phased twinkling glow animations across active windows. |
| 7 | Dual Layer Mode Switching | F2, F18, F25 | High | Toggle between Screen Overlay (`.floating`, click-through passthrough) and Desktop Background (`.desktop`, pinned behind icons). |
| 8 | Multi-Display Resolution Re-anchoring | F3, F5, F26, F27 | High | Configure dual monitors, dynamically simulate screen parameter change notification (e.g., 4K external display unplugged), verify overlay lifecycle. |
| 9 | Menu Bar Companion Control Workflow | F9, F16, F32, F33 | High | Toggle snowfall from menu bar icon, switch intensity via submenu, trigger "Clear Snow Now", navigate to Settings UI. |
| 10 | Deep Shovel Excavation & Clearing | F12, F15, F17, F18 | High | Accumulate dense snowdrifts on Dock and windows, engage Shovel tool, drag scoop cursor across surfaces, verify deep rectangular snow removal. |
| 11 | Dock Orientation & Dynamic Resizing | F3, F4, F5, F14 | High | Simulate Dock repositioning from bottom to left edge, verify bottom ledge adjusts, and snow accumulation respects Dock geometry. |
| 12 | Rapid Window Drag & Drop Stress | F6, F7, F13, F14 | High | Rapidly reposition windows at 60 Hz, verify 10 Hz window query throttle prevents CPU thrashing and angle-of-repose smoothing keeps drifts intact. |
| 13 | Vehicle Model Fleet Showcase | F19, F20, F21 | High | Cycle through all five snowplow models (Classic Tractor, Vintage Tractor, Snowmobile, Penguin, Custom) and execute sweeps. |
| 14 | Ambient Audio Mute & Volume Dynamics | F28, F33, F32 | High | Enable ambient winter breeze audio, adjust volume slider, toggle mute, assert audio pauses synchronously during sleep/lock. |
| 15 | Occlusion Culling with Stacking Windows | F2, F6, F12 | High | Stack multiple overlapping windows (z-index cascade), verify covered ledges are culled from collision surfaces and do not accumulate hidden drifts. |
| 16 | Manual Clear All Drifts | F12, F14, F33 | High | Generate heavy snowbanks on all active surfaces, trigger manual "Clear All Snow Now", verify immediate polygon fade and heightmap zeroing. |
| 17 | Full Application Lifecycle & Graceful Teardown | F1, F8, F25, F26, F32, F33 | High | Initialize full application stack with active wallpaper + Flake overlay, cycle states, and cleanly terminate all windows and timers without memory leaks. |

---

## 5. Coverage Thresholds

| Test Suite / Track | Scope | Target Count | Enforcement |
|--------------------|-------|:------------:|:-----------:|
| **Live Wallpaper Suite** | Features 1–10 (Tiers 1–4) | 116 tests | 100% Pass |
| **Flake Tier 1 (Equivalence)** | Features 1–33 (≥5 per feature) | ≥165 tests | 100% Pass |
| **Flake Tier 2 (Boundary)** | Features 1–33 (≥5 per feature) | ≥165 tests | 100% Pass |
| **Flake Tier 3 (Combinatorial)**| Features 1–33 (Pairwise interactions) | ≥33 tests | 100% Pass |
| **Flake Tier 4 (Scenarios)** | Features 1–33 (Real-world sessions) | ≥17 tests | 100% Pass |
| **Total Flake E2E Suite** | Features 1–33 (All 4 Tiers) | **≥380 tests** | **100% Pass** |
| **Overall Combined Suite** | Live Wallpaper + Flake E2E | **≥496 tests** | **100% Pass** |
