namespace Live.Interop.Win32;

using System;
using System.Drawing;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.System.Power;
using Windows.Win32.UI.WindowsAndMessaging;
using Live.Core.Interfaces;
using Live.Core.Power;

/// <summary>
/// Monitors Windows power and session events: display sleep, workstation lock,
/// battery status, and active fullscreen window occlusion to manage additive pause states.
/// </summary>
public sealed class WindowsPowerManager : IPowerManager
{
    private PauseReasons _currentPauseReasons = PauseReasons.None;
    private PowerSettings _settings = new();
    private bool _isMonitoring;
    private bool _isDisposed;

    public PauseReasons CurrentPauseReasons => _currentPauseReasons;
    public bool IsPaused => _currentPauseReasons != PauseReasons.None;

    public PowerSettings Settings
    {
        get => _settings;
        set => _settings = value;
    }

    public bool IsMonitoring => _isMonitoring;

    public event EventHandler<PauseReasons>? PauseStateChanged;

    public void StartMonitoring()
    {
        if (_isMonitoring) return;
        _isMonitoring = true;
        EvaluateBatteryStatus();
    }

    public void StopMonitoring()
    {
        _isMonitoring = false;
    }

    public void AddPauseReason(PauseReasons reason)
    {
        if (reason == PauseReasons.None) return;
        var oldReasons = _currentPauseReasons;
        _currentPauseReasons |= reason;
        if (_currentPauseReasons != oldReasons)
        {
            PauseStateChanged?.Invoke(this, _currentPauseReasons);
        }
    }

    public void RemovePauseReason(PauseReasons reason)
    {
        if (reason == PauseReasons.None) return;
        var oldReasons = _currentPauseReasons;
        _currentPauseReasons &= ~reason;
        if (_currentPauseReasons != oldReasons)
        {
            PauseStateChanged?.Invoke(this, _currentPauseReasons);
        }
    }

    public void SetPauseReason(PauseReasons reason, bool active)
    {
        if (active)
        {
            AddPauseReason(reason);
        }
        else
        {
            RemovePauseReason(reason);
        }
    }

    public void SetUserPaused(bool paused)
    {
        SetPauseReason(PauseReasons.UserPaused, paused);
    }

    /// <summary>
    /// Checks whether the current foreground application covers an entire monitor in fullscreen mode.
    /// </summary>
    public bool CheckForegroundFullscreen()
    {
        if (!_settings.PauseOnFullscreen)
        {
            RemovePauseReason(PauseReasons.FullscreenApp);
            return false;
        }

        HWND foreground = PInvoke.GetForegroundWindow();
        if (foreground == HWND.Null)
        {
            RemovePauseReason(PauseReasons.FullscreenApp);
            return false;
        }

        // Ignore desktop/shell
        unsafe
        {
            char* buffer = stackalloc char[256];
            int len = PInvoke.GetClassName(foreground, buffer, 256);
            if (len > 0)
            {
                string className = new string(buffer, 0, len);
                if (className is "Progman" or "WorkerW" or "Shell_TrayWnd")
                {
                    RemovePauseReason(PauseReasons.FullscreenApp);
                    return false;
                }
            }
        }

        if (PInvoke.GetWindowRect(foreground, out RECT winRect))
        {
            HMONITOR hMon = PInvoke.MonitorFromWindow(foreground, MONITOR_FROM_FLAGS.MONITOR_DEFAULTTONEAREST);
            var mi = new MONITORINFO { cbSize = (uint)sizeof(MONITORINFO) };
            if (PInvoke.GetMonitorInfo(hMon, ref mi))
            {
                // Fullscreen if window rect covers or exceeds monitor rect
                bool isFullscreen = winRect.left <= mi.rcMonitor.left &&
                                    winRect.top <= mi.rcMonitor.top &&
                                    winRect.right >= mi.rcMonitor.right &&
                                    winRect.bottom >= mi.rcMonitor.bottom;

                SetPauseReason(PauseReasons.FullscreenApp, isFullscreen);
                return isFullscreen;
            }
        }

        RemovePauseReason(PauseReasons.FullscreenApp);
        return false;
    }

    /// <summary>
    /// Queries the Win32 system power status for battery operation.
    /// </summary>
    public void EvaluateBatteryStatus()
    {
        if (!_settings.PauseOnBattery)
        {
            RemovePauseReason(PauseReasons.BatterySaver);
            return;
        }

        if (PInvoke.GetSystemPowerStatus(out SYSTEM_POWER_STATUS status))
        {
            // ACLineStatus == 0 indicates battery power (offline from AC)
            bool onBattery = status.ACLineStatus == 0;
            SetPauseReason(PauseReasons.BatterySaver, onBattery);
        }
    }

    /// <summary>
    /// Handles session notifications such as workstation lock/unlock (WTS_SESSION_LOCK / WTS_SESSION_UNLOCK).
    /// </summary>
    public void HandleSessionChange(uint eventType)
    {
        const uint WTS_SESSION_LOCK = 0x7;
        const uint WTS_SESSION_UNLOCK = 0x8;

        if (eventType == WTS_SESSION_LOCK && _settings.PauseOnScreenLock)
        {
            AddPauseReason(PauseReasons.ScreenLocked);
        }
        else if (eventType == WTS_SESSION_UNLOCK)
        {
            RemovePauseReason(PauseReasons.ScreenLocked);
        }
    }

    /// <summary>
    /// Handles power setting change notifications (e.g. GUID_CONSOLE_DISPLAY_STATE).
    /// </summary>
    public void HandleDisplayStateChange(int displayState)
    {
        // 0 = Display Off, 1 = Display On, 2 = Display Dimmed
        if (displayState == 0 && _settings.PauseOnDisplaySleep)
        {
            AddPauseReason(PauseReasons.DisplaySleeping);
        }
        else if (displayState == 1)
        {
            RemovePauseReason(PauseReasons.DisplaySleeping);
        }
    }

    public void Dispose()
    {
        if (!_isDisposed)
        {
            StopMonitoring();
            _isDisposed = true;
        }
    }
}
