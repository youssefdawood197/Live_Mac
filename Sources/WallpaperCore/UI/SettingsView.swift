import SwiftUI

/// Settings and preferences view for Lively Wallpaper.
public struct SettingsView: View {
    @ObservedObject public var appState: AppState
    public weak var powerManager: PowerManagerProtocol?

    public init(appState: AppState, powerManager: PowerManagerProtocol? = nil) {
        self.appState = appState
        self.powerManager = powerManager
    }

    public var body: some View {
        Form {
            // MARK: - Power & Energy Saving
            Section(header: Text("Energy & Performance").font(.headline)) {
                Toggle(isOn: $appState.pauseOnFullscreen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause when apps are full-screen")
                            .fontWeight(.medium)
                        Text("Automatically suspends video and web animation when gaming or running full-screen apps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.pauseOnFullscreen) { _, _ in
                    updatePowerSettings()
                }

                Toggle(isOn: $appState.pauseOnBattery) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause on battery power")
                            .fontWeight(.medium)
                        Text("Halts live rendering when running on MacBook battery to maximize battery life.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.pauseOnBattery) { _, _ in
                    updatePowerSettings()
                }

                Toggle(isOn: $appState.pauseOnDisplaySleep) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause on display sleep and screen lock")
                            .fontWeight(.medium)
                        Text("Stops rendering when displays sleep or the lock screen activates.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.pauseOnDisplaySleep) { _, _ in
                    updatePowerSettings()
                }
            }

            // MARK: - Audio & Interaction
            Section(header: Text("Audio & Interaction").font(.headline)) {
                Toggle(isOn: $appState.isMuted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mute wallpaper audio by default")
                            .fontWeight(.medium)
                        Text("Keeps live video wallpapers silent when set as desktop background.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $appState.isInteractionModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive desktop mode")
                            .fontWeight(.medium)
                        Text("Elevates wallpaper to receive mouse clicks directly for HTML5/WebGL shaders.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - About & Architecture
            Section(header: Text("About Lively Wallpaper for Mac").font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "sparkles.tv")
                            .font(.title)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lively Wallpaper for macOS")
                                .font(.headline)
                            Text("Version 1.0.0 (Native Apple Silicon)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Text("A pure native macOS replica of Lively Wallpaper built with Swift 6, SwiftUI, and AppKit. Features hardware-accelerated AVFoundation video looping, WebKit shader engine, and zero-TCC fullscreen auto-pause.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updatePowerSettings() {
        guard var settings = powerManager?.settings else { return }
        settings.pauseOnFullscreen = appState.pauseOnFullscreen
        settings.pauseOnBattery = appState.pauseOnBattery
        settings.pauseOnDisplaySleep = appState.pauseOnDisplaySleep
        powerManager?.settings = settings
    }
}
