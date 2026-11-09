import SwiftUI

/// Gallery view presenting the user's wallpaper library in an adaptive grid.
public struct WallpaperGalleryView: View {
    @ObservedObject public var appState: AppState
    public weak var windowManager: DesktopWindowManagerProtocol?
    public weak var powerManager: PowerManagerProtocol?

    public var onSelect: (WallpaperItem) -> Void
    public var onDelete: ((WallpaperItem) -> Void)?
    public var onAdd: ((WallpaperItem) -> Void)?

    @State private var showingAddSheet: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)
    ]

    public init(
        appState: AppState,
        windowManager: DesktopWindowManagerProtocol? = nil,
        powerManager: PowerManagerProtocol? = nil,
        onSelect: @escaping (WallpaperItem) -> Void,
        onDelete: ((WallpaperItem) -> Void)? = nil,
        onAdd: ((WallpaperItem) -> Void)? = nil
    ) {
        self.appState = appState
        self.windowManager = windowManager
        self.powerManager = powerManager
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Filter & Search Toolbar
            HStack(spacing: 12) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search wallpapers...", text: $appState.searchQuery)
                        .textFieldStyle(.plain)
                    if !appState.searchQuery.isEmpty {
                        Button(action: { appState.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 240)

                // Type Filter Picker
                Picker("Filter", selection: $appState.filterType) {
                    Text("All").tag(WallpaperType?.none)
                    Text("Videos").tag(WallpaperType?.some(.video))
                    Text("HTML5 Web").tag(WallpaperType?.some(.web))
                    Text("URLs").tag(WallpaperType?.some(.url))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Spacer()

                // Playback Controls
                Button(action: {
                    appState.togglePause()
                    windowManager?.setPaused(appState.isPaused)
                }) {
                    Label(
                        appState.isPaused ? "Resume" : "Pause",
                        systemImage: appState.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .help("Pause or resume live wallpaper rendering")

                Button(action: {
                    appState.toggleMute()
                    windowManager?.setMuted(appState.isMuted)
                }) {
                    Label(
                        appState.isMuted ? "Unmute" : "Mute",
                        systemImage: appState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    )
                }
                .help("Mute or unmute wallpaper audio")

                // Add Wallpaper Button
                Button(action: { showingAddSheet = true }) {
                    Label("Add Wallpaper", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - Gallery Grid
            ScrollView {
                if appState.filteredWallpapers.isEmpty {
                    emptyStateView
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.filteredWallpapers) { item in
                            WallpaperCardView(
                                item: item,
                                isActive: appState.activeWallpaperId == item.id,
                                onSelect: {
                                    appState.setActiveWallpaper(item)
                                    onSelect(item)
                                },
                                onDelete: onDelete != nil ? {
                                    onDelete?(item)
                                } : nil
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWallpaperSheet { newItem in
                appState.addWallpaper(newItem)
                onAdd?(newItem)
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(appState.searchQuery.isEmpty ? "No Wallpapers in Library" : "No Matching Wallpapers Found")
                .font(.headline)
            Text(appState.searchQuery.isEmpty ? "Click 'Add Wallpaper' to import an MP4/MOV video, HTML5 folder, or web URL." : "Try clearing your search term or changing the category filter.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if appState.searchQuery.isEmpty {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Your First Wallpaper", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
