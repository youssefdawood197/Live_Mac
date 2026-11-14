namespace LivelyWallpaper.Windows.Physics;

/// <summary>
/// Snowfall density and particle count for Windows Flake Mode.
/// </summary>
public enum SnowfallIntensity
{
    Light = 0,
    Steady = 1,
    Blizzard = 2
}

/// <summary>
/// Vehicle or character model for the automatic snowplow sweeper.
/// </summary>
public enum SnowplowModel
{
    ClassicTractor,
    VintageTractor,
    Snowmobile,
    Penguin,
    Custom
}

/// <summary>
/// Rendering layer target on Windows.
/// </summary>
public enum FlakeLayerMode
{
    ScreenOverlay,     // WS_EX_LAYERED transparent overlay above open windows
    DesktopBackground  // Behind desktop icons via WorkerW
}

/// <summary>
/// Interactive cursor tools.
/// </summary>
public enum InteractiveTool
{
    None,
    Mitten,
    Shovel,
    Snowman
}

/// <summary>
/// Configuration model for Flake Mode on Windows, mirroring the macOS implementation.
/// </summary>
public sealed class FlakeConfiguration
{
    public bool IsEnabled { get; set; } = false;
    public FlakeLayerMode LayerMode { get; set; } = FlakeLayerMode.ScreenOverlay;
    public SnowfallIntensity Intensity { get; set; } = SnowfallIntensity.Steady;
    public double WindAngleDegrees { get; set; } = 90.0;
    public double WindSpeed { get; set; } = 1.0;
    public bool AccumulateOnWindows { get; set; } = true;
    public bool AccumulateOnTaskbar { get; set; } = true;
    public bool AccumulateOnScreenBottom { get; set; } = true;
    public bool SnowplowEnabled { get; set; } = true;
    public SnowplowModel SnowplowModel { get; set; } = SnowplowModel.ClassicTractor;
    public string? CustomPlowImagePath { get; set; }
    public bool FairyLightsEnabled { get; set; } = false;
    public bool AmbientSoundEnabled { get; set; } = false;
    public float SoundVolume { get; set; } = 0.5f;
    public InteractiveTool ActiveTool { get; set; } = InteractiveTool.None;
}
