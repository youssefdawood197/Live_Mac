import AppKit
import SwiftUI
import Combine
import WallpaperCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, PowerManagerDelegate {

    // MARK: - Core Subsystems

    public let appState = AppState()
    public let library = WallpaperLibrary.shared
    public let assetManager = AssetManager()
    public private(set) var windowManager: DesktopWindowManager!
    public private(set) var powerManager: PowerManager!
    public private(set) var statusItemController: StatusItemController!
    public private(set) var flakeController: FlakeController!

    private var managerWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Enforce accessory policy (menu bar app, no dock icon by default)
        NSApplication.shared.setActivationPolicy(.accessory)

        // 2. Setup standard Edit menu for clipboard keyboard shortcuts (Cmd+C, Cmd+V, Cmd+A)
        setupApplicationMenu()

        // 3. Initialize Window Manager with live hardware screens
        let screenProvider = SystemScreenProvider()
        self.windowManager = DesktopWindowManager(screenProvider: screenProvider)

        // 4. Initialize Power Manager
        self.powerManager = PowerManager(
            settings: PowerSettings(from: appState),
            windowManager: windowManager,
            screenProvider: screenProvider
        )
        self.powerManager.delegate = self

        // 5. Initialize Menu Bar Companion
        self.statusItemController = StatusItemController(
            appState: appState,
            windowManager: windowManager,
            powerManager: powerManager,
            attachToStatusBar: true
        )

        // 5b. Initialize Flake Ambient Controller
        self.flakeController = FlakeController(
            config: appState.flakeConfig,
            powerManager: powerManager
        )
        self.statusItemController.flakeController = flakeController

        // Synchronize AppState FlakeConfiguration mutations with active FlakeController
        appState.$flakeConfig
            .dropFirst()
            .sink { [weak self] newConfig in
                self?.flakeController?.config = newConfig
                self?.writeStatusSnapshot()
            }
            .store(in: &cancellables)

        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.writeStatusSnapshot()
            }
            .store(in: &cancellables)

        // Hook status item callbacks
        statusItemController.onOpenManager = { [weak self] in
            self?.showManagerWindow()
        }
        statusItemController.onOpenSettings = { [weak self] in
            self?.appState.selectedNavigationTab = .settings
            self?.showManagerWindow()
        }
        statusItemController.onOpenFlakeSettings = { [weak self] in
            self?.appState.selectedNavigationTab = .flake
            self?.showManagerWindow()
        }
        statusItemController.onQuit = { [weak self] in
            self?.terminateAndQuit()
        }

        // 6. Asynchronous first-launch setup & library provisioning
        Task {
            await initializeLibraryAndPlayback()
            parseCommandLineArguments()
            writeStatusSnapshot()
            showManagerWindow()
        }

        // 7. Start power & fullscreen monitoring
        powerManager.startMonitoring()

        // 8. Register distributed IPC command listener for CLI forwards
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedCommand(_:)),
            name: Notification.Name("com.lively.wallpaper.command"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManagerWindow()
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self, name: Notification.Name("com.lively.wallpaper.command"), object: nil)
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let statusURL = appSupport.appendingPathComponent("LivelyWallpaper/status.json")
            try? FileManager.default.removeItem(at: statusURL)
        }
        powerManager?.stopMonitoring()
        windowManager?.terminate()
        flakeController?.closeAllOverlayWindows()
        statusItemController?.terminate()
    }

    // MARK: - Library & Playback Bootstrap

    private func initializeLibraryAndPlayback() async {
        do {
            // Provision all 4K and sample wallpapers
            let extractedSamples = try await assetManager.ensureAllSamplesExtracted()

            // Load saved wallpapers from disk
            var saved = try await library.loadWallpapers()

            if saved.isEmpty {
                // Populate default samples into library on first run
                for item in extractedSamples {
                    try await library.add(item)
                }
                try await library.save()
                saved = extractedSamples
            } else {
                // Ensure any newly added bundled samples are integrated
                for item in extractedSamples {
                    if !saved.contains(where: { $0.title == item.title }) {
                        try? await library.add(item)
                        saved.append(item)
                    }
                }
                try? await library.save()
            }

            self.appState.setWallpapers(saved)

            // Select active wallpaper
            if let active = appState.activeWallpaper ?? saved.first {
                appState.setActiveWallpaper(active)
                windowManager.setWallpaper(active)
            }

            // Asynchronously resolve, extract, and backfill thumbnails for all wallpapers
            await ThumbnailManager.shared.backfillThumbnails(for: appState.wallpapers, library: library, appState: appState)
        } catch {
            print("[LivelyWallpaper] Initialization error: \(error)")
        }
    }

    // MARK: - PowerManagerDelegate

    public func powerManagerDidChangePauseState(
        _ manager: PowerManagerProtocol,
        isPaused: Bool,
        reasons: PauseReasons
    ) {
        windowManager.setPaused(isPaused)
        flakeController?.setPaused(isPaused)
    }

    // MARK: - Command Line Arguments

    @objc private func handleDistributedCommand(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let args = userInfo["args"] as? [String] else { return }
        Task { @MainActor in
            self.executeCLIArguments(args)
        }
    }

    private func parseCommandLineArguments() {
        let args = Array(CommandLine.arguments.dropFirst())
        executeCLIArguments(args)
    }

    public func executeCLIArguments(_ args: [String]) {
        if args.contains("--show-manager") {
            showManagerWindow()
        }

        if args.contains("--pause") {
            appState.isPaused = true
            windowManager?.setPaused(true)
        } else if args.contains("--play") {
            appState.isPaused = false
            windowManager?.setPaused(false)
        }

        if args.contains("--mute") {
            appState.isMuted = true
            windowManager?.setMuted(true)
        } else if args.contains("--unmute") {
            appState.isMuted = false
            windowManager?.setMuted(false)
        }

        if let idx = args.firstIndex(of: "--interactive"), idx + 1 < args.count {
            let val = args[idx + 1].lowercased()
            let enabled = (val == "on" || val == "true" || val == "1")
            appState.isInteractionModeEnabled = enabled
            windowManager?.isInteractive = enabled
        }

        if let idx = args.firstIndex(of: "--flake"), idx + 1 < args.count {
            let val = args[idx + 1].lowercased()
            appState.flakeConfig.isEnabled = (val == "on" || val == "true" || val == "1")
            flakeController?.config = appState.flakeConfig
        }

        if let idx = args.firstIndex(of: "--flake-intensity"), idx + 1 < args.count {
            let val = args[idx + 1].lowercased()
            switch val {
            case "light":
                appState.flakeConfig.intensity = .light
            case "blizzard":
                appState.flakeConfig.intensity = .blizzard
            default:
                appState.flakeConfig.intensity = .steady
            }
            flakeController?.config = appState.flakeConfig
        }

        if args.contains("--clear-snow") {
            flakeController?.clearAllSnow()
        }

        if let idx = args.firstIndex(of: "--set-wallpaper"), idx + 1 < args.count {
            let target = args[idx + 1]
            if let found = appState.wallpapers.first(where: { item in
                item.title.localizedCaseInsensitiveContains(target) || item.pathOrURL.contains(target)
            }) {
                appState.setActiveWallpaper(found)
                windowManager?.setWallpaper(found)
            }
        }

        if let idx = args.firstIndex(of: "--add-wallpaper"), idx + 1 < args.count {
            let rawPath = args[idx + 1]
            let fileURL = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                let title = fileURL.deletingPathExtension().lastPathComponent
                let ext = fileURL.pathExtension.lowercased()
                let item: WallpaperItem
                if isDir.boolValue {
                    item = WallpaperItem(title: title, type: .web, sourceURL: fileURL)
                } else if ["mp4", "mov", "m4v"].contains(ext) {
                    item = WallpaperItem(title: title, type: .video, sourceURL: fileURL)
                } else {
                    return
                }
                appState.addWallpaper(item)
                Task {
                    try? await library.add(item, saveImmediately: true)
                }
            }
        }

        writeStatusSnapshot()
    }

    public func writeStatusSnapshot() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let statusURL = appSupport.appendingPathComponent("LivelyWallpaper/status.json")

        let dict: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "activeWallpaperTitle": appState.activeWallpaper?.title ?? "None",
            "activeWallpaperType": appState.activeWallpaper?.type.rawValue ?? "None",
            "isPaused": appState.isPaused,
            "isMuted": appState.isMuted,
            "isInteractive": appState.isInteractionModeEnabled,
            "flakeEnabled": appState.flakeConfig.isEnabled,
            "flakeIntensity": appState.flakeConfig.intensity.rawValue,
            "flakeWindAngle": appState.flakeConfig.windAngleDegrees,
            "flakeWindSpeed": appState.flakeConfig.windSpeed,
            "activeTool": appState.flakeConfig.activeTool.rawValue,
            "displayCount": NSScreen.screens.count
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: statusURL, options: .atomic)
        }
    }

    // MARK: - Window Management

    public func showManagerWindow() {
        if let window = managerWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let managerView = ManagerView(
            appState: appState,
            windowManager: windowManager,
            powerManager: powerManager,
            onSelectWallpaper: { [weak self] item in
                self?.windowManager.setWallpaper(item)
            },
            onDeleteWallpaper: { [weak self] item in
                guard let self = self else { return }
                self.appState.removeWallpaper(id: item.id)
                Task {
                    try? await self.library.remove(id: item.id)
                    try? await self.library.save()
                }
            },
            onAddWallpaper: { [weak self] newItem in
                guard let self = self else { return }
                Task {
                    try? await self.library.add(newItem)
                    try? await self.library.save()
                }
            },
            onClearSnow: { [weak self] in
                self?.flakeController?.clearAllSnow()
            }
        )

        let hostingController = NSHostingController(rootView: managerView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.title = "Lively Wallpaper Manager"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        self.managerWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Auxiliary Menus & Teardown

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        // Edit Menu for Cut/Copy/Paste
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func terminateAndQuit() {
        applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        NSApplication.shared.terminate(nil)
    }
}
