import XCTest
@testable import WallpaperCore

final class Milestone1ChallengeTests: XCTestCase {

    // MARK: - 1. WallpaperLibrary Concurrency & Persistence Stress

    func testLibraryHighConcurrencyMixedCRUDStress() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Challenge_LibStress_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = WallpaperLibrary(storageDirectory: tempDir)

        // Seed with 10 initial items
        var createdIDs: [UUID] = []
        for i in 0..<10 {
            let item = WallpaperItem(title: "Initial \(i)", type: .video, pathOrURL: "/tmp/init_\(i).mp4")
            createdIDs.append(item.id)
            try await library.addWallpaper(item)
        }
        let initialIDs = createdIDs

        let addedCount = 40

        // Execute concurrent tasks performing mixed operations
        await withTaskGroup(of: Void.self) { group in
            // Task type 1: Concurrent Additions
            for i in 0..<addedCount {
                group.addTask {
                    let item = WallpaperItem(
                        title: "Concurrent Add \(i)",
                        type: i % 2 == 0 ? .video : .web,
                        pathOrURL: "/tmp/add_\(i).mp4"
                    )
                    _ = try? await library.addWallpaper(item)
                }
            }

            // Task type 2: Concurrent Reads / Lookups
            for _ in 0..<20 {
                group.addTask {
                    _ = await library.getWallpapers()
                    _ = await library.getWallpapers(type: .video)
                    if let targetID = initialIDs.randomElement() {
                        _ = await library.getWallpaper(id: targetID)
                        _ = await library.contains(id: targetID)
                    }
                }
            }

            // Task type 3: Concurrent Updates
            for i in 0..<10 {
                group.addTask {
                    if let targetID = initialIDs.randomElement() {
                        let updated = WallpaperItem(
                            id: targetID,
                            title: "Updated Title \(i)",
                            type: .video,
                            pathOrURL: "/tmp/updated_\(i).mp4"
                        )
                        _ = try? await library.updateWallpaper(updated)
                    }
                }
            }

            // Task type 4: Concurrent Reordering
            for _ in 0..<10 {
                group.addTask {
                    _ = try? await library.moveWallpaper(fromIndex: 0, toIndex: 2)
                }
            }
        }

        // Verify library state consistency
        let finalItems = await library.getWallpapers()
        XCTAssertGreaterThanOrEqual(finalItems.count, 10)

