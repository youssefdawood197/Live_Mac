namespace Live.Core.Flake;

using System.Text.Json.Serialization;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SnowfallIntensity
{
    Light,
    Steady,
    Blizzard
}

public static class SnowfallIntensityExtensions
{
    public static int GetMaxParticles(this SnowfallIntensity intensity) => intensity switch
    {
        SnowfallIntensity.Light => 150,
        SnowfallIntensity.Steady => 400,
        SnowfallIntensity.Blizzard => 900,
        _ => 400
    };

    public static float GetBirthRate(this SnowfallIntensity intensity) => intensity switch
    {
        SnowfallIntensity.Light => 20.0f,
        SnowfallIntensity.Steady => 50.0f,
        SnowfallIntensity.Blizzard => 120.0f,
        _ => 50.0f
    };

    public static float GetFallSpeedMultiplier(this SnowfallIntensity intensity) => intensity switch
    {
        SnowfallIntensity.Light => 0.8f,
        SnowfallIntensity.Steady => 1.0f,
        SnowfallIntensity.Blizzard => 1.4f,
        _ => 1.0f
    };
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SnowplowModel
{
    ClassicTractor,
    VintageTractor,
    Snowmobile,
    Penguin,
    Custom
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FlakeLayerMode
{
    Overlay,
    Desktop
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum InteractiveTool
{
    None,
    Mitten,
    Shovel,
    Snowman
}

public record FlakeConfiguration
{
    [JsonPropertyName("isEnabled")]
    public bool IsEnabled { get; init; } = false;

    [JsonPropertyName("layerMode")]
    public FlakeLayerMode LayerMode { get; init; } = FlakeLayerMode.Overlay;

    [JsonPropertyName("intensity")]
    public SnowfallIntensity Intensity { get; init; } = SnowfallIntensity.Steady;

    [JsonPropertyName("windAngleDegrees")]
    public double WindAngleDegrees { get; init; } = 90.0; // 90° = falling straight down

    [JsonPropertyName("windSpeed")]
    public double WindSpeed { get; init; } = 1.0;

    [JsonPropertyName("accumulateOnWindows")]
    public bool AccumulateOnWindows { get; init; } = true;

    [JsonPropertyName("accumulateOnTaskbar")]
    public bool AccumulateOnTaskbar { get; init; } = true;

    [JsonPropertyName("accumulateOnScreenBottom")]
    public bool AccumulateOnScreenBottom { get; init; } = true;

    [JsonPropertyName("snowplowEnabled")]
    public bool SnowplowEnabled { get; init; } = true;

    [JsonPropertyName("snowplowModel")]
    public SnowplowModel SnowplowModel { get; init; } = SnowplowModel.ClassicTractor;

    [JsonPropertyName("customPlowImagePath")]
    public string? CustomPlowImagePath { get; init; }

    [JsonPropertyName("fairyLightsEnabled")]
    public bool FairyLightsEnabled { get; init; } = false;

    [JsonPropertyName("ambientSoundEnabled")]
    public bool AmbientSoundEnabled { get; init; } = false;

    [JsonPropertyName("soundVolume")]
    public float SoundVolume { get; init; } = 0.5f;

    [JsonPropertyName("activeTool")]
    public InteractiveTool ActiveTool { get; init; } = InteractiveTool.None;
}
