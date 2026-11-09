import XCTest
@testable import WallpaperCore

final class ModelTests: XCTestCase {

    // MARK: - 1. WallpaperType Tests

    func testWallpaperTypeEnumCasesAndRawValues() {
        XCTAssertEqual(WallpaperType.allCases.count, 3)
        XCTAssertEqual(WallpaperType.video.rawValue, "video")
        XCTAssertEqual(WallpaperType.web.rawValue, "web")
        XCTAssertEqual(WallpaperType.url.rawValue, "url")
    }

    func testWallpaperTypeDisplayNames() {
        XCTAssertEqual(WallpaperType.video.displayName, "Video")
        XCTAssertEqual(WallpaperType.web.displayName, "Web Page")
        XCTAssertEqual(WallpaperType.url.displayName, "Web URL")
    }

    func testWallpaperTypeSystemIcons() {
        XCTAssertEqual(WallpaperType.video.systemIconName, "video.fill")
        XCTAssertEqual(WallpaperType.web.systemIconName, "safari.fill")
        XCTAssertEqual(WallpaperType.url.systemIconName, "link")
    }

    func testWallpaperTypeCapabilities() {
        // Web-based
        XCTAssertFalse(WallpaperType.video.isWebBased)
        XCTAssertTrue(WallpaperType.web.isWebBased)
        XCTAssertTrue(WallpaperType.url.isWebBased)

        // Audio support
        XCTAssertTrue(WallpaperType.video.supportsAudio)
        XCTAssertTrue(WallpaperType.web.supportsAudio)
        XCTAssertFalse(WallpaperType.url.supportsAudio)

        // Interaction support
        XCTAssertFalse(WallpaperType.video.supportsInteraction)
        XCTAssertTrue(WallpaperType.web.supportsInteraction)
        XCTAssertTrue(WallpaperType.url.supportsInteraction)
    }

    func testWallpaperTypeFileExtensionInference() {
        XCTAssertEqual(WallpaperType(fileExtension: "mp4"), .video)
        XCTAssertEqual(WallpaperType(fileExtension: "MOV"), .video)
        XCTAssertEqual(WallpaperType(fileExtension: "m4v"), .video)
        XCTAssertEqual(WallpaperType(fileExtension: "webm"), .video)
        XCTAssertEqual(WallpaperType(fileExtension: "avi"), .video)
        XCTAssertEqual(WallpaperType(fileExtension: "mkv"), .video)

        XCTAssertEqual(WallpaperType(fileExtension: "html"), .web)
        XCTAssertEqual(WallpaperType(fileExtension: "HTM"), .web)
        XCTAssertEqual(WallpaperType(fileExtension: "zip"), .web)
        XCTAssertEqual(WallpaperType(fileExtension: "lively"), .web)

        XCTAssertNil(WallpaperType(fileExtension: "txt"))
        XCTAssertNil(WallpaperType(fileExtension: "png"))
        XCTAssertNil(WallpaperType(fileExtension: "exe"))
    }

    func testWallpaperTypeURLInference() {
        XCTAssertEqual(WallpaperType(url: URL(fileURLWithPath: "/tmp/movie.mp4")), .video)
        XCTAssertEqual(WallpaperType(url: URL(fileURLWithPath: "/tmp/index.html")), .web)
        XCTAssertEqual(WallpaperType(url: URL(string: "https://example.com/stream")!), .url)
        XCTAssertEqual(WallpaperType(url: URL(string: "http://localhost:3000")!), .url)
        XCTAssertNil(WallpaperType(url: URL(string: "ftp://files.example.com")!))
    }

    // MARK: - 2. WallpaperItem Tests

    func testWallpaperItemDefaultValues() {
        let item = WallpaperItem(
            title: "Default Test",
            type: .video,
            pathOrURL: "/tmp/sample.mp4"
        )
        XCTAssertEqual(item.title, "Default Test")
        XCTAssertEqual(item.type, .video)
        XCTAssertEqual(item.pathOrURL, "/tmp/sample.mp4")
        XCTAssertEqual(item.volume, 1.0)
        XCTAssertTrue(item.isMuted)
        XCTAssertFalse(item.isInteractive)
        XCTAssertFalse(item.isBundled)
        XCTAssertNil(item.thumbnailPath)
        XCTAssertNil(item.itemDescription)
        XCTAssertNil(item.author)
        XCTAssertNil(item.license)
        XCTAssertNil(item.previewPath)
    }

