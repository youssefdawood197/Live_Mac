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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pause when apps are full-screen")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Automatically suspends video and web animation when gaming or running full-screen apps.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
                .onChange(of: appState.pauseOnFullscreen) { _, _ in
                    updatePowerSettings()
                }

                Toggle(isOn: $appState.pauseOnBattery) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pause on battery power")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Halts live rendering when running on MacBook battery to maximize battery life.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
                .onChange(of: appState.pauseOnBattery) { _, _ in
                    updatePowerSettings()
                }

                Toggle(isOn: $appState.pauseOnDisplaySleep) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pause on display sleep and screen lock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Stops rendering when displays sleep or the lock screen activates.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
                .onChange(of: appState.pauseOnDisplaySleep) { _, _ in
                    updatePowerSettings()
                }
            }

            // MARK: - Audio & Interaction
            Section(header: Text("Audio & Interaction").font(.headline)) {
                Toggle(isOn: $appState.isMuted) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mute wallpaper audio by default")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Keeps live video wallpapers silent when set as desktop background.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }

                Toggle(isOn: $appState.isInteractionModeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Interactive desktop mode")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Elevates wallpaper to receive mouse clicks directly for HTML5/WebGL shaders.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
            }

            // MARK: - About & Architecture
            Section(header: Text("About Lively Wallpaper for Mac").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Lively Wallpaper for macOS")
                                .font(.headline)
                            Text("Version 1.0.0 (Native Apple Silicon)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    Text("A pure native macOS replica of Lively Wallpaper built with Swift 6, SwiftUI, and AppKit. Features hardware-accelerated AVFoundation video looping, WebKit shader engine, and zero-TCC fullscreen auto-pause.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
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
