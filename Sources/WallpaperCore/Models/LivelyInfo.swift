import Foundation

/// Raw wallpaper classification enumeration matching the official Windows Lively Wallpaper specification.
public enum LivelyWallpaperType: Int, Codable, Sendable, Equatable {
    case web = 0
    case webstream = 1
    case video = 2
    case gif = 3
    case unity = 4
    case godot = 5
    case videostream = 6
    case app = 7
    case picture = 8
    case unknown = -1

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = LivelyWallpaperType(rawValue: intVal) ?? .unknown
            return
        }
        if let strVal = try? container.decode(String.self) {
            switch strVal.lowercased() {
            case "web", "0": self = .web
            case "webstream", "1": self = .webstream
            case "video", "2": self = .video
            case "gif", "3": self = .gif
            case "unity", "4": self = .unity
            case "godot", "5": self = .godot
            case "videostream", "6": self = .videostream
            case "app", "7": self = .app
            case "picture", "8": self = .picture
            default: self = .unknown
            }
            return
        }
        self = .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Metadata schema parser for Lively Wallpaper manifest files (`LivelyInfo.json`).
public struct LivelyInfo: Codable, Sendable, Equatable {
    /// Schema application version.
    public let appVersion: String?

    /// Display title of the wallpaper.
    public let title: String

    /// Relative filename of the thumbnail image (e.g., "thumbnail.jpg").
    public let thumbnail: String?

    /// Relative filename of the preview GIF/video (e.g., "preview.gif").
    public let preview: String?

    /// Description of the wallpaper.
    public let desc: String?

    /// Author or artist name.
    public let author: String?

    /// Licensing terms.
    public let license: String?

    /// Contact website or email.
    public let contact: String?

    /// Lively wallpaper type.
    public let type: LivelyWallpaperType

    /// Relative or absolute path to the main runnable asset (e.g., "index.html", "loop.mp4").
    public let fileName: String

    /// Optional command-line or query arguments.
    public let arguments: String?

    /// Explicit flag indicating whether fileName is an absolute path.
    public let isAbsolutePath: Bool?

    enum CodingKeys: String, CodingKey {
        case appVersion = "AppVersion"
        case title = "Title"
        case thumbnail = "Thumbnail"
        case preview = "Preview"
        case desc = "Desc"
        case description = "Description"
        case author = "Author"
        case license = "License"
        case contact = "Contact"
        case type = "Type"
        case fileName = "FileName"
        case arguments = "Arguments"
        case isAbsolutePath = "IsAbsolutePath"
    }

