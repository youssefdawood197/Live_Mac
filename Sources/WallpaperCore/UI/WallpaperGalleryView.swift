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
            ViewThatFits(in: .horizontal) {
                // Wide layout: single clean row
                HStack(spacing: 12) {
                    searchFieldView
                        .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

                    typeFilterPicker

                    Spacer(minLength: 8)

                    playbackControlsView

                    addWallpaperButton
                }

                // Compact layout: responsive two rows preventing text compression
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        searchFieldView
                            .frame(maxWidth: .infinity)

                        addWallpaperButton
                    }

                    HStack(spacing: 10) {
                        typeFilterPicker

                        Spacer(minLength: 8)

                        playbackControlsView
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

    // MARK: - Toolbar Controls Subviews

    private var searchFieldView: some View {
        HStack(spacing: 6) {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var typeFilterPicker: some View {
        Picker("Filter", selection: $appState.filterType) {
            Text("All").tag(WallpaperType?.none)
            Text("Videos").tag(WallpaperType?.some(.video))
            Text("HTML5 Web").tag(WallpaperType?.some(.web))
            Text("URLs").tag(WallpaperType?.some(.url))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }

    private var playbackControlsView: some View {
        HStack(spacing: 8) {
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
            .fixedSize(horizontal: true, vertical: false)

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
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var addWallpaperButton: some View {
        Button(action: { showingAddSheet = true }) {
            Label("Add Wallpaper", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(appState.searchQuery.isEmpty ? "No Wallpapers in Library" : "No Matching Wallpapers Found")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(appState.searchQuery.isEmpty ? "Click 'Add Wallpaper' to import an MP4/MOV video, HTML5 folder, or web URL." : "Try clearing your search term or changing the category filter.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            if appState.searchQuery.isEmpty {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Your First Wallpaper", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
