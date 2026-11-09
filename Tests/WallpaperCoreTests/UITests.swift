import XCTest
import Combine
@testable import WallpaperCore

@MainActor
final class UITests: XCTestCase {

    private var appState: AppState!
    private var mockScreenProvider: MockScreenProvider!
    private var windowManager: DesktopWindowManager!
    private var statusItemController: StatusItemController!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        mockScreenProvider = MockScreenProvider(screens: [
            DisplayDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ])
        windowManager = DesktopWindowManager(screenProvider: mockScreenProvider)
        statusItemController = StatusItemController(
            appState: appState,
            windowManager: windowManager,
            attachToStatusBar: false // Headless testing
        )
    }

    @MainActor
    override func tearDown() async throws {
        statusItemController.terminate()
        windowManager.terminate()
        statusItemController = nil
        windowManager = nil
        mockScreenProvider = nil
        appState = nil
        try await super.tearDown()
    }

    // MARK: - Status Item Properties & Initial State

    func testStatusItemInitialProperties() {
        XCTAssertEqual(statusItemController.title, "Lively Wallpaper")
        XCTAssertEqual(statusItemController.iconName, "sparkles.tv")
        XCTAssertEqual(statusItemController.playPauseTitle, "Pause")
        XCTAssertEqual(statusItemController.muteTitle, "Mute")
        XCTAssertFalse(statusItemController.isInteractiveChecked)
        XCTAssertFalse(statusItemController.isTerminated)
        XCTAssertFalse(statusItemController.isManagerOpen)
    }

    // MARK: - State Synchronization

    func testPlayPauseTitleUpdatesOnStateChange() {
        XCTAssertEqual(statusItemController.playPauseTitle, "Pause")

        statusItemController.update(
            isPaused: true,
            isMuted: false,
            isInteractive: false,
            wallpapers: []
        )
        XCTAssertEqual(statusItemController.playPauseTitle, "Resume")

        statusItemController.update(
            isPaused: false,
            isMuted: false,
            isInteractive: false,
            wallpapers: []
        )
        XCTAssertEqual(statusItemController.playPauseTitle, "Pause")
    }

    func testMuteTitleUpdatesOnStateChange() {
        XCTAssertEqual(statusItemController.muteTitle, "Mute")

        statusItemController.update(
            isPaused: false,
            isMuted: true,
            isInteractive: false,
            wallpapers: []
        )
        XCTAssertEqual(statusItemController.muteTitle, "Unmute")

        statusItemController.update(
            isPaused: false,
            isMuted: false,
            isInteractive: false,
            wallpapers: []
        )
        XCTAssertEqual(statusItemController.muteTitle, "Mute")
    }

    func testInteractiveModeUpdates() {
        XCTAssertFalse(statusItemController.isInteractiveChecked)

        statusItemController.update(
            isPaused: false,
            isMuted: false,
            isInteractive: true,
            wallpapers: []
        )
        XCTAssertTrue(statusItemController.isInteractiveChecked)

        statusItemController.update(
            isPaused: false,
            isMuted: false,
            isInteractive: false,
            wallpapers: []
        )
        XCTAssertFalse(statusItemController.isInteractiveChecked)
    }

    func testQuickPickerWallpapersList() {
        let sample1 = WallpaperItem(
            title: "Ocean Wave",
            type: .video,
            sourceURL: URL(fileURLWithPath: "/tmp/ocean.mp4")
        )
        let sample2 = WallpaperItem(
            title: "Cyberpunk City",
            type: .url,
            sourceURL: URL(string: "https://example.com/cyberpunk")!
        )

        statusItemController.update(
            isPaused: false,
            isMuted: false,
            isInteractive: false,
            wallpapers: [sample1, sample2]
        )

        XCTAssertEqual(statusItemController.quickPickerWallpapers.count, 2)
        XCTAssertEqual(statusItemController.quickPickerWallpapers[0].title, "Ocean Wave")
        XCTAssertEqual(statusItemController.quickPickerWallpapers[1].title, "Cyberpunk City")
    }

    // MARK: - AppState Filtering & Search Tests

    func testAppStateSearchAndTypeFilter() {
        let v1 = WallpaperItem(title: "Deep Space Video", type: .video, sourceURL: URL(fileURLWithPath: "/tmp/space.mp4"))
        let w1 = WallpaperItem(title: "Fluid Matrix Web", type: .web, sourceURL: URL(fileURLWithPath: "/tmp/matrix/index.html"))
        let u1 = WallpaperItem(title: "Cyberpunk Live URL", type: .url, sourceURL: URL(string: "https://example.com/live")!)

        appState.setWallpapers([v1, w1, u1])
        XCTAssertEqual(appState.filteredWallpapers.count, 3)

        // Test search
        appState.searchQuery = "space"
        XCTAssertEqual(appState.filteredWallpapers.count, 1)
        XCTAssertEqual(appState.filteredWallpapers.first?.title, "Deep Space Video")

        // Test type filter
        appState.searchQuery = ""
        appState.filterType = .web
        XCTAssertEqual(appState.filteredWallpapers.count, 1)
        XCTAssertEqual(appState.filteredWallpapers.first?.title, "Fluid Matrix Web")

        appState.filterType = .url
        XCTAssertEqual(appState.filteredWallpapers.count, 1)
        XCTAssertEqual(appState.filteredWallpapers.first?.title, "Cyberpunk Live URL")

        appState.filterType = nil
        XCTAssertEqual(appState.filteredWallpapers.count, 3)
    }

    // MARK: - Manager Callbacks

    func testOpenManagerCallback() {
        var opened = false
        statusItemController.onOpenManager = {
            opened = true
        }

        // Trigger open manager
        statusItemController.isManagerOpen = true
        statusItemController.onOpenManager?()
        XCTAssertTrue(opened)
        XCTAssertTrue(statusItemController.isManagerOpen)
    }

    func testTerminationLifecycle() {
        XCTAssertFalse(statusItemController.isTerminated)
        statusItemController.terminate()
        XCTAssertTrue(statusItemController.isTerminated)
    }
}