    public init(
        appVersion: String? = nil,
        title: String,
        thumbnail: String? = nil,
        preview: String? = nil,
        desc: String? = nil,
        author: String? = nil,
        license: String? = nil,
        contact: String? = nil,
        type: LivelyWallpaperType,
        fileName: String,
        arguments: String? = nil,
        isAbsolutePath: Bool? = nil
    ) {
        self.appVersion = appVersion
        self.title = title
        self.thumbnail = thumbnail
        self.preview = preview
        self.desc = desc
        self.author = author
        self.license = license
        self.contact = contact
        self.type = type
        self.fileName = fileName
        self.arguments = arguments
        self.isAbsolutePath = isAbsolutePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        self.title = try container.decode(String.self, forKey: .title)
        self.thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        self.preview = try container.decodeIfPresent(String.self, forKey: .preview)

        if let d = try container.decodeIfPresent(String.self, forKey: .desc) {
            self.desc = d
        } else if let d = try container.decodeIfPresent(String.self, forKey: .description) {
            self.desc = d
        } else {
            self.desc = nil
        }

        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.license = try container.decodeIfPresent(String.self, forKey: .license)
        self.contact = try container.decodeIfPresent(String.self, forKey: .contact)
        self.type = try container.decodeIfPresent(LivelyWallpaperType.self, forKey: .type) ?? .unknown
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.arguments = try container.decodeIfPresent(String.self, forKey: .arguments)
        self.isAbsolutePath = try container.decodeIfPresent(Bool.self, forKey: .isAbsolutePath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(desc, forKey: .desc)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(license, forKey: .license)
        try container.encodeIfPresent(contact, forKey: .contact)
        try container.encode(type, forKey: .type)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(arguments, forKey: .arguments)
        try container.encodeIfPresent(isAbsolutePath, forKey: .isAbsolutePath)
    }

    /// Maps the Lively classification to the native macOS `WallpaperType`.
    public var nativeWallpaperType: WallpaperType {
        switch type {
        case .video:
            return .video
        case .web:
            return .web
        case .webstream, .videostream:
            return .url
        case .gif:
            return .video
        case .picture:
            return .web
        default:
            let ext = (fileName as NSString).pathExtension.lowercased()
            if ["mp4", "mov", "m4v", "webm", "avi", "mkv"].contains(ext) {
                return .video
            } else if ["html", "htm"].contains(ext) {
                return .web
            } else if fileName.hasPrefix("http://") || fileName.hasPrefix("https://") {
                return .url
            }
            return .web
        }
    }

    /// Parses a `LivelyInfo` struct from raw JSON data.
    public static func parse(data: Data) throws -> LivelyInfo {
        let decoder = JSONDecoder()
        return try decoder.decode(LivelyInfo.self, from: data)
    }

    /// Parses `LivelyInfo` from a file or directory URL.
    public static func parse(from url: URL) throws -> LivelyInfo {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
            return try parse(fromDirectory: url)
        }
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    /// Inspects a directory for `LivelyInfo.json` (case-insensitively) and parses it.
    public static func parse(fromDirectory dirURL: URL) throws -> LivelyInfo {
        let fileManager = FileManager.default
        let candidates = ["LivelyInfo.json", "livelyinfo.json", "LIVELYINFO.JSON"]
        for candidate in candidates {
            let candidateURL = dirURL.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: candidateURL.path) {
                let data = try Data(contentsOf: candidateURL)
                return try parse(data: data)
            }
        }
        throw NSError(
            domain: "LivelyInfoParser",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No LivelyInfo.json found in directory: \(dirURL.path)"]
        )
    }

    /// Converts this Lively metadata definition into a production `WallpaperItem`.
    public func makeWallpaperItem(directoryURL: URL? = nil) -> WallpaperItem {
        let resolvedPathOrURL: String
        let resolvedThumb: String?
        let resolvedPrev: String?

        let isAbsolute = isAbsolutePath ?? (fileName.hasPrefix("/") || fileName.hasPrefix("http://") || fileName.hasPrefix("https://"))

        if isAbsolute {
            resolvedPathOrURL = fileName
        } else if let dirURL = directoryURL {
            resolvedPathOrURL = dirURL.appendingPathComponent(fileName).path
        } else {
            resolvedPathOrURL = fileName
        }

        if let thumb = thumbnail, !thumb.isEmpty {
            if thumb.hasPrefix("/") || thumb.hasPrefix("http://") || thumb.hasPrefix("https://") {
                resolvedThumb = thumb
            } else if let dirURL = directoryURL {
                resolvedThumb = dirURL.appendingPathComponent(thumb).path
            } else {
                resolvedThumb = thumb
            }
        } else {
            resolvedThumb = nil
        }

        if let prev = preview, !prev.isEmpty {
            if prev.hasPrefix("/") || prev.hasPrefix("http://") || prev.hasPrefix("https://") {
                resolvedPrev = prev
            } else if let dirURL = directoryURL {
                resolvedPrev = dirURL.appendingPathComponent(prev).path
            } else {
                resolvedPrev = prev
            }
        } else {
            resolvedPrev = nil
        }

        let isWeb = (nativeWallpaperType == .web || nativeWallpaperType == .url)

        return WallpaperItem(
            title: title,
            type: nativeWallpaperType,
            pathOrURL: resolvedPathOrURL,
            thumbnailPath: resolvedThumb,
            volume: 1.0,
            isMuted: true,
            isInteractive: isWeb,
            itemDescription: desc,
            author: author,
            license: license,
            previewPath: resolvedPrev,
            isBundled: false
        )
    }
}
