namespace Live.App;

using System;
using Microsoft.UI.Xaml;
using Live.App.Tray;
using Live.Core.Models;
using Live.Interop.Win32;

/// <summary>
/// Provides application-specific behavior to supplement the default Application class.
/// </summary>
public partial class App : Application
{
    private MainWindow? _mainWindow;
    private TrayIconController? _trayController;

    public static AppState State { get; } = new();
    public static WindowsPowerManager Power { get; } = new();
    public static WorkerWInjector WindowManager { get; } = new();

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Power.StartMonitoring();

        _mainWindow = new MainWindow();
        _trayController = new TrayIconController(State, _mainWindow);

        _mainWindow.Activate();
    }
}
