import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Modal sheet enabling users to import local video files, HTML5 canvas/WebGL folders, or live URLs.
public struct AddWallpaperSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let onAdd: (WallpaperItem) -> Void
    public var assetManager: AssetManager

    @State private var selectedTab: Int = 0 // 0: Video, 1: Web Folder, 2: Remote URL
    @State private var remoteURLText: String = ""
    @State private var customTitle: String = ""
    @State private var customAuthor: String = ""
    @State private var customDescription: String = ""
    @State private var errorMessage: String? = nil
    @State private var isProcessing: Bool = false

    public init(
        assetManager: AssetManager = AssetManager(),
        onAdd: @escaping (WallpaperItem) -> Void
    ) {
        self.assetManager = assetManager
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Live Wallpaper")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Source Selector Tabs
            Picker("Source Type", selection: $selectedTab) {
                Text("Video File").tag(0)
                Text("HTML5 / WebGL Folder").tag(1)
                Text("Remote URL").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab Content
            VStack(spacing: 16) {
                switch selectedTab {
                case 0:
                    videoImportView
                case 1:
                    webFolderImportView
                case 2:
                    urlImportView
                default:
                    EmptyView()
                }

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }

                if isProcessing {
                    ProgressView("Validating and importing...")
                        .progressViewStyle(.circular)
                        .padding()
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                if selectedTab == 2 {
                    Button("Add URL Wallpaper") {
                        submitURL()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                }
            }
            .padding()
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 440, idealHeight: 480)
    }

    // MARK: - Video Import View

    private var videoImportView: some View {
        VStack(spacing: 16) {
            Text("Select an MP4 or MOV video to loop on your desktop.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: selectVideoFile) {
                Label("Browse Video File...", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Supported Formats: MP4, MOV, M4V (H.264 / HEVC)")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    // MARK: - Web Folder Import View

    private var webFolderImportView: some View {
        VStack(spacing: 16) {
            Text("Select a folder containing an index.html file with HTML5, CSS, Canvas, or WebGL animations.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: selectWebDirectory) {
                Label("Browse HTML5 Folder...", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Folder must contain an entry point named index.html")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    // MARK: - Remote URL Import View

    private var urlImportView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Live Web URL:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("https://example.com/interactive-wallpaper", text: $remoteURLText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title (Optional):")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("My Web Wallpaper", text: $customTitle)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Renders any website, WebGL shader (Shadertoy), or live dashboard directly onto your desktop.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    // MARK: - Import Handlers

    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.mpeg4Movie, UTType.quickTimeMovie, UTType.movie]
        panel.prompt = "Choose Video"

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let meta = try await assetManager.validateVideo(at: fileURL)
                let title = fileURL.deletingPathExtension().lastPathComponent
                let itemId = UUID()
                
                // Extract video frame thumbnail immediately
                let thumbDir = ThumbnailManager.shared.thumbnailsDirectory
                let thumbURL = thumbDir.appendingPathComponent("\(itemId.uuidString).jpg")
                let generatedThumbURL = try? await assetManager.generateThumbnail(for: fileURL, at: thumbURL)

                let item = WallpaperItem(
                    id: itemId,
                    title: title,
                    type: .video,
                    sourceURL: fileURL,
                    thumbnailURL: generatedThumbURL,
                    duration: meta.durationSeconds
                )
                await MainActor.run {
                    self.onAdd(item)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to import video: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    private func selectWebDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose HTML5 Folder"

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        isProcessing = true
        errorMessage = nil

        do {
            let meta = try assetManager.validateWebDirectory(at: folderURL)
            let title = meta.title ?? folderURL.lastPathComponent

            // Check for existing thumbnail file in web directory
            var thumbURL: URL? = nil
            for name in ["thumbnail.jpg", "thumbnail.png", "preview.jpg", "preview.png"] {
                let candidate = folderURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    thumbURL = candidate
                    break
                }
            }

            let item = WallpaperItem(
                title: title,
                type: .web,
                sourceURL: folderURL,
                thumbnailURL: thumbURL
            )
            onAdd(item)
            dismiss()
        } catch {
            errorMessage = "Failed to import web folder: \(error.localizedDescription)"
            isProcessing = false
        }
    }

    private func submitURL() {
        let trimmed = remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            errorMessage = "Please enter a valid HTTP or HTTPS URL."
            return
        }

        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (url.host ?? "Web Wallpaper")
            : customTitle

        let item = WallpaperItem(
            title: title,
            type: .url,
            sourceURL: url
        )
        onAdd(item)
        dismiss()
    }
}
