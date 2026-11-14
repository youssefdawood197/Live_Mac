import AppKit
import Combine
import Foundation

/// Coordinates the macOS Menu Bar companion icon (`NSStatusItem`) and quick control menu.
///
/// Provides rapid access to playback pause/resume, audio mute/unmute, interactive mode toggling,
/// dynamic wallpaper quick-switching submenu, and launching the SwiftUI Wallpaper Manager.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {

    // MARK: - Observable State & Contracts

    public private(set) var title: String = "Lively Wallpaper"
    public private(set) var iconName: String = "sparkles.tv"
    public private(set) var playPauseTitle: String = "Pause"
    public private(set) var muteTitle: String = "Mute"
    public private(set) var isInteractiveChecked: Bool = false
    public private(set) var quickPickerWallpapers: [WallpaperItem] = []
    public var isManagerOpen: Bool = false
    public var isTerminated: Bool = false

    // MARK: - Delegates & Coordination

    public weak var appState: AppState?
    public weak var windowManager: DesktopWindowManagerProtocol?
    public weak var powerManager: PowerManagerProtocol?
    public weak var flakeController: FlakeController?

    public var onOpenManager: (@MainActor () -> Void)?
    public var onOpenSettings: (@MainActor () -> Void)?
    public var onOpenFlakeSettings: (@MainActor () -> Void)?
    public var onQuit: (@MainActor () -> Void)?

    // MARK: - AppKit Menu Components

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var cancellables: Set<AnyCancellable> = []

    private var playPauseMenuItem: NSMenuItem?
    private var muteMenuItem: NSMenuItem?
    private var interactiveMenuItem: NSMenuItem?
    private var wallpapersSubmenuItem: NSMenuItem?

    // MARK: - Initialization

    public init(
        appState: AppState? = nil,
        windowManager: DesktopWindowManagerProtocol? = nil,
        powerManager: PowerManagerProtocol? = nil,
        attachToStatusBar: Bool = true
    ) {
        self.appState = appState
        self.windowManager = windowManager
        self.powerManager = powerManager
        super.init()

        if attachToStatusBar {
            setupStatusItem()
        }
        setupBindings()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        guard !ProcessInfo.processInfo.arguments.contains("-headless") else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Lively Wallpaper") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✨"
            }
            button.toolTip = "Lively Wallpaper for macOS"
        }

        let newMenu = NSMenu(title: "Lively Wallpaper")
        newMenu.delegate = self
        self.menu = newMenu
        item.menu = newMenu
        self.statusItem = item

        rebuildMenu()
    }

    // MARK: - Dynamic Menu Construction

    public func rebuildMenu() {
        guard let menu = self.menu else { return }
        menu.removeAllItems()

        // 1. Header item
        let headerItem = NSMenuItem(title: "Lively Wallpaper", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        if let boldFont = NSFont.boldSystemFont(ofSize: 13) as NSFont? {
            headerItem.attributedTitle = NSAttributedString(
                string: "Lively Wallpaper",
                attributes: [.font: boldFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Play / Pause
        let playPauseItem = NSMenuItem(
            title: playPauseTitle,
            action: #selector(playPauseClicked),
            keyEquivalent: "p"
        )
        playPauseItem.target = self
        menu.addItem(playPauseItem)
        self.playPauseMenuItem = playPauseItem

        // 3. Mute / Unmute
        let muteItem = NSMenuItem(
            title: muteTitle,
            action: #selector(muteClicked),
            keyEquivalent: "m"
        )
        muteItem.target = self
        menu.addItem(muteItem)
        self.muteMenuItem = muteItem

        // 4. Interactive Mode Toggle
        let interactiveItem = NSMenuItem(
            title: "Interactive Desktop",
            action: #selector(interactiveClicked),
            keyEquivalent: "i"
        )
        interactiveItem.target = self
        interactiveItem.state = isInteractiveChecked ? .on : .off
        menu.addItem(interactiveItem)
        self.interactiveMenuItem = interactiveItem

        // 4b. Flake Snow Mode Submenu
        let flakeItem = NSMenuItem(title: "Flake Snow Mode", action: nil, keyEquivalent: "")
        let flakeSubmenu = NSMenu(title: "Flake Snow Mode")
        populateFlakeSubmenu(flakeSubmenu)
        flakeItem.submenu = flakeSubmenu
        menu.addItem(flakeItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quick Wallpapers Submenu
        let wallpapersItem = NSMenuItem(title: "Wallpapers", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Wallpapers")
        populateWallpapersSubmenu(submenu)
        wallpapersItem.submenu = submenu
        menu.addItem(wallpapersItem)
        self.wallpapersSubmenuItem = wallpapersItem

        menu.addItem(NSMenuItem.separator())

        // 6. Open Wallpaper Manager
        let managerItem = NSMenuItem(
            title: "Wallpaper Manager...",
            action: #selector(openManagerClicked),
            keyEquivalent: "o"
        )
        managerItem.target = self
        menu.addItem(managerItem)

        // 7. Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 8. Quit
        let quitItem = NSMenuItem(
            title: "Quit Lively Wallpaper",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func populateWallpapersSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()

        if quickPickerWallpapers.isEmpty {
            let emptyItem = NSMenuItem(title: "No Wallpapers Found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        let activeId = appState?.activeWallpaperId ?? windowManager?.activeWallpaper?.id

        for wallpaper in quickPickerWallpapers {
            let item = NSMenuItem(
                title: wallpaper.title,
                action: #selector(wallpaperSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = wallpaper
            item.state = (wallpaper.id == activeId) ? .on : .off
            submenu.addItem(item)
        }
    }

    private func populateFlakeSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()

        let isFlakeActive = appState?.flakeConfig.isEnabled ?? false

        // Toggle on/off
        let toggleItem = NSMenuItem(
            title: isFlakeActive ? "Disable Snowfall" : "Enable Snowfall",
            action: #selector(flakeToggleClicked),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = isFlakeActive ? .on : .off
        submenu.addItem(toggleItem)

        if isFlakeActive {
            submenu.addItem(NSMenuItem.separator())

            // Intensity section
            let intensityHeader = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
            intensityHeader.isEnabled = false
            submenu.addItem(intensityHeader)

            let currentIntensity = appState?.flakeConfig.intensity ?? .steady
            for intensity in SnowfallIntensity.allCases {
                let item = NSMenuItem(
                    title: intensity.rawValue,
                    action: #selector(flakeIntensitySelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = intensity
                item.state = (currentIntensity == intensity) ? .on : .off
                submenu.addItem(item)
            }

            submenu.addItem(NSMenuItem.separator())

            // Clear snow
            let clearItem = NSMenuItem(
                title: "Clear Snow Drifts",
                action: #selector(clearSnowClicked),
                keyEquivalent: ""
            )
            clearItem.target = self
            submenu.addItem(clearItem)
        }

        submenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Flake Settings...",
            action: #selector(openFlakeSettingsClicked),
            keyEquivalent: ""
        )
        settingsItem.target = self
        submenu.addItem(settingsItem)
    }

    // MARK: - State Update Protocol

    /// Synchronizes status item companion state with core models.
    public func update(
        isPaused: Bool,
        isMuted: Bool,
        isInteractive: Bool,
        wallpapers: [WallpaperItem]
    ) {
        self.playPauseTitle = isPaused ? "Resume" : "Pause"
        self.muteTitle = isMuted ? "Unmute" : "Mute"
        self.isInteractiveChecked = isInteractive
        self.quickPickerWallpapers = wallpapers

        playPauseMenuItem?.title = playPauseTitle
        muteMenuItem?.title = muteTitle
        interactiveMenuItem?.state = isInteractive ? .on : .off

        if let submenu = wallpapersSubmenuItem?.submenu {
            populateWallpapersSubmenu(submenu)
        }
    }

    // MARK: - Combine Bindings

    private func setupBindings() {
        guard let appState = self.appState else { return }

        Publishers.CombineLatest4(
            appState.$isPaused,
            appState.$isMuted,
            appState.$isInteractionModeEnabled,
            appState.$wallpapers
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] isPaused, isMuted, isInteractive, wallpapers in
            self?.update(
                isPaused: isPaused,
                isMuted: isMuted,
                isInteractive: isInteractive,
                wallpapers: wallpapers
            )
        }
        .store(in: &cancellables)

        appState.$activeWallpaperId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let submenu = self.wallpapersSubmenuItem?.submenu else { return }
                self.populateWallpapersSubmenu(submenu)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func playPauseClicked() {
        if let appState = self.appState {
            appState.togglePause()
            windowManager?.setPaused(appState.isPaused)
        } else {
            let nextPaused = (playPauseTitle == "Pause")
            windowManager?.setPaused(nextPaused)
            playPauseTitle = nextPaused ? "Resume" : "Pause"
            playPauseMenuItem?.title = playPauseTitle
        }
    }

    @objc private func muteClicked() {
        if let appState = self.appState {
            appState.toggleMute()
            windowManager?.setMuted(appState.isMuted)
        } else {
            let nextMuted = (muteTitle == "Mute")
            windowManager?.setMuted(nextMuted)
            muteTitle = nextMuted ? "Unmute" : "Mute"
            muteMenuItem?.title = muteTitle
        }
    }

    @objc private func interactiveClicked() {
        if let appState = self.appState {
            appState.toggleInteractionMode()
            windowManager?.isInteractive = appState.isInteractionModeEnabled
        } else {
            isInteractiveChecked.toggle()
            windowManager?.isInteractive = isInteractiveChecked
            interactiveMenuItem?.state = isInteractiveChecked ? .on : .off
        }
    }

    @objc private func wallpaperSelected(_ sender: NSMenuItem) {
        guard let wallpaper = sender.representedObject as? WallpaperItem else { return }
        appState?.setActiveWallpaper(wallpaper)
        windowManager?.setWallpaper(wallpaper)

        if let submenu = wallpapersSubmenuItem?.submenu {
            populateWallpapersSubmenu(submenu)
        }
    }

    @objc private func flakeToggleClicked() {
        guard let appState = self.appState else { return }
        appState.flakeConfig.isEnabled.toggle()
        flakeController?.config = appState.flakeConfig
        rebuildMenu()
    }

    @objc private func flakeIntensitySelected(_ sender: NSMenuItem) {
        guard let appState = self.appState, let intensity = sender.representedObject as? SnowfallIntensity else { return }
        appState.flakeConfig.intensity = intensity
        flakeController?.config = appState.flakeConfig
        rebuildMenu()
    }

    @objc private func clearSnowClicked() {
        flakeController?.clearAllSnow()
    }

    @objc private func openFlakeSettingsClicked() {
        appState?.selectedNavigationTab = .flake
        isManagerOpen = true
        if let onOpenFlakeSettings = onOpenFlakeSettings {
            onOpenFlakeSettings()
        } else {
            onOpenManager?()
        }
    }

    @objc private func openManagerClicked() {
        isManagerOpen = true
        onOpenManager?()
    }

    @objc private func openSettingsClicked() {
        appState?.selectedNavigationTab = .settings
        isManagerOpen = true
        onOpenSettings?()
    }

    @objc private func quitClicked() {
        if let onQuit = onQuit {
            onQuit()
        } else {
            terminate()
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Teardown

    public func terminate() {
        isTerminated = true
        cancellables.removeAll()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        if let submenu = wallpapersSubmenuItem?.submenu {
            populateWallpapersSubmenu(submenu)
        }
    }
}
