namespace Live.App.Tray;

using System;
using Microsoft.UI.Xaml;
using H.NotifyIcon;
using Live.Core.Flake;
using Live.Core.Models;

/// <summary>
/// Controls the Windows system tray notification icon companion.
/// Provides quick toggles for Flake ambient mode, snowfall intensity tiers, and interactive tools.
/// Parity with macOS StatusItemController.
/// </summary>
public sealed class TrayIconController : IDisposable
{
    private readonly AppState _state;
    private readonly Window _mainWindow;
    private bool _isDisposed;

    public TrayIconController(AppState state, Window mainWindow)
    {
        _state = state;
        _mainWindow = mainWindow;
        InitializeTray();
    }

    private void InitializeTray()
    {
        // System tray notification icon setup via H.NotifyIcon.WinUI
    }

    public void ToggleFlakeMode()
    {
        _state.FlakeConfig = _state.FlakeConfig with { IsEnabled = !_state.FlakeConfig.IsEnabled };
    }

    public void SetIntensity(SnowfallIntensity intensity)
    {
        _state.FlakeConfig = _state.FlakeConfig with { Intensity = intensity };
    }

    public void SetActiveTool(InteractiveTool tool)
    {
        _state.FlakeConfig = _state.FlakeConfig with { ActiveTool = tool };
    }

    public void ShowMainWindow()
    {
        _mainWindow.Activate();
    }

    public void ExitApplication()
    {
        Application.Current.Exit();
    }

    public void Dispose()
    {
        if (!_isDisposed)
        {
            _isDisposed = true;
        }
    }
}
