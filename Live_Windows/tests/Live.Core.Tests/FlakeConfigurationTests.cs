namespace Live.Core.Tests;

using System;
using System.Text.Json;
using Live.Core.Flake;
using Xunit;

public class FlakeConfigurationTests
{
    [Fact]
    public void DefaultConfiguration_MatchesMacOSSymmetry()
    {
        var config = new FlakeConfiguration();

        Assert.False(config.IsEnabled);
        Assert.Equal(FlakeLayerMode.Overlay, config.LayerMode);
        Assert.Equal(SnowfallIntensity.Steady, config.Intensity);
        Assert.Equal(90.0, config.WindAngleDegrees);
        Assert.Equal(1.0, config.WindSpeed);
        Assert.True(config.AccumulateOnWindows);
        Assert.True(config.AccumulateOnTaskbar);
        Assert.True(config.AccumulateOnScreenBottom);
        Assert.True(config.SnowplowEnabled);
        Assert.Equal(SnowplowModel.ClassicTractor, config.SnowplowModel);
        Assert.False(config.FairyLightsEnabled);
        Assert.False(config.AmbientSoundEnabled);
        Assert.Equal(0.5f, config.SoundVolume);
        Assert.Equal(InteractiveTool.None, config.ActiveTool);
    }

    [Fact]
    public void SnowfallIntensity_TuningMetrics()
    {
        Assert.Equal(150, SnowfallIntensity.Light.GetMaxParticles());
        Assert.Equal(400, SnowfallIntensity.Steady.GetMaxParticles());
        Assert.Equal(900, SnowfallIntensity.Blizzard.GetMaxParticles());

        Assert.True(SnowfallIntensity.Light.GetBirthRate() < SnowfallIntensity.Steady.GetBirthRate());
        Assert.True(SnowfallIntensity.Steady.GetBirthRate() < SnowfallIntensity.Blizzard.GetBirthRate());

        Assert.True(SnowfallIntensity.Light.GetFallSpeedMultiplier() < SnowfallIntensity.Steady.GetFallSpeedMultiplier());
        Assert.True(SnowfallIntensity.Steady.GetFallSpeedMultiplier() < SnowfallIntensity.Blizzard.GetFallSpeedMultiplier());
    }

    [Fact]
    public void JsonSerialization_RoundTrip_PreservesProperties()
    {
        var original = new FlakeConfiguration
        {
            IsEnabled = true,
            LayerMode = FlakeLayerMode.Desktop,
            Intensity = SnowfallIntensity.Blizzard,
            WindAngleDegrees = 135.0,
            WindSpeed = 2.5,
            SnowplowModel = SnowplowModel.Penguin,
            FairyLightsEnabled = true,
            AmbientSoundEnabled = true,
            SoundVolume = 0.8f,
            ActiveTool = InteractiveTool.Mitten
        };

        string json = JsonSerializer.Serialize(original);
        var deserialized = JsonSerializer.Deserialize<FlakeConfiguration>(json);

        Assert.NotNull(deserialized);
        Assert.Equal(original, deserialized);
    }

    [Fact]
    public void WindVector_MathCalculations()
    {
        // 90° straight down: ForceX should be ~0, ForceY should be > 0 (downward in Win2D)
        var downWind = new WindVector(90.0, 1.0);
        Assert.True(Math.Abs(downWind.ForceX) < 0.001f);
        Assert.True(downWind.ForceY > 80.0f);

        // 0° pointing East: ForceX should be > 0
        var eastWind = new WindVector(0.0, 1.0);
        Assert.True(eastWind.ForceX > 0.0f);

        // 180° pointing West: ForceX should be < 0
        var westWind = new WindVector(180.0, 1.0);
        Assert.True(westWind.ForceX < 0.0f);
    }
}
