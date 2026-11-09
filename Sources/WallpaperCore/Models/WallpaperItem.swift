import Foundation

/// Core data model representing an individual wallpaper item in the library.
public struct WallpaperItem: Identifiable, Hashable, Codable, Sendable {
    /// Unique identifier for this wallpaper instance.
    public let id: UUID

    /// Human-readable title of the wallpaper.
    public var title: String

    /// The engine and media type of the wallpaper.
    public var type: WallpaperType

    /// Absolute local filesystem path or remote URL string.
    public var pathOrURL: String

    /// Optional local path or remote URL to the thumbnail preview image.
    public var thumbnailPath: String?

    /// Playback volume level clamped between 0.0 (silent) and 1.0 (maximum).
    public var volume: Float

    /// Indicates whether audio output is currently muted.
    public var isMuted: Bool

    /// Indicates whether direct desktop mouse and keyboard interaction is active.
    public var isInteractive: Bool

    /// Creation or ingestion timestamp.
    public var createdAt: Date

    /// Optional descriptive summary or user notes.
    public var itemDescription: String?

    /// Optional author or creator credit.
    public var author: String?

    /// Optional license string (e.g., MIT, CC-BY).
    public var license: String?

    /// Optional path to an animated preview GIF or short video clip.
    public var previewPath: String?

    /// Indicates whether this item is a built-in default asset bundled with the app.
    public var isBundled: Bool

    /// Designated initializer with defensive clamping and sensible defaults.
    public init(
        id: UUID = UUID(),
        title: String,
        type: WallpaperType,
        pathOrURL: String,
        thumbnailPath: String? = nil,
        volume: Float = 1.0,
        isMuted: Bool = true,
        isInteractive: Bool = false,
        createdAt: Date = Date(),
        itemDescription: String? = nil,
        author: String? = nil,
        license: String? = nil,
        previewPath: String? = nil,
        isBundled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.pathOrURL = pathOrURL
        self.thumbnailPath = thumbnailPath
        if volume.isNaN {
            self.volume = 0.0
        } else if volume.isInfinite {
            self.volume = volume > 0 ? 1.0 : 0.0
        } else {
            self.volume = min(max(volume, 0.0), 1.0)
        }
        self.isMuted = isMuted
        self.isInteractive = isInteractive
        self.createdAt = createdAt
        self.itemDescription = itemDescription
        self.author = author
        self.license = license
        self.previewPath = previewPath
        self.isBundled = isBundled
    }

    // MARK: - Convenience Initializer & Accessors

    /// Convenience initializer accepting Foundation `URL` instances and standard aliases.
    public init(
        id: UUID = UUID(),
        title: String,
        type: WallpaperType,
        sourceURL: URL,
        thumbnailURL: URL? = nil,
        duration: Double? = nil,
        volume: Float = 1.0,
        isMuted: Bool = true,
        isInteractive: Bool = false,
        desc: String? = nil,
        author: String? = nil,
        license: String? = nil,
        previewPath: String? = nil,
        isBundled: Bool = false
    ) {
        let pathString = (type == .url || sourceURL.scheme == "http" || sourceURL.scheme == "https")
            ? sourceURL.absoluteString
            : sourceURL.path

        self.init(
            id: id,
            title: title,
            type: type,
            pathOrURL: pathString,
            thumbnailPath: thumbnailURL?.path ?? thumbnailURL?.absoluteString,
            volume: volume,
            isMuted: isMuted,
            isInteractive: isInteractive,
            itemDescription: desc,
            author: author,
            license: license,
            previewPath: previewPath,
            isBundled: isBundled
        )
    }

    /// Accessor for Foundation URL representation of `pathOrURL`.
    public var sourceURL: URL {
        resolvedURL ?? URL(fileURLWithPath: pathOrURL)
    }

    /// Accessor for Foundation URL representation of `thumbnailPath`.
    public var thumbnailURL: URL? {
        resolvedThumbnailURL
    }

    /// Alias for `itemDescription`.
    public var desc: String? {
        get { itemDescription }
        set { itemDescription = newValue }
    }

    /// Resolves `pathOrURL` to a valid Foundation `URL`.
    public var resolvedURL: URL? {
        if type == .url || pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            return URL(string: pathOrURL)
        }
        return URL(fileURLWithPath: pathOrURL)
    }

    /// Resolves `thumbnailPath` to a valid Foundation `URL`.
    public var resolvedThumbnailURL: URL? {
        guard let thumb = thumbnailPath, !thumb.isEmpty else { return nil }
        if thumb.hasPrefix("http://") || thumb.hasPrefix("https://") {
            return URL(string: thumb)
        }
        return URL(fileURLWithPath: thumb)
    }

    /// Checks if the underlying local file exists (always returns true for remote URLs).
    public var fileExists: Bool {
        if type == .url { return true }
        let path = resolvedURL?.path ?? pathOrURL
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Codable Conformance with Legacy Support
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case pathOrURL
        case thumbnailPath
        case volume
        case isMuted
        case isInteractive
        case createdAt
        case dateAdded
        case itemDescription
        case description
        case desc
        case author
        case license
        case previewPath
        case isBundled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.type = try container.decode(WallpaperType.self, forKey: .type)
        self.pathOrURL = try container.decode(String.self, forKey: .pathOrURL)
        self.thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)

        let rawVolume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        if rawVolume.isNaN {
            self.volume = 0.0
        } else if rawVolume.isInfinite {
            self.volume = rawVolume > 0 ? 1.0 : 0.0
        } else {
            self.volume = min(max(rawVolume, 0.0), 1.0)
        }
        self.isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
        self.isInteractive = try container.decodeIfPresent(Bool.self, forKey: .isInteractive) ?? false

        if let date = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            self.createdAt = date
        } else if let date = try container.decodeIfPresent(Date.self, forKey: .dateAdded) {
            self.createdAt = date
        } else {
            self.createdAt = Date()
        }

        if let d = try container.decodeIfPresent(String.self, forKey: .itemDescription) {
            self.itemDescription = d
        } else if let d = try container.decodeIfPresent(String.self, forKey: .description) {
            self.itemDescription = d
        } else if let d = try container.decodeIfPresent(String.self, forKey: .desc) {
            self.itemDescription = d
        } else {
            self.itemDescription = nil
        }

        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.license = try container.decodeIfPresent(String.self, forKey: .license)
        self.previewPath = try container.decodeIfPresent(String.self, forKey: .previewPath)
        self.isBundled = try container.decodeIfPresent(Bool.self, forKey: .isBundled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encode(pathOrURL, forKey: .pathOrURL)
        try container.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
        try container.encode(volume, forKey: .volume)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isInteractive, forKey: .isInteractive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(itemDescription, forKey: .itemDescription)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(license, forKey: .license)
        try container.encodeIfPresent(previewPath, forKey: .previewPath)
        try container.encode(isBundled, forKey: .isBundled)
    }
}
