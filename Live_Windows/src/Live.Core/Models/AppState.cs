namespace Live.Core.Models;

using System;
using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using Live.Core.Flake;

public enum NavigationTab
{
    Library,
    Flake,
    Settings
}

public partial class AppState : ObservableObject
{
    // Playback state
    [ObservableProperty]
    private bool _isPaused;

    [ObservableProperty]
    private bool _isMuted = true;

    [ObservableProperty]
    private bool _isInteractionModeEnabled;

    // Flake ambient mode state
    [ObservableProperty]
    private FlakeConfiguration _flakeConfig = new();

    // Wallpaper library collection
    public ObservableCollection<WallpaperItem> Wallpapers { get; } = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ActiveWallpaper))]
    private Guid? _activeWallpaperId;

    public WallpaperItem? ActiveWallpaper =>
        Wallpapers.FirstOrDefault(w => w.Id == ActiveWallpaperId);

    // UI navigation & filters
    [ObservableProperty]
    private NavigationTab _selectedTab = NavigationTab.Library;

    [ObservableProperty]
    private string _searchQuery = string.Empty;

    [ObservableProperty]
    private WallpaperType? _filterType;

    // Power preferences
    [ObservableProperty]
    private bool _pauseOnFullscreen = true;

    [ObservableProperty]
    private bool _pauseOnBattery = false;

    [ObservableProperty]
    private bool _pauseOnDisplaySleep = true;

    public void SetActiveWallpaper(Guid id)
    {
        if (Wallpapers.Any(w => w.Id == id))
        {
            ActiveWallpaperId = id;
        }
    }

    public void AddWallpaper(WallpaperItem item)
    {
        if (!Wallpapers.Any(w => w.Id == item.Id))
        {
            Wallpapers.Add(item);
        }
        if (ActiveWallpaperId == null)
        {
            ActiveWallpaperId = item.Id;
        }
    }

    public void RemoveWallpaper(Guid id)
    {
        var item = Wallpapers.FirstOrDefault(w => w.Id == id);
        if (item != null)
        {
            Wallpapers.Remove(item);
            if (ActiveWallpaperId == id)
            {
                ActiveWallpaperId = Wallpapers.FirstOrDefault()?.Id;
            }
        }
    }

    public void TogglePause() => IsPaused = !IsPaused;
    public void ToggleMute() => IsMuted = !IsMuted;
    public void ToggleInteractionMode() => IsInteractionModeEnabled = !IsInteractionModeEnabled;
}
