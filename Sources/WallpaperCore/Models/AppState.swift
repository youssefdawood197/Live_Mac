import Foundation
import Combine

/// Navigation sections within the SwiftUI Wallpaper Manager window.
public enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case library = "Library"
    case settings = "Settings"

    public var id: String { rawValue }
}

/// Central application state observable across SwiftUI views, menu bar companion, and background managers.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Core Playback State
    @Published public var isPaused: Bool = false
    @Published public var isMuted: Bool = true
    @Published public var isInteractionModeEnabled: Bool = false

    // MARK: - Library & Selection State
    @Published public var wallpapers: [WallpaperItem] = []
    @Published public var activeWallpaperId: UUID?
    @Published public var selectedNavigationTab: NavigationTab = .library
    @Published public var searchQuery: String = ""
    @Published public var filterType: WallpaperType? = nil

    // MARK: - Energy Saver Settings
    @Published public var pauseOnFullscreen: Bool = true
    @Published public var pauseOnBattery: Bool = false
    @Published public var pauseOnDisplaySleep: Bool = true

    // MARK: - Initializer
    public init(
        wallpapers: [WallpaperItem] = [],
        activeWallpaperId: UUID? = nil,
        isPaused: Bool = false,
        isMuted: Bool = true,
        isInteractionModeEnabled: Bool = false
    ) {
        self.wallpapers = wallpapers
        self.activeWallpaperId = activeWallpaperId ?? wallpapers.first?.id
        self.isPaused = isPaused
        self.isMuted = isMuted
        self.isInteractionModeEnabled = isInteractionModeEnabled
    }

    // MARK: - Computed Properties

    /// Returns the currently active `WallpaperItem` matching `activeWallpaperId`.
    public var activeWallpaper: WallpaperItem? {
        wallpapers.first(where: { $0.id == activeWallpaperId })
    }

    /// Wallpapers filtered by the current search query and type filter.
    public var filteredWallpapers: [WallpaperItem] {
        wallpapers.filter { item in
            let matchesSearch = searchQuery.isEmpty || item.title.localizedCaseInsensitiveContains(searchQuery)
            let matchesType = (filterType == nil) || (item.type == filterType)
            return matchesSearch && matchesType
        }
    }

    // MARK: - State Mutations

    /// Sets the active wallpaper by its UUID.
    public func setActiveWallpaper(id: UUID) {
        guard wallpapers.contains(where: { $0.id == id }) else { return }
        self.activeWallpaperId = id
    }

    /// Sets the active wallpaper directly.
    public func setActiveWallpaper(_ item: WallpaperItem) {
        if !wallpapers.contains(where: { $0.id == item.id }) {
            wallpapers.append(item)
        }
        self.activeWallpaperId = item.id
    }

    /// Adds a wallpaper to the in-memory state and selects it if none is currently active.
    public func addWallpaper(_ item: WallpaperItem) {
        if !wallpapers.contains(where: { $0.id == item.id }) {
            wallpapers.append(item)
        }
        if activeWallpaperId == nil {
            activeWallpaperId = item.id
        }
    }

    /// Removes a wallpaper by ID and updates the active selection if necessary.
    public func removeWallpaper(id: UUID) {
        wallpapers.removeAll(where: { $0.id == id })
        if activeWallpaperId == id {
            activeWallpaperId = wallpapers.first?.id
        }
    }

    /// Updates an existing wallpaper matching `id`.
    public func updateWallpaper(_ item: WallpaperItem) {
        if let index = wallpapers.firstIndex(where: { $0.id == item.id }) {
            wallpapers[index] = item
        }
    }

    /// Replaces the wallpaper collection wholesale and preserves selection if possible.
    public func setWallpapers(_ newWallpapers: [WallpaperItem]) {
        self.wallpapers = newWallpapers
        if let activeId = activeWallpaperId, !newWallpapers.contains(where: { $0.id == activeId }) {
            self.activeWallpaperId = newWallpapers.first?.id
        } else if activeWallpaperId == nil {
            self.activeWallpaperId = newWallpapers.first?.id
        }
    }

    /// Toggles playback pause state.
    public func togglePause() {
        isPaused.toggle()
    }

    /// Toggles audio mute state.
    public func toggleMute() {
        isMuted.toggle()
    }

    /// Toggles desktop interactive mode.
    public func toggleInteractionMode() {
        isInteractionModeEnabled.toggle()
    }
}