    func testWallpaperItemVolumeClamping() {
        let negative = WallpaperItem(title: "Neg", type: .video, pathOrURL: "x", volume: -1.0)
        XCTAssertEqual(negative.volume, 0.0)

        let excessive = WallpaperItem(title: "Exc", type: .video, pathOrURL: "x", volume: 2.5)
        XCTAssertEqual(excessive.volume, 1.0)

        let normal = WallpaperItem(title: "Norm", type: .video, pathOrURL: "x", volume: 0.65)
        XCTAssertEqual(normal.volume, 0.65, accuracy: 0.001)
    }

    func testWallpaperItemURLResolution() {
        let local = WallpaperItem(title: "Local", type: .video, pathOrURL: "/Users/test/video.mp4")
        XCTAssertEqual(local.resolvedURL?.isFileURL, true)
        XCTAssertEqual(local.resolvedURL?.path, "/Users/test/video.mp4")

        let remote = WallpaperItem(title: "Remote", type: .url, pathOrURL: "https://example.com/matrix")
        XCTAssertEqual(remote.resolvedURL?.isFileURL, false)
        XCTAssertEqual(remote.resolvedURL?.absoluteString, "https://example.com/matrix")
    }

    func testWallpaperItemCodableRoundtrip() throws {
        let original = WallpaperItem(
            title: "Full Spec Item",
            type: .web,
            pathOrURL: "/Users/test/matrix/index.html",
            thumbnailPath: "/Users/test/matrix/thumb.jpg",
            volume: 0.8,
            isMuted: false,
            isInteractive: true,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            itemDescription: "Digital rain simulation",
            author: "Neo",
            license: "MIT",
            previewPath: "/Users/test/matrix/preview.gif",
            isBundled: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WallpaperItem.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.pathOrURL, original.pathOrURL)
        XCTAssertEqual(decoded.thumbnailPath, original.thumbnailPath)
        XCTAssertEqual(decoded.volume, original.volume, accuracy: 0.001)
        XCTAssertEqual(decoded.isMuted, original.isMuted)
        XCTAssertEqual(decoded.isInteractive, original.isInteractive)
        XCTAssertEqual(decoded.itemDescription, original.itemDescription)
        XCTAssertEqual(decoded.author, original.author)
        XCTAssertEqual(decoded.license, original.license)
        XCTAssertEqual(decoded.previewPath, original.previewPath)
        XCTAssertEqual(decoded.isBundled, original.isBundled)
    }