        // Verify disk persistence file is valid and readable
        let diskLibrary = WallpaperLibrary(storageDirectory: tempDir)
        let reloaded = try await diskLibrary.loadWallpapers()
        XCTAssertEqual(reloaded.count, finalItems.count)
        XCTAssertEqual(reloaded.map { $0.id }, finalItems.map { $0.id })
    }

    func testLibraryCorruptedJSONRecovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Challenge_Corrupt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageFile = tempDir.appendingPathComponent("wallpapers.json")

        // Sub-scenario 1: Truncated JSON
        try "[{\"title\": \"Unfinished".write(to: storageFile, atomically: true, encoding: .utf8)
        let library1 = WallpaperLibrary(storageDirectory: tempDir)
        do {
            _ = try await library1.loadWallpapers()
            XCTFail("Expected loadWallpapers to throw on truncated JSON")
        } catch let WallpaperLibraryError.persistenceFailed(msg) {
            XCTAssertTrue(msg.contains("Failed to decode wallpapers"))
        }

        // Recovery: adding a new item and saving should overwrite corrupted file with valid JSON
        let recoveryItem = WallpaperItem(title: "Recovery Item", type: .video, pathOrURL: "/tmp/recover.mp4")
        try await library1.addWallpaper(recoveryItem)
        let itemsAfterRecovery = await library1.getWallpapers()
        XCTAssertEqual(itemsAfterRecovery.count, 1)

        // Verify disk now has valid JSON
        let libraryReloaded = WallpaperLibrary(storageDirectory: tempDir)
        let reloaded = try await libraryReloaded.loadWallpapers()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.title, "Recovery Item")

        // Sub-scenario 2: 0-byte empty file
        try "".write(to: storageFile, atomically: true, encoding: .utf8)
        let library2 = WallpaperLibrary(storageDirectory: tempDir)
        do {
            _ = try await library2.loadWallpapers()
            XCTFail("Expected loadWallpapers to throw on empty file")
        } catch WallpaperLibraryError.persistenceFailed {
            // Expected failure
        }

        // Sub-scenario 3: Random binary garbage
        let garbageBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF, 0x42])
        try garbageBytes.write(to: storageFile)
        let library3 = WallpaperLibrary(storageDirectory: tempDir)
        do {
            _ = try await library3.loadWallpapers()
            XCTFail("Expected loadWallpapers to throw on binary garbage")
        } catch WallpaperLibraryError.persistenceFailed {
            // Expected failure
        }
    }

    func testLibraryConcurrentDuplicatePrevention() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Challenge_DupStress_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = WallpaperLibrary(storageDirectory: tempDir)
        let fixedID = UUID()
        let item = WallpaperItem(id: fixedID, title: "Fixed ID Item", type: .video, pathOrURL: "/tmp/fixed.mp4")

        // Try adding the EXACT same item 50 times concurrently
        var successfulAdds = 0
        var duplicateErrors = 0

        await withTaskGroup(of: Result<Void, Error>.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    do {
                        try await library.addWallpaper(item)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success:
                    successfulAdds += 1
                case .failure(let error):
                    if case WallpaperLibraryError.duplicateItem = error {
                        duplicateErrors += 1
                    }
                }
            }
        }

        XCTAssertEqual(successfulAdds, 1, "Exactly one add should succeed")
        XCTAssertEqual(duplicateErrors, 49, "All 49 other concurrent adds should be rejected as duplicates")
        let total = await library.getWallpapers().count
        XCTAssertEqual(total, 1)
    }

    func testLibraryReorderBoundaryConditions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Challenge_Reorder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = WallpaperLibrary(storageDirectory: tempDir)
        let item1 = WallpaperItem(title: "A", type: .video, pathOrURL: "a")
        let item2 = WallpaperItem(title: "B", type: .video, pathOrURL: "b")
        let item3 = WallpaperItem(title: "C", type: .video, pathOrURL: "c")
        try await library.addWallpaper(item1)
        try await library.addWallpaper(item2)
        try await library.addWallpaper(item3)

        // Out of bounds fromIndex
        try await library.moveWallpaper(fromIndex: -1, toIndex: 1)
        try await library.moveWallpaper(fromIndex: 99, toIndex: 1)
        // Out of bounds toIndex
        try await library.moveWallpaper(fromIndex: 0, toIndex: -5)
        try await library.moveWallpaper(fromIndex: 0, toIndex: 100)

        // Verify ordering remained intact
        let items = await library.getWallpapers()
        XCTAssertEqual(items.map { $0.title }, ["A", "B", "C"])

        // Same index move
        try await library.moveWallpaper(fromIndex: 1, toIndex: 1)
        let itemsSame = await library.getWallpapers()
        XCTAssertEqual(itemsSame.map { $0.title }, ["A", "B", "C"])
    }

    // MARK: - 2. LivelyInfo Stress & Edge Cases

    func testLivelyInfoPolymorphicTypeVariations() throws {
        // Test all integer cases 0..8
        for code in 0...8 {
            let json = """
            { "Title": "Code \(code)", "Type": \(code), "FileName": "asset_\(code).dat" }
            """.data(using: .utf8)!
            let info = try LivelyInfo.parse(data: json)
            XCTAssertEqual(info.type.rawValue, code)
        }

        // Test string cases
        let stringTypeMap: [String: LivelyWallpaperType] = [
            "web": .web,
            "0": .web,
            "webstream": .webstream,
            "1": .webstream,
            "video": .video,
            "2": .video,
            "gif": .gif,
            "3": .gif,
            "unity": .unity,
            "4": .unity,
            "godot": .godot,
            "5": .godot,
            "videostream": .videostream,
            "6": .videostream,
            "app": .app,
            "7": .app,
            "picture": .picture,
            "8": .picture,
            "unknown_str": .unknown,
            "VIDEO": .video,
            "Web": .web
        ]

        for (str, expected) in stringTypeMap {
            let json = """
            { "Title": "Str \(str)", "Type": "\(str)", "FileName": "asset.dat" }
            """.data(using: .utf8)!
            let info = try LivelyInfo.parse(data: json)
            XCTAssertEqual(info.type, expected, "Mismatch for string type: \(str)")
        }

        // Unknown integer type
        let unknownIntJSON = """
        { "Title": "Unknown Int", "Type": 999, "FileName": "asset.dat" }
        """.data(using: .utf8)!
        let unknownInfo = try LivelyInfo.parse(data: unknownIntJSON)
        XCTAssertEqual(unknownInfo.type, .unknown)
    }

    func testLivelyInfoDescriptionFallbackPrecedence() throws {
        // Both Desc and Description present: Desc takes precedence
        let bothJSON = """
        {
            "Title": "Precedence Test",
            "Type": 2,
            "FileName": "video.mp4",
            "Desc": "Primary Desc",
            "Description": "Secondary Description"
        }
        """.data(using: .utf8)!
        let bothInfo = try LivelyInfo.parse(data: bothJSON)
        XCTAssertEqual(bothInfo.desc, "Primary Desc")

        // Only Description present
        let descriptionOnlyJSON = """
        {
            "Title": "Desc Only Test",
            "Type": 2,
            "FileName": "video.mp4",
            "Description": "Secondary Description"
        }
        """.data(using: .utf8)!
        let descInfo = try LivelyInfo.parse(data: descriptionOnlyJSON)
        XCTAssertEqual(descInfo.desc, "Secondary Description")

        // Neither present
        let neitherJSON = """
        {
            "Title": "No Desc Test",
            "Type": 2,
            "FileName": "video.mp4"
        }
        """.data(using: .utf8)!
        let neitherInfo = try LivelyInfo.parse(data: neitherJSON)
        XCTAssertNil(neitherInfo.desc)
    }

    func testLivelyInfoMalformedAndCorruptedPayloads() {
        let malformedCases: [(name: String, json: String)] = [
            ("Unclosed brace", "{\"Title\": \"Test\""),
            ("Missing colon", "{\"Title\" \"Test\", \"FileName\": \"a.mp4\"}"),
            ("Unquoted identifier", "{Title: \"Test\", FileName: \"a.mp4\"}"),
            ("Unclosed quotes", "{\"Title\": \"Test, \"FileName\": \"a.mp4\"}"),
            ("Missing required Title", "{\"FileName\": \"a.mp4\", \"Type\": 2}"),
            ("Missing required FileName", "{\"Title\": \"Test\", \"Type\": 2}"),
            ("Title wrong type (integer)", "{\"Title\": 12345, \"FileName\": \"a.mp4\"}"),
            ("FileName wrong type (array)", "{\"Title\": \"Test\", \"FileName\": [\"a.mp4\"]}"),
            ("Empty JSON object", "{}"),
            ("Empty string", "")
        ]

        for testCase in malformedCases {
            let data = testCase.json.data(using: .utf8)!
            XCTAssertThrowsError(try LivelyInfo.parse(data: data), "Should throw for: \(testCase.name)")
        }
    }

    func testLivelyInfoUnicodeAndWhitespaceStress() throws {
        let unicodeTitle = "🌸 ライブ壁紙 💖 (Matrix 4K) — 日本語 / 한국어 / 👨‍💻"
        let longDesc = String(repeating: "Large description sentence. ", count: 500) // ~15 KB string
        let json = """
        {
            "Title": "\(unicodeTitle)",
            "Type": 0,
            "FileName": "index.html",
            "Desc": "\(longDesc)",
            "Author": "🎨 Artist & Coder",
            "License": "CC-BY-SA 4.0"
        }
        """.data(using: .utf8)!

        let info = try LivelyInfo.parse(data: json)
        XCTAssertEqual(info.title, unicodeTitle)
        XCTAssertEqual(info.author, "🎨 Artist & Coder")
        XCTAssertEqual(info.desc, longDesc)

        let item = info.makeWallpaperItem(directoryURL: URL(fileURLWithPath: "/Library/Wallpapers/Cherry"))
        XCTAssertEqual(item.title, unicodeTitle)
        XCTAssertEqual(item.author, "🎨 Artist & Coder")
        XCTAssertEqual(item.itemDescription, longDesc)
    }

    func testLivelyInfoWindowsPathAndSeparatorHandling() throws {
        // Windows absolute path
        let absWindows = LivelyInfo(
            title: "Windows Abs",
            type: .video,
            fileName: "C:\\Wallpapers\\loop.mp4",
            isAbsolutePath: true
        )
        let itemAbs = absWindows.makeWallpaperItem(directoryURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(itemAbs.pathOrURL, "C:\\Wallpapers\\loop.mp4")

        // Relative path resolution
        let relWindows = LivelyInfo(
            title: "Relative Asset",
            type: .video,
            fileName: "loop.mp4",
            isAbsolutePath: false
        )
        let itemRel = relWindows.makeWallpaperItem(directoryURL: URL(fileURLWithPath: "/Library/Lively/Rain"))
        XCTAssertEqual(itemRel.pathOrURL, "/Library/Lively/Rain/loop.mp4")
    }

    // MARK: - 3. WallpaperItem Boundary Conditions & Floating Point Clamping

    func testWallpaperItemVolumeBoundaryAndClamping() {
        // Upper boundaries
        let maxValid = WallpaperItem(title: "Max", type: .video, pathOrURL: "x", volume: 1.0)
        XCTAssertEqual(maxValid.volume, 1.0)

        let overMax = WallpaperItem(title: "Over", type: .video, pathOrURL: "x", volume: 1.0001)
        XCTAssertEqual(overMax.volume, 1.0)

        let extremeMax = WallpaperItem(title: "Extreme", type: .video, pathOrURL: "x", volume: Float.greatestFiniteMagnitude)
        XCTAssertEqual(extremeMax.volume, 1.0)

        let posInf = WallpaperItem(title: "PosInf", type: .video, pathOrURL: "x", volume: Float.infinity)
        XCTAssertEqual(posInf.volume, 1.0)

        // Lower boundaries
        let minValid = WallpaperItem(title: "Min", type: .video, pathOrURL: "x", volume: 0.0)
        XCTAssertEqual(minValid.volume, 0.0)

        let underMin = WallpaperItem(title: "Under", type: .video, pathOrURL: "x", volume: -0.0001)
        XCTAssertEqual(underMin.volume, 0.0)

        let extremeMin = WallpaperItem(title: "ExtremeMin", type: .video, pathOrURL: "x", volume: -Float.greatestFiniteMagnitude)
        XCTAssertEqual(extremeMin.volume, 0.0)

        let negInf = WallpaperItem(title: "NegInf", type: .video, pathOrURL: "x", volume: -Float.infinity)
        XCTAssertEqual(negInf.volume, 0.0)
    }

    func testWallpaperItemNaNVolumeBehavior() {
        // Empirically observe how WallpaperItem handles Float.nan
        let nanItem = WallpaperItem(title: "NaN Test", type: .video, pathOrURL: "x", volume: Float.nan)

        // Document empirical behavior: In IEEE 754 Swift max(0.0, min(1.0, Float.nan))
        // Observe whether nanItem.volume is NaN or clamped to a valid float
        let isNaN = nanItem.volume.isNaN
        // We test encoding roundtrip: if it is NaN, JSONEncoder will throw
        let encoder = JSONEncoder()
        if isNaN {
            // Documenting empirical proof: NaN volume causes JSON encoding failure
            XCTAssertThrowsError(try encoder.encode(nanItem), "NaN volume cannot be serialized to JSON")
        } else {
            XCTAssertNoThrow(try encoder.encode(nanItem))
        }
    }

    func testWallpaperItemURLResolutionBoundaries() {
        // Empty path: URL(fileURLWithPath: "") resolves to current directory, so fileExists is true
        let emptyItem = WallpaperItem(title: "Empty", type: .video, pathOrURL: "")
        XCTAssertNotNil(emptyItem.resolvedURL)
        XCTAssertEqual(emptyItem.resolvedURL?.path, FileManager.default.currentDirectoryPath)
        // EMPIRICAL DEFECT DEMONSTRATION: fileExists returns true for empty path because path resolves to "."
        XCTAssertTrue(emptyItem.fileExists, "Empirical defect: empty path resolves to current working directory, returning true for fileExists")

        // Non-existent path correctly returns false
        let nonExistentItem = WallpaperItem(title: "NonExistent", type: .video, pathOrURL: "/invalid/path/to/missing_video.mp4")
        XCTAssertFalse(nonExistentItem.fileExists)

        // Standard HTTP/HTTPS
        let httpItem = WallpaperItem(title: "HTTP", type: .url, pathOrURL: "http://example.com/stream.m3u8")
        XCTAssertEqual(httpItem.resolvedURL?.scheme, "http")
        XCTAssertTrue(httpItem.fileExists) // type == .url returns true

        // File URL with spaces
        let spaceItem = WallpaperItem(title: "Space", type: .video, pathOrURL: "/Users/test/My Wallpapers/video 1.mp4")
        XCTAssertEqual(spaceItem.resolvedURL?.isFileURL, true)
        XCTAssertEqual(spaceItem.resolvedURL?.path, "/Users/test/My Wallpapers/video 1.mp4")

        // Thumbnail resolution
        let nilThumb = WallpaperItem(title: "Nil Thumb", type: .video, pathOrURL: "x", thumbnailPath: nil)
        XCTAssertNil(nilThumb.resolvedThumbnailURL)

        let emptyThumb = WallpaperItem(title: "Empty Thumb", type: .video, pathOrURL: "x", thumbnailPath: "")
        XCTAssertNil(emptyThumb.resolvedThumbnailURL)

        let remoteThumb = WallpaperItem(title: "Remote Thumb", type: .video, pathOrURL: "x", thumbnailPath: "https://example.com/t.png")
        XCTAssertEqual(remoteThumb.resolvedThumbnailURL?.absoluteString, "https://example.com/t.png")

        let localThumb = WallpaperItem(title: "Local Thumb", type: .video, pathOrURL: "x", thumbnailPath: "/tmp/thumb.jpg")
        XCTAssertEqual(localThumb.resolvedThumbnailURL?.isFileURL, true)
    }

    func testWallpaperItemDirectMutationBypassesClamping() throws {
        var item = WallpaperItem(title: "Mutate", type: .video, pathOrURL: "/tmp/v.mp4", volume: 0.5)
        XCTAssertEqual(item.volume, 0.5)

        // EMPIRICAL OBSERVATION: Direct mutation bypasses init clamping
        item.volume = 5.0
        XCTAssertEqual(item.volume, 5.0, "Direct assignment to volume allows unclamped values")

        // However, encoding and decoding enforces clamping on reload
        let encoded = try JSONEncoder().encode(item)
        let reloaded = try JSONDecoder().decode(WallpaperItem.self, from: encoded)
        XCTAssertEqual(reloaded.volume, 1.0, "Decoder clamps excessive volume to 1.0")
    }

    func testLivelyInfoWindowsBackslashPathHandling() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Challenge_WindowsBackslash_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetVideo = subDir.appendingPathComponent("video.mp4")
        try "dummy video content".write(to: targetVideo, atomically: true, encoding: .utf8)

        // Windows-style backslash relative path
        let info = LivelyInfo(
            title: "Backslash Test",
            type: .video,
            fileName: "sub\\video.mp4"
        )
        let item = info.makeWallpaperItem(directoryURL: tempDir)

        // On POSIX (macOS), tempDir.appendingPathComponent("sub\\video.mp4") treats backslash as literal character
        // So item.pathOrURL is .../sub\video.mp4, NOT .../sub/video.mp4
        let posixPath = tempDir.appendingPathComponent("sub/video.mp4").path
        let isPOSIXMatch = (item.pathOrURL == posixPath)
        XCTAssertFalse(isPOSIXMatch, "makeWallpaperItem does not normalize Windows backslashes to forward slashes")
        // Consequently, fileExists fails on POSIX for backslash paths
        XCTAssertFalse(item.fileExists, "POSIX fileExists returns false because 'sub\\video.mp4' is treated as a single non-existent filename")
    }

    func testLibraryMassiveScalePersistenceStress() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Challenge_Massive_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let library = WallpaperLibrary(storageDirectory: tempDir)
        let scale = 500

        // Add 500 items in batch (without saving every single item to measure batch save performance)
        for i in 0..<scale {
            let item = WallpaperItem(
                title: "Scale Item \(i)",
                type: i % 3 == 0 ? .video : (i % 3 == 1 ? .web : .url),
                pathOrURL: "/tmp/scale_\(i).mp4",
                volume: Float(i % 100) / 100.0,
                isMuted: i % 2 == 0
            )
            try await library.addWallpaper(item, saveImmediately: false)
        }
        try await library.save()

        let inMemoryCount = await library.getWallpapers().count
        XCTAssertEqual(inMemoryCount, scale)

        // Verify disk reload integrity
        let reloadLibrary = WallpaperLibrary(storageDirectory: tempDir)
        let reloaded = try await reloadLibrary.loadWallpapers()
        XCTAssertEqual(reloaded.count, scale)
        XCTAssertEqual(reloaded[250].title, "Scale Item 250")
    }

    func testWallpaperItemDecoderResilienceToCorruptedVolumes() throws {
        // Volume > 1 in JSON
        let overVolumeJSON = """
        { "title": "Over", "type": "video", "pathOrURL": "x", "volume": 5.5 }
        """.data(using: .utf8)!
        let overItem = try JSONDecoder().decode(WallpaperItem.self, from: overVolumeJSON)
        XCTAssertEqual(overItem.volume, 1.0)

        // Volume < 0 in JSON
        let underVolumeJSON = """
        { "title": "Under", "type": "video", "pathOrURL": "x", "volume": -10.0 }
        """.data(using: .utf8)!
        let underItem = try JSONDecoder().decode(WallpaperItem.self, from: underVolumeJSON)
        XCTAssertEqual(underItem.volume, 0.0)

        // Missing volume in JSON: defaults to 1.0
        let missingVolumeJSON = """
        { "title": "Missing", "type": "video", "pathOrURL": "x" }
        """.data(using: .utf8)!
        let missingItem = try JSONDecoder().decode(WallpaperItem.self, from: missingVolumeJSON)
        XCTAssertEqual(missingItem.volume, 1.0)
    }
}
