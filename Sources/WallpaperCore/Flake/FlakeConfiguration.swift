import Foundation
import CoreGraphics

/// Defines the intensity and density of snowfall in Flake Mode.
public enum SnowfallIntensity: String, CaseIterable, Codable, Sendable {
    case light = "Light"       // Gentle, sparse snowfall (150 particles, 20 bps, 7.5s lifetime)
    case steady = "Steady"     // Balanced ambient snowfall (400 particles, 50 bps, 8.0s lifetime)
    case blizzard = "Blizzard" // Dense winter snowstorm (900 particles, 120 bps, 7.5s lifetime)

    public var maxParticles: Int {
        switch self {
        case .light: return 150
        case .steady: return 400
        case .blizzard: return 900
        }
    }

    public var birthRate: CGFloat {
        switch self {
        case .light: return 20.0
        case .steady: return 50.0
        case .blizzard: return 120.0
        }
    }

    public var fallSpeedMultiplier: CGFloat {
        switch self {
        case .light: return 0.8
        case .steady: return 1.0
        case .blizzard: return 1.4
        }
    }

    /// Particle lifetime in seconds satisfying budget: maxParticles = birthRate * lifetime.
    public var particleLifetime: CGFloat {
        CGFloat(maxParticles) / birthRate
    }
}

/// Selectable clearing vehicle or character for the automated snowplow.
public enum SnowplowModel: String, CaseIterable, Codable, Sendable {
    case classicTractor = "Classic Tractor"
    case vintageTractor = "Vintage Tractor"
    case snowmobile = "Snowmobile"
    case penguin = "Penguin with Shovel"
    case custom = "Custom Image"

    public var iconName: String {
        switch self {
        case .classicTractor: return "car.side.fill"
        case .vintageTractor: return "bus.fill"
        case .snowmobile: return "figure.skiing.downhill"
        case .penguin: return "bird.fill"
        case .custom: return "photo.fill"
        }
    }
}

/// Rendering layer target for Flake Mode.
public enum FlakeLayerMode: String, CaseIterable, Codable, Sendable {
    /// Transparent floating overlay above open application windows with full click-through.
    case overlay = "Screen Overlay"
    /// Behind application windows on the desktop level.
    case desktop = "Desktop Background"
}

/// Interactive desktop toys and clearing tools.
public enum InteractiveTool: String, CaseIterable, Codable, Sendable {
    case none = "None (Click-Through)"
    case mitten = "Mitten (Brush)"
    case shovel = "Shovel (Scoop)"
    case snowman = "Snowman Builder"
}

/// Full configuration state for Flake Mode.
public struct FlakeConfiguration: Codable, Equatable, Sendable {
    /// Master toggle for Flake Mode ambient snow effect.
    public var isEnabled: Bool = false

    /// Target layer for snow rendering (overlay vs. desktop).
    public var layerMode: FlakeLayerMode = .overlay

    /// Preset snowfall density and particle rate.
    public var intensity: SnowfallIntensity = .steady

    /// Directional wind angle in degrees (0° = East, 90° = Straight Down / South, 180° = West, 270° = Up).
    public var windAngleDegrees: Double = 90.0

    /// Wind velocity multiplier (0.0 = calm, 3.0 = strong gust, or px/s² up to 600).
    public var windSpeed: Double = 1.0

    /// Whether snow lands and physically piles up on open application window ledges.
    public var accumulateOnWindows: Bool = true

    /// Whether snow piles up along the macOS Dock border.
    public var accumulateOnDock: Bool = true

    /// Whether snow drifts along the bottom edge of connected displays.
    public var accumulateOnScreenBottom: Bool = true

    /// Whether the automatic snowplow vehicle sweeps the bottom drift when full.
    public var snowplowEnabled: Bool = true

    /// Selected snowplow model.
    public var snowplowModel: SnowplowModel = .classicTractor

    /// Custom photo/image URL for custom plow blade.
    public var customPlowImageURL: URL? = nil

    /// Whether festive fairy lights / garlands appear along the tops of windows.
    public var fairyLightsEnabled: Bool = false

    /// Whether cozy ambient winter sound effects loop.
    public var ambientSoundEnabled: Bool = false

    /// Ambient sound volume level (0.0 to 1.0).
    public var soundVolume: Float = 0.5

    /// Currently active cursor tool.
    public var activeTool: InteractiveTool = .none

    // MARK: - Aliases for Protocol Parity

    public var windDirectionDegrees: Double {
        get { windAngleDegrees }
        set { windAngleDegrees = newValue }
    }

    public var accumulateOnBottom: Bool {
        get { accumulateOnScreenBottom }
        set { accumulateOnScreenBottom = newValue }
    }

    public var isAudioEnabled: Bool {
        get { ambientSoundEnabled }
        set { ambientSoundEnabled = newValue }
    }

    public var audioVolume: Float {
        get { soundVolume }
        set { soundVolume = newValue }
    }

    public init(
        isEnabled: Bool = false,
        layerMode: FlakeLayerMode = .overlay,
        intensity: SnowfallIntensity = .steady,
        windAngleDegrees: Double = 90.0,
        windSpeed: Double = 1.0,
        accumulateOnWindows: Bool = true,
        accumulateOnDock: Bool = true,
        accumulateOnScreenBottom: Bool = true,
        snowplowEnabled: Bool = true,
        snowplowModel: SnowplowModel = .classicTractor,
        customPlowImageURL: URL? = nil,
        fairyLightsEnabled: Bool = false,
        ambientSoundEnabled: Bool = false,
        soundVolume: Float = 0.5,
        activeTool: InteractiveTool = .none
    ) {
        self.isEnabled = isEnabled
        self.layerMode = layerMode
        self.intensity = intensity
        self.windAngleDegrees = windAngleDegrees
        self.windSpeed = windSpeed
        self.accumulateOnWindows = accumulateOnWindows
        self.accumulateOnDock = accumulateOnDock
        self.accumulateOnScreenBottom = accumulateOnScreenBottom
        self.snowplowEnabled = snowplowEnabled
        self.snowplowModel = snowplowModel
        self.customPlowImageURL = customPlowImageURL
        self.fairyLightsEnabled = fairyLightsEnabled
        self.ambientSoundEnabled = ambientSoundEnabled
        self.soundVolume = soundVolume
        self.activeTool = activeTool
    }
}