    func testWallpaperItemLegacyPayloadDecoding() throws {
        let legacyJSON = """
        {
            "title": "Legacy Item",
            "type": "video",
            "pathOrURL": "/path/video.mp4",
            "dateAdded": 1690000000,
            "desc": "Legacy description field"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let item = try decoder.decode(WallpaperItem.self, from: legacyJSON)

        XCTAssertEqual(item.title, "Legacy Item")
        XCTAssertEqual(item.type, .video)
        XCTAssertEqual(item.itemDescription, "Legacy description field")
        XCTAssertEqual(item.volume, 1.0)
        XCTAssertTrue(item.isMuted)
        XCTAssertFalse(item.isInteractive)
    }

    func testWallpaperItemHashableAndEquatable() {
        let uuid = UUID()
        let date = Date(timeIntervalSince1970: 1700000000)
        let item1 = WallpaperItem(id: uuid, title: "Item", type: .video, pathOrURL: "x", createdAt: date)
        let item2 = WallpaperItem(id: uuid, title: "Item", type: .video, pathOrURL: "x", createdAt: date)
        let item3 = WallpaperItem(title: "Item 3", type: .video, pathOrURL: "x", createdAt: date)

        XCTAssertEqual(item1, item2)
        XCTAssertNotEqual(item1, item3)
        XCTAssertEqual(item1.hashValue, item2.hashValue)
    }

    // MARK: - 3. LivelyInfo Tests

    func testLivelyInfoParsingFullIntType() throws {
        let json = """
        {
          "AppVersion": "1.0.0.0",
          "Title": "Matrix Digital Rain",
          "Thumbnail": "thumbnail.jpg",
          "Preview": "preview.gif",
          "Desc": "Procedural green matrix code rain with canvas",
          "Author": "Geeky",
          "License": "MIT",
          "Contact": "https://github.com",
          "Type": 0,
          "FileName": "index.html",
          "Arguments": null,
          "IsAbsolutePath": false
        }
        """.data(using: .utf8)!

        let info = try LivelyInfo.parse(data: json)
        XCTAssertEqual(info.appVersion, "1.0.0.0")
        XCTAssertEqual(info.title, "Matrix Digital Rain")
        XCTAssertEqual(info.thumbnail, "thumbnail.jpg")
        XCTAssertEqual(info.preview, "preview.gif")
        XCTAssertEqual(info.desc, "Procedural green matrix code rain with canvas")
        XCTAssertEqual(info.author, "Geeky")
        XCTAssertEqual(info.license, "MIT")
        XCTAssertEqual(info.type, .web)
        XCTAssertEqual(info.fileName, "index.html")
        XCTAssertEqual(info.isAbsolutePath, false)
        XCTAssertEqual(info.nativeWallpaperType, .web)

        let dir = URL(fileURLWithPath: "/Library/Wallpapers/Matrix")
        let item = info.makeWallpaperItem(directoryURL: dir)
        XCTAssertEqual(item.title, "Matrix Digital Rain")
        XCTAssertEqual(item.type, .web)
        XCTAssertEqual(item.pathOrURL, "/Library/Wallpapers/Matrix/index.html")
        XCTAssertEqual(item.thumbnailPath, "/Library/Wallpapers/Matrix/thumbnail.jpg")
        XCTAssertEqual(item.previewPath, "/Library/Wallpapers/Matrix/preview.gif")
        XCTAssertTrue(item.isInteractive)
    }

    func testLivelyInfoParsingStringTypeAndFallback() throws {
        let json = """
        {
          "Title": "Ocean Breeze",
          "Type": "video",
          "FileName": "ocean.mp4",
          "Description": "4K 60fps drone footage"
        }
        """.data(using: .utf8)!

        let info = try LivelyInfo.parse(data: json)
        XCTAssertEqual(info.title, "Ocean Breeze")
        XCTAssertEqual(info.type, .video)
        XCTAssertEqual(info.nativeWallpaperType, .video)
        XCTAssertEqual(info.desc, "4K 60fps drone footage")
        XCTAssertNil(info.author)
        XCTAssertNil(info.thumbnail)
    }

    func testLivelyInfoMalformedThrows() {
        let malformed = "{ this is not json }".data(using: .utf8)!
        XCTAssertThrowsError(try LivelyInfo.parse(data: malformed))
    }

    func testLivelyInfoDirectoryCandidateSearch() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LivelyDirTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sample = """
        { "Title": "Candidate", "Type": 2, "FileName": "video.mp4" }
        """
        let fileURL = tempDir.appendingPathComponent("LivelyInfo.json")
        try sample.write(to: fileURL, atomically: true, encoding: .utf8)

        let parsed = try LivelyInfo.parse(fromDirectory: tempDir)
        XCTAssertEqual(parsed.title, "Candidate")
        XCTAssertEqual(parsed.nativeWallpaperType, .video)
    }

    // MARK: - 4. WallpaperLibrary Tests

    func testWallpaperLibraryCRUDAndPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LibTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = WallpaperLibrary(storageDirectory: tempDir)
        let initial = try await library.loadWallpapers()
        XCTAssertEqual(initial.count, 0)

        // Add items
        let item1 = WallpaperItem(title: "Item 1", type: .video, pathOrURL: "/tmp/1.mp4")
        let item2 = WallpaperItem(title: "Item 2", type: .web, pathOrURL: "/tmp/2/index.html")
        try await library.addWallpaper(item1)
        try await library.addWallpaper(item2)

        let count = await library.getWallpapers().count
        XCTAssertEqual(count, 2)

        // Duplicate rejection
        do {
            try await library.addWallpaper(item1)
            XCTFail("Expected duplicate item failure")
        } catch WallpaperLibraryError.duplicateItem {
            // Success
        }

        // Update
        var updated1 = item1
        updated1.title = "Item 1 Renamed"
        try await library.updateWallpaper(updated1)
        let fetched = await library.getWallpaper(id: item1.id)
        XCTAssertEqual(fetched?.title, "Item 1 Renamed")

        // Reload from disk in a fresh instance
        let library2 = WallpaperLibrary(storageDirectory: tempDir)
        let reloadedItems = try await library2.loadWallpapers()
        XCTAssertEqual(reloadedItems.count, 2)
        XCTAssertEqual(reloadedItems.first?.title, "Item 1 Renamed")

        // Remove
        try await library.removeWallpaper(id: item1.id)
        let hasItem1 = await library.contains(id: item1.id)
        XCTAssertFalse(hasItem1)
        let countAfterRemove = await library.getWallpapers().count
        XCTAssertEqual(countAfterRemove, 1)

        // Reorder
        let item3 = WallpaperItem(title: "Item 3", type: .url, pathOrURL: "https://apple.com")
        try await library.addWallpaper(item3)
        try await library.moveWallpaper(fromIndex: 1, toIndex: 0)
        let reordered = await library.getWallpapers()
        XCTAssertEqual(reordered.first?.title, "Item 3")

        // Clear
        try await library.clear()
        let countAfterClear = await library.getWallpapers().count
        XCTAssertEqual(countAfterClear, 0)
    }

    func testWallpaperLibraryConcurrencyStress() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LibStress_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = WallpaperLibrary(storageDirectory: tempDir)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    let item = WallpaperItem(
                        title: "Concurrent Item \(i)",
                        type: .video,
                        pathOrURL: "/tmp/v_\(i).mp4"
                    )
                    try? await library.addWallpaper(item)
                }
            }
        }

        let total = await library.getWallpapers().count
        XCTAssertEqual(total, 30)

        // Fresh instance read to verify atomic write integrity
        let library2 = WallpaperLibrary(storageDirectory: tempDir)
        let reloaded = try await library2.loadWallpapers()
        XCTAssertEqual(reloaded.count, 30)
    }

    // MARK: - 5. AppState Tests

    @MainActor
    func testAppStateDefaultsAndMutations() {
        let appState = AppState()
        XCTAssertFalse(appState.isPaused)
        XCTAssertTrue(appState.isMuted)
        XCTAssertFalse(appState.isInteractionModeEnabled)
        XCTAssertEqual(appState.selectedNavigationTab, .library)
        XCTAssertNil(appState.activeWallpaper)

        let item1 = WallpaperItem(title: "Alpha Video", type: .video, pathOrURL: "/tmp/a.mp4")
        let item2 = WallpaperItem(title: "Beta Web", type: .web, pathOrURL: "/tmp/b/index.html")

        appState.addWallpaper(item1)
        XCTAssertEqual(appState.activeWallpaperId, item1.id)
        XCTAssertEqual(appState.activeWallpaper?.title, "Alpha Video")

        appState.addWallpaper(item2)
        XCTAssertEqual(appState.wallpapers.count, 2)
        // active remains item1
        XCTAssertEqual(appState.activeWallpaperId, item1.id)

        appState.setActiveWallpaper(id: item2.id)
        XCTAssertEqual(appState.activeWallpaperId, item2.id)

        appState.togglePause()
        XCTAssertTrue(appState.isPaused)

        appState.toggleMute()
        XCTAssertFalse(appState.isMuted)

        appState.toggleInteractionMode()
        XCTAssertTrue(appState.isInteractionModeEnabled)

        appState.removeWallpaper(id: item2.id)
        XCTAssertEqual(appState.wallpapers.count, 1)
        XCTAssertEqual(appState.activeWallpaperId, item1.id)
    }

    @MainActor
    func testAppStateFilteringAndSearch() {
        let item1 = WallpaperItem(title: "Aurora Loop", type: .video, pathOrURL: "/tmp/a.mp4")
        let item2 = WallpaperItem(title: "Matrix Digital Rain", type: .web, pathOrURL: "/tmp/b/index.html")
        let item3 = WallpaperItem(title: "Cyberpunk URL", type: .url, pathOrURL: "https://cyber.punk")

        let appState = AppState(wallpapers: [item1, item2, item3])
        XCTAssertEqual(appState.filteredWallpapers.count, 3)

        // Filter by text search
        appState.searchQuery = "rain"
        XCTAssertEqual(appState.filteredWallpapers.count, 1)
        XCTAssertEqual(appState.filteredWallpapers.first?.title, "Matrix Digital Rain")

        // Reset search, filter by type
        appState.searchQuery = ""
        appState.filterType = .video
        XCTAssertEqual(appState.filteredWallpapers.count, 1)
        XCTAssertEqual(appState.filteredWallpapers.first?.title, "Aurora Loop")

        // Search within filtered type
        appState.searchQuery = "aurora"
        XCTAssertEqual(appState.filteredWallpapers.count, 1)

        appState.searchQuery = "nonexistent"
        XCTAssertEqual(appState.filteredWallpapers.count, 0)
    }
}
