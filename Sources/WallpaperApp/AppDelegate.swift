import AppKit
import SwiftUI
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

    private var managerWindow: NSWindow?

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

        // Hook status item callbacks
        statusItemController.onOpenManager = { [weak self] in
            self?.showManagerWindow()
        }
        statusItemController.onOpenSettings = { [weak self] in
            self?.appState.selectedNavigationTab = .settings
            self?.showManagerWindow()
        }
        statusItemController.onQuit = { [weak self] in
            self?.terminateAndQuit()
        }

        // 6. Asynchronous first-launch setup & library provisioning
        Task {
            await initializeLibraryAndPlayback()
            showManagerWindow()
        }

        // 7. Start power & fullscreen monitoring
        powerManager.startMonitoring()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManagerWindow()
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        powerManager?.stopMonitoring()
        windowManager?.terminate()
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
            }
        )

        let hostingController = NSHostingController(rootView: managerView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
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
