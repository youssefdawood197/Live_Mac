namespace Live.Core.Interfaces;

using System;
using Live.Core.Power;

/// <summary>
/// Contract for multi-source additive power and lifecycle management.
/// Automatically pauses rendering engines when screens sleep, lock, or fullscreen apps occlude.
/// </summary>
public interface IPowerManager : IDisposable
{
    PauseReasons CurrentPauseReasons { get; }
    bool IsPaused { get; }
    PowerSettings Settings { get; set; }
    bool IsMonitoring { get; }

    event EventHandler<PauseReasons>? PauseStateChanged;

    void StartMonitoring();
    void StopMonitoring();
    void AddPauseReason(PauseReasons reason);
    void RemovePauseReason(PauseReasons reason);
    void SetPauseReason(PauseReasons reason, bool active);
    void SetUserPaused(bool paused);
}
