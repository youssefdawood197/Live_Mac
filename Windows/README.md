# Lively Wallpaper & Flake for Windows ❄️

The official Windows companion implementation of **Lively Wallpaper** and **Flake Ambient Mode**, built on **.NET 8** and modern Windows desktop APIs.

---

## 🏗️ Architecture & Core Components

```
Windows/LivelyWallpaper.Windows/
├── Core/
│   ├── DesktopWindowManager.cs      # Explorer Progman/WorkerW wallpaper parenting
│   └── FlakeOverlayWindow.cs        # WS_EX_LAYERED transparent click-through window
├── Physics/
│   ├── CollisionSurface.cs          # Window ledge and taskbar boundary models
│   ├── FlakeConfiguration.cs        # Snowfall intensity, wind vector, tools
│   └── WindowSurfaceDetector.cs     # Win32 EnumWindows + DWM extended frame detection
├── UI/
│   └── TrayIconManager.cs           # System tray snowflake companion icon & menu
├── Program.cs                       # Windows Application lifecycle entry point
├── app.manifest                     # Per-Monitor V2 DPI awareness & Windows 11 manifest
└── LivelyWallpaper.Windows.csproj   # .NET 8 modern project specification
```

---

## 🌟 Key Features

1. **Native Desktop Windowing (`WorkerW`)**:
   - Spawns and attaches live wallpapers behind desktop icons using the Win32 `Progman` / `0x052C` message loop, ensuring normal desktop click-and-drag file interactions work without latency.

2. **Flake Ambient Snowfall & Window Drifts**:
   - Particle snowfall rendered on a layered, transparent, click-through overlay window (`WS_EX_TRANSPARENT | WS_EX_LAYERED`).
   - Uses `DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS)` to detect open window frames and the Windows Taskbar (`Shell_TrayWnd`), piling physical snowdrifts on top of open windows.

3. **Interactive Cursor Tools**:
   - Mitten and Shovel tools to brush away or scoop snowbanks.
   - Automatic snowplow clearing sweeps when bottom drifts exceed threshold.

4. **System Tray Companion**:
   - Sits in the Windows Notification Area near the clock with quick toggles (Enable/Disable, Intensity presets, Clear Snow, Settings, Exit).

---

## 🚀 Building & Running on Windows

### Prerequisites
- Windows 10 (version 1809 / build 17763 or newer) or Windows 11
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) or Visual Studio 2022 (v17.8+)

### Build
```cmd
cd Windows\LivelyWallpaper.Windows
dotnet build -c Release
```

### Run
```cmd
dotnet run -c Release
```

### Publish Single-File Executable
```cmd
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```
