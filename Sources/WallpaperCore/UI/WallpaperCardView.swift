import SwiftUI
import AppKit

/// Card component rendering an individual wallpaper item within the gallery grid.
public struct WallpaperCardView: View {
    public let item: WallpaperItem
    public let isActive: Bool
    public let onSelect: () -> Void
    public let onDelete: (() -> Void)?

    @State private var isHovered: Bool = false

    public init(
        item: WallpaperItem,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isActive = isActive
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Thumbnail Container
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Type Badge
                typeBadge
                    .padding(6)

                // Active Checkmark Indicator
                if isActive {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                                .padding(8)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            // MARK: - Metadata
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Spacer()

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                if let author = item.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let description = item.desc, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.1) : Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered && !isActive ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("Set as Wallpaper", systemImage: "sparkles")
            }

            if let onDelete = onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Wallpaper", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailView: some View {
        AsyncThumbnailView(item: item)
    }

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.type.sfSymbolName)
                .font(.system(size: 9, weight: .bold))
            Text(item.type.displayName)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.65))
        .clipShape(Capsule())
    }
}

/// Asynchronous thumbnail component providing instant cached image rendering,
/// seamless frame extraction for videos, and animated fade-in.
public struct AsyncThumbnailView: View {
    public let item: WallpaperItem
    @ObservedObject private var thumbnailManager = ThumbnailManager.shared
    @State private var loadedImage: NSImage? = nil

    public init(item: WallpaperItem) {
        self.item = item
    }

    public var body: some View {
        ZStack {
            if let image = loadedImage ?? thumbnailManager.cachedImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: item.type.sfSymbolName)
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(item.type.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .task(id: item.id) {
            if loadedImage == nil {
                if let image = await thumbnailManager.loadThumbnail(for: item) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.loadedImage = image
                    }
                }
            }
        }
    }
}
