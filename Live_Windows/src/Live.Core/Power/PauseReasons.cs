namespace Live.Core.Power;

using System;
using System.Collections.Generic;

/// <summary>
/// Additive bitmask representing all active sources requesting live wallpaper rendering suspension.
/// Exact 1:1 mathematical parity with macOS PauseReasons.swift.
/// </summary>
[Flags]
public enum PauseReasons : int
{
    None            = 0,
    UserPaused      = 1 << 0, // 1
    FullscreenApp   = 1 << 1, // 2
    DisplaySleeping = 1 << 2, // 4
    ScreenLocked    = 1 << 3, // 8
    BatterySaver    = 1 << 4, // 16
    All             = UserPaused | FullscreenApp | DisplaySleeping | ScreenLocked | BatterySaver // 31
}

public static class PauseReasonsExtensions
{
    public static string FormatDescription(this PauseReasons reasons)
    {
        if (reasons == PauseReasons.None) return "none";
        var parts = new List<string>();
        if ((reasons & PauseReasons.UserPaused) != 0) parts.Add("userPaused");
        if ((reasons & PauseReasons.FullscreenApp) != 0) parts.Add("fullscreenApp");
        if ((reasons & PauseReasons.DisplaySleeping) != 0) parts.Add("displaySleeping");
        if ((reasons & PauseReasons.ScreenLocked) != 0) parts.Add("screenLocked");
        if ((reasons & PauseReasons.BatterySaver) != 0) parts.Add("batterySaver");
        return string.Join(", ", parts);
    }
}
