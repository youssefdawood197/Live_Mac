import SwiftUI

/// Settings and configuration panel for Flake ambient winter snowfall mode.
public struct FlakeSettingsView: View {
    @ObservedObject public var appState: AppState
    public var onClearSnow: (() -> Void)?

    public init(appState: AppState, onClearSnow: (() -> Void)? = nil) {
        self.appState = appState
        self.onClearSnow = onClearSnow
    }

    public var body: some View {
        Form {
            // MARK: - Master Toggle & Status
            Section(header: Text("Flake Ambient Mode").font(.headline)) {
                Toggle(isOn: $appState.flakeConfig.isEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Ambient Snowfall (Flake Mode)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Renders gentle, realistic falling snow that lands and accumulates on open window borders and the Dock.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, 3)
                }

                if appState.flakeConfig.isEnabled {
                    Picker("Rendering Layer", selection: $appState.flakeConfig.layerMode) {
                        ForEach(FlakeLayerMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)
                }
            }

            // MARK: - Weather & Wind Physics
            if appState.flakeConfig.isEnabled {
                Section(header: Text("Weather & Wind Physics").font(.headline)) {
                    Picker("Snowfall Intensity", selection: $appState.flakeConfig.intensity) {
                        ForEach(SnowfallIntensity.allCases, id: \.self) { intensity in
                            Text(intensity.rawValue).tag(intensity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)

                    HStack(alignment: .center, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wind Direction & Angle")
                                .font(.system(size: 12, weight: .medium))
                            Text("Drag the dial or click to steer wind vectors.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Slider(value: $appState.flakeConfig.windSpeed, in: 0.0...3.0, step: 0.2) {
                                Text("Wind Speed")
                            } minimumValueLabel: {
                                Text("Calm").font(.caption)
                            } maximumValueLabel: {
                                Text("Storm").font(.caption)
                            }
                            .padding(.top, 4)
                        }

                        Spacer()

                        WindCompassView(
                            windAngleDegrees: $appState.flakeConfig.windAngleDegrees,
                            windSpeed: $appState.flakeConfig.windSpeed
                        )
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Snow Accumulation & Drifts
                Section(header: Text("Physical Snowdrifts & Surfaces").font(.headline)) {
                    Toggle("Accumulate snow on window top borders", isOn: $appState.flakeConfig.accumulateOnWindows)
                    Toggle("Accumulate snow along the macOS Dock", isOn: $appState.flakeConfig.accumulateOnDock)
                    Toggle("Accumulate snow on display bottom edge", isOn: $appState.flakeConfig.accumulateOnScreenBottom)

                    Divider()

                    Toggle("Automated Snowplow Sweeper", isOn: $appState.flakeConfig.snowplowEnabled)

                    if appState.flakeConfig.snowplowEnabled {
                        Picker("Snowplow Vehicle", selection: $appState.flakeConfig.snowplowModel) {
                            ForEach(SnowplowModel.allCases, id: \.self) { model in
                                Label(model.rawValue, systemImage: model.iconName).tag(model)
                            }
                        }

                        if appState.flakeConfig.snowplowModel == .custom {
                            HStack {
                                if let customURL = appState.flakeConfig.customPlowImageURL {
                                    Text(customURL.lastPathComponent)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("No image selected")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Choose Image...") {
                                    let panel = NSOpenPanel()
                                    panel.allowedContentTypes = [.image, .png, .jpeg]
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    if panel.runModal() == .OK, let url = panel.url {
                                        appState.flakeConfig.customPlowImageURL = url
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // MARK: - Holiday Lights & Seasonal Toys
                Section(header: Text("Interactive Toys & Festivities").font(.headline)) {
                    Toggle("Festive Fairy Lights on Windows", isOn: $appState.flakeConfig.fairyLightsEnabled)

                    Picker("Active Cursor Tool", selection: $appState.flakeConfig.activeTool) {
                        ForEach(InteractiveTool.allCases, id: \.self) { tool in
                            Text(tool.rawValue).tag(tool)
                        }
                    }
                    .padding(.vertical, 2)

                    Toggle("Cozy Winter Ambient Audio", isOn: $appState.flakeConfig.ambientSoundEnabled)

                    if appState.flakeConfig.ambientSoundEnabled {
                        Slider(value: $appState.flakeConfig.soundVolume, in: 0.0...1.0) {
                            Text("Audio Volume")
                        }
                    }

                    HStack {
                        Spacer()
                        Button(action: { onClearSnow?() }) {
                            Label("Clear All Snow Now", systemImage: "paintbrush.fill")
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
