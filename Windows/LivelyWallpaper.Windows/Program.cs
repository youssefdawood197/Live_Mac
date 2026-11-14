using System;
using System.Windows.Forms;
using LivelyWallpaper.Windows.Core;
using LivelyWallpaper.Windows.Physics;
using LivelyWallpaper.Windows.UI;

namespace LivelyWallpaper.Windows;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        ApplicationConfiguration.Initialize();

        var config = new FlakeConfiguration();
        var desktopManager = new DesktopWindowManager();
        using var trayIcon = new TrayIconManager(config);

        trayIcon.OnClearSnowRequested += () =>
        {
            // Clear snowdrifts
        };

        trayIcon.OnOpenSettingsRequested += () =>
        {
            // Show settings window
        };

        Application.Run();
    }
}
