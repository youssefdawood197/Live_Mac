import Foundation

/// Specific domain errors thrown during wallpaper library persistence and operations.
public enum WallpaperLibraryError: LocalizedError, Equatable, Sendable {
    case itemNotFound(UUID)
    case duplicateItem(String)
    case invalidURL(String)
    case unsupportedFileType(String)
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            return "Wallpaper with ID \(id) not found in library."
        case .duplicateItem(let identifier):
            return "Wallpaper '\(identifier)' already exists in library."
        case .invalidURL(let str):
            return "Invalid wallpaper URL: \(str)"
        case .unsupportedFileType(let ext):
            return "Unsupported wallpaper file type: \(ext)"
        case .persistenceFailed(let msg):
            return "Persistence failure: \(msg)"
        }
    }
}

/// Thread-safe, actor-isolated wallpaper repository managing library state, disk persistence, and asset discovery.
public actor WallpaperLibrary {
    /// In-memory cache of wallpaper items.
    private var items: [WallpaperItem] = []

    /// Base directory where library metadata and assets reside.
    public let storageDirectory: URL

    /// File path to `wallpapers.json`.
    public let storageFile: URL

    /// Bundle searched for default sample assets.
    public let bundle: Bundle

    /// File manager instance.
    private let fileManager: FileManager

    /// Shared singleton instance pointing to the standard Application Support directory.
    public static let shared = WallpaperLibrary()

    /// Initializes a wallpaper library with custom or default storage paths.
    public init(
        storageDirectory: URL? = nil,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.bundle = bundle

        let dir: URL
        if let customDir = storageDirectory {
            dir = customDir
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            dir = appSupport.appendingPathComponent("LivelyWallpaper", isDirectory: true)
        }
        self.storageDirectory = dir
        self.storageFile = dir.appendingPathComponent("wallpapers.json")
    }

    /// Returns a snapshot of all wallpapers currently in the library.
    public func getWallpapers() -> [WallpaperItem] {
        return items
    }

    /// Retrieves an individual wallpaper by its unique ID.
    public func getWallpaper(id: UUID) -> WallpaperItem? {
        return items.first { $0.id == id }
    }

    /// Filters wallpapers by their engine/media type.
    public func getWallpapers(type: WallpaperType) -> [WallpaperItem] {
        return items.filter { $0.type == type }
    }

    /// Checks if a wallpaper with the given ID exists.
    public func contains(id: UUID) -> Bool {
        return items.contains { $0.id == id }
    }

    /// Checks if a wallpaper with the given path or URL exists.
    public func contains(pathOrURL: String) -> Bool {
        return items.contains { $0.pathOrURL == pathOrURL }
    }

    /// Loads wallpaper items from disk. Returns the loaded list.
    @discardableResult
    public func loadWallpapers() throws -> [WallpaperItem] {
        guard fileManager.fileExists(atPath: storageFile.path) else {
            self.items = []
            return []
        }

        do {
            let data = try Data(contentsOf: storageFile)
            let decoder = JSONDecoder()
            self.items = try decoder.decode([WallpaperItem].self, from: data)
            return self.items
        } catch {
            throw WallpaperLibraryError.persistenceFailed("Failed to decode wallpapers: \(error.localizedDescription)")
        }
    }

    /// Persists the current in-memory library state atomically to disk.
    public func save() throws {
        do {
            if !fileManager.fileExists(atPath: storageDirectory.path) {
                try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: storageFile, options: .atomic)
        } catch {
            throw WallpaperLibraryError.persistenceFailed("Failed to save wallpapers: \(error.localizedDescription)")
        }
    }

    /// Adds a new wallpaper to the library and optionally persists immediately.
    public func addWallpaper(_ item: WallpaperItem, saveImmediately: Bool = true) throws {
        if contains(id: item.id) {
            throw WallpaperLibraryError.duplicateItem("ID \(item.id)")
        }
        items.append(item)
        if saveImmediately {
            try save()
        }
    }

    /// Convenience alias for `addWallpaper`.
    public func add(_ item: WallpaperItem, saveImmediately: Bool = true) throws {
        try addWallpaper(item, saveImmediately: saveImmediately)
    }

    /// Updates an existing wallpaper item matching on `id`.
    public func updateWallpaper(_ item: WallpaperItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw WallpaperLibraryError.itemNotFound(item.id)
        }
        items[index] = item
        try save()
    }

    /// Removes a wallpaper item from the library.
    public func removeWallpaper(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw WallpaperLibraryError.itemNotFound(id)
        }
        items.remove(at: index)
        try save()
    }

    /// Convenience alias for `removeWallpaper`.
    public func remove(id: UUID) throws {
        try removeWallpaper(id: id)
    }

    /// Reorders wallpaper items within the library.
    public func moveWallpaper(fromIndex: Int, toIndex: Int) throws {
        guard items.indices.contains(fromIndex), items.indices.contains(toIndex) else { return }
        let moved = items.remove(at: fromIndex)
        items.insert(moved, at: toIndex)
        try save()
    }

    /// Clears all library items and deletes the underlying persistence file.
    public func clear() throws {
        items.removeAll()
        if fileManager.fileExists(atPath: storageFile.path) {
            try fileManager.removeItem(at: storageFile)
        }
    }

    /// Discovers built-in sample wallpapers bundled with the application.
    public func discoverBundledWallpapers() -> [WallpaperItem] {
        var discovered: [WallpaperItem] = []

        // 1. Look for sample_loop.mp4
        if let videoURL = bundle.url(forResource: "sample_loop", withExtension: "mp4") {
            let item = WallpaperItem(
                title: "Sample Video Loop",
                type: .video,
                pathOrURL: videoURL.path,
                volume: 1.0,
                isMuted: true,
                isInteractive: false,
                itemDescription: "Bundled looping MP4 video wallpaper",
                isBundled: true
            )
            discovered.append(item)
        }

        // 2. Look for sample_canvas/index.html
        if let canvasDir = bundle.url(forResource: "sample_canvas", withExtension: nil) {
            let indexURL = canvasDir.appendingPathComponent("index.html")
            if fileManager.fileExists(atPath: indexURL.path) {
                let item = WallpaperItem(
                    title: "Sample HTML5 Canvas",
                    type: .web,
                    pathOrURL: indexURL.path,
                    volume: 0.0,
                    isMuted: true,
                    isInteractive: true,
                    itemDescription: "Bundled interactive HTML5 canvas wallpaper",
                    isBundled: true
                )
                discovered.append(item)
            }
        } else if let indexURL = bundle.url(forResource: "index", withExtension: "html") {
            let item = WallpaperItem(
                title: "Sample HTML5 Canvas",
                type: .web,
                pathOrURL: indexURL.path,
                volume: 0.0,
                isMuted: true,
                isInteractive: true,
                itemDescription: "Bundled interactive HTML5 canvas wallpaper",
                isBundled: true
            )
            discovered.append(item)
        }

        return discovered
    }

    /// Loads the library from disk; if empty or missing, discovers bundled assets and persists them.
    @discardableResult
    public func loadAndSeedIfEmpty() throws -> [WallpaperItem] {
        try loadWallpapers()
        if items.isEmpty {
            let bundled = discoverBundledWallpapers()
            for item in bundled {
                items.append(item)
            }
            if !items.isEmpty {
                try save()
            }
        }
        return items
    }

    /// Convenience importer for a Lively package directory.
    @discardableResult
    public func importLivelyPackage(from directoryURL: URL) throws -> WallpaperItem {
        let info = try LivelyInfo.parse(fromDirectory: directoryURL)
        let item = info.makeWallpaperItem(directoryURL: directoryURL)
        try addWallpaper(item)
        return item
    }

    /// Convenience importer for a video file.
    @discardableResult
    public func importVideoFile(at fileURL: URL, title: String? = nil) throws -> WallpaperItem {
        guard let type = WallpaperType(url: fileURL), type == .video else {
            throw WallpaperLibraryError.unsupportedFileType(fileURL.pathExtension)
        }
        let wallpaperTitle = title ?? fileURL.deletingPathExtension().lastPathComponent
        let item = WallpaperItem(
            title: wallpaperTitle,
            type: .video,
            pathOrURL: fileURL.path,
            volume: 1.0,
            isMuted: true,
            isInteractive: false
        )
        try addWallpaper(item)
        return item
    }

    /// Convenience importer for a remote URL.
    @discardableResult
    public func importRemoteURL(_ url: URL, title: String? = nil) throws -> WallpaperItem {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw WallpaperLibraryError.invalidURL(url.absoluteString)
        }
        let wallpaperTitle = title ?? url.host ?? "Web Stream"
        let item = WallpaperItem(
            title: wallpaperTitle,
            type: .url,
            pathOrURL: url.absoluteString,
            volume: 1.0,
            isMuted: true,
            isInteractive: true
        )
        try addWallpaper(item)
        return item
    }
}
