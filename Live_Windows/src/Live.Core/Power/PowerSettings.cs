namespace Live.Core.Power;

/// <summary>
/// User power management preferences controlling when live wallpaper playback and snowfall auto-pauses.
/// </summary>
public record PowerSettings(
    bool PauseOnFullscreen = true,
    bool PauseOnBattery = false,
    bool PauseOnDisplaySleep = true,
    bool PauseOnScreenLock = true,
    bool PauseOnLowPowerMode = true
);
