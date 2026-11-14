using System;
using System.Drawing;
using System.Windows.Forms;
using LivelyWallpaper.Windows.Physics;

namespace LivelyWallpaper.Windows.UI;

/// <summary>
/// Manages the Windows notification area (System Tray) companion icon with quick controls.
/// </summary>
public sealed class TrayIconManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly FlakeConfiguration _config;
    private readonly ContextMenuStrip _contextMenu;

    public event Action? OnOpenSettingsRequested;
    public event Action? OnClearSnowRequested;
    public event Action? OnConfigurationChanged;

    public TrayIconManager(FlakeConfiguration config)
    {
        _config = config;
        _contextMenu = new ContextMenuStrip();

        _notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application, // Fallback icon; replaced with custom snowflake icon
            Text = "Lively Wallpaper & Flake",
            ContextMenuStrip = _contextMenu,
            Visible = true
        };

        RebuildMenu();
    }

    public void RebuildMenu()
    {
        _contextMenu.Items.Clear();

        // 1. Header
        var header = new ToolStripMenuItem("Lively Wallpaper (Flake Mode)") { Enabled = false };
        _contextMenu.Items.Add(header);
        _contextMenu.Items.Add(new ToolStripSeparator());

        // 2. Flake Mode Toggle
        var toggleItem = new ToolStripMenuItem(_config.IsEnabled ? "Disable Snowfall" : "Enable Snowfall")
        {
            Checked = _config.IsEnabled
        };
        toggleItem.Click += (_, _) =>
        {
            _config.IsEnabled = !_config.IsEnabled;
            OnConfigurationChanged?.Invoke();
            RebuildMenu();
        };
        _contextMenu.Items.Add(toggleItem);

        // 3. Intensity Submenu
        var intensityMenu = new ToolStripMenuItem("Snowfall Intensity");
        foreach (SnowfallIntensity intensity in Enum.GetValues<SnowfallIntensity>())
        {
            var item = new ToolStripMenuItem(intensity.ToString())
            {
                Checked = _config.Intensity == intensity
            };
            item.Click += (_, _) =>
            {
                _config.Intensity = intensity;
                OnConfigurationChanged?.Invoke();
                RebuildMenu();
            };
            intensityMenu.DropDownItems.Add(item);
        }
        _contextMenu.Items.Add(intensityMenu);

        // 4. Clear Snow
        var clearItem = new ToolStripMenuItem("Clear Snow Drifts");
        clearItem.Click += (_, _) => OnClearSnowRequested?.Invoke();
        _contextMenu.Items.Add(clearItem);

        _contextMenu.Items.Add(new ToolStripSeparator());

        // 5. Settings
        var settingsItem = new ToolStripMenuItem("Settings...");
        settingsItem.Click += (_, _) => OnOpenSettingsRequested?.Invoke();
        _contextMenu.Items.Add(settingsItem);

        _contextMenu.Items.Add(new ToolStripSeparator());

        // 6. Exit
        var exitItem = new ToolStripMenuItem("Exit Lively Wallpaper");
        exitItem.Click += (_, _) => Application.Exit();
        _contextMenu.Items.Add(exitItem);
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _contextMenu.Dispose();
    }
}
