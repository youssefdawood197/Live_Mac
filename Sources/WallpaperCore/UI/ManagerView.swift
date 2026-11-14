import SwiftUI

/// Main window interface for the Lively Wallpaper manager application.
public struct ManagerView: View {
    @ObservedObject public var appState: AppState
    public weak var windowManager: DesktopWindowManagerProtocol?
    public weak var powerManager: PowerManagerProtocol?

    public var onSelectWallpaper: (WallpaperItem) -> Void
    public var onDeleteWallpaper: ((WallpaperItem) -> Void)?
    public var onAddWallpaper: ((WallpaperItem) -> Void)?
    public var onClearSnow: (() -> Void)?

    public init(
        appState: AppState,
        windowManager: DesktopWindowManagerProtocol? = nil,
        powerManager: PowerManagerProtocol? = nil,
        onSelectWallpaper: @escaping (WallpaperItem) -> Void,
        onDeleteWallpaper: ((WallpaperItem) -> Void)? = nil,
        onAddWallpaper: ((WallpaperItem) -> Void)? = nil,
        onClearSnow: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.windowManager = windowManager
        self.powerManager = powerManager
        self.onSelectWallpaper = onSelectWallpaper
        self.onDeleteWallpaper = onDeleteWallpaper
        self.onAddWallpaper = onAddWallpaper
        self.onClearSnow = onClearSnow
    }

    public var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar
            List(selection: $appState.selectedNavigationTab) {
                Section(header: Text("Lively Wallpaper")) {
                    NavigationLink(value: NavigationTab.library) {
                        Label("Wallpaper Library", systemImage: "photo.stack")
                    }
                    NavigationLink(value: NavigationTab.flake) {
                        Label("Flake Snow Mode", systemImage: "snowflake")
                    }
                    NavigationLink(value: NavigationTab.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                // Active Wallpaper Quick Info in Sidebar
                if let active = appState.activeWallpaper {
                    Section(header: Text("Active Wallpaper")) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(active.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(active.type.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
        } detail: {
            // MARK: - Detail View Content
            switch appState.selectedNavigationTab {
            case .library:
                WallpaperGalleryView(
                    appState: appState,
                    windowManager: windowManager,
                    powerManager: powerManager,
                    onSelect: onSelectWallpaper,
                    onDelete: onDeleteWallpaper,
                    onAdd: onAddWallpaper
                )
            case .flake:
                FlakeSettingsView(
                    appState: appState,
                    onClearSnow: onClearSnow
                )
            case .settings:
                SettingsView(
                    appState: appState,
                    powerManager: powerManager
                )
            }
        }
        .frame(minWidth: 640, idealWidth: 920, minHeight: 480, idealHeight: 620)
    }
}
