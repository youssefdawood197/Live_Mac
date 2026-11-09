# E2E Test Infra: Lively Wallpaper for macOS

## Test Philosophy
- Opaque-box, requirement-driven. No dependency on implementation design.
- Methodology: Category-Partition + Boundary Value Analysis (BVA) + Pairwise Combinatorial Testing + Real-World Workload Testing.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | Desktop Window Leveling & Spaces | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | Mouse Event Passthrough & Interactive Mode | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 3 | Video Playback & Seamless Looping | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 4 | Video Audio & Volume Controls | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 5 | Local Web Wallpaper (HTML5/Canvas/WebGL) | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 6 | Remote Web Wallpaper Live URLs | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 7 | Web Resource & Audio Suspension | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 8 | Menu Bar Companion Controls | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 9 | SwiftUI Wallpaper Manager Gallery & Ingestion | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 10 | Energy Saver Auto-Pause Engine | ORIGINAL_REQUEST §R5 | 5 | 5 | ✓ |

## Test Architecture
- Test runner: `swift test --filter WallpaperE2ETests`
- Test framework: Swift XCTest / Swift Testing executing headless verification routines
- Target directory: `Tests/WallpaperE2ETests/`
  - `E2ETestHarness.swift`: Headless environment mock and opaque test assertion helpers
  - `Tier1_FeatureTests.swift`: Equivalence class feature tests (≥5 per feature, 50 total)
  - `Tier2_BoundaryTests.swift`: Boundary value and error condition tests (≥5 per feature, 50 total)
  - `Tier3_CombinationTests.swift`: Cross-feature pairwise interaction tests (≥10 tests)
  - `Tier4_ScenarioTests.swift`: Real-world end-to-end user workflows (6 scenarios)

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Full App Lifecycle (Launch into menu bar, summon manager, verify state, quit) | F8, F9 | High |
| 2 | Video Wallpaper Workflow (Load MP4, verify looping, adjust volume, toggle mute) | F3, F4, F8 | High |
| 3 | Interactive Web Wallpaper Workflow (Load HTML5 folder, toggle interactive mode, handle events) | F1, F2, F5 | High |
| 4 | Energy Saver Auto-Pause (Fullscreen app detection, verify pause, exit fullscreen, verify resume) | F3, F10 | High |
| 5 | Display Sleep & Wake (Trigger display sleep, verify suspension, trigger wake, verify playback) | F3, F5, F10 | High |
| 6 | Hybrid Wallpaper Switcher (Switch between video, local HTML5, and remote URL) | F2, F3, F4, F5, F6, F8 | High |

## Coverage Thresholds
- Tier 1: ≥5 per feature (50 test cases)
- Tier 2: ≥5 per feature (50 test cases)
- Tier 3: Pairwise coverage of major feature interactions (≥10 test cases)
- Tier 4: Realistic application workflows (≥5 test cases)
- Total minimum: ≥115 test cases
