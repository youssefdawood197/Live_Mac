namespace Live.App.ViewModels;

using System;
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Live.Core.Models;

public partial class MainViewModel : ObservableObject
{
    private readonly AppState _state;

    public ObservableCollection<WallpaperItem> Wallpapers => _state.Wallpapers;

    public WallpaperItem? ActiveWallpaper
    {
        get => _state.ActiveWallpaper;
        set
        {
            if (value != null)
            {
                _state.SetActiveWallpaper(value.Id);
                OnPropertyChanged();
            }
        }
    }

    public bool IsPaused
    {
        get => _state.IsPaused;
        set
        {
            if (_state.IsPaused != value)
            {
                _state.IsPaused = value;
                OnPropertyChanged();
            }
        }
    }

    public bool IsMuted
    {
        get => _state.IsMuted;
        set
        {
            if (_state.IsMuted != value)
            {
                _state.IsMuted = value;
                OnPropertyChanged();
            }
        }
    }

    public bool PauseOnFullscreen
    {
        get => _state.PauseOnFullscreen;
        set
        {
            if (_state.PauseOnFullscreen != value)
            {
                _state.PauseOnFullscreen = value;
                OnPropertyChanged();
            }
        }
    }

    public bool PauseOnBattery
    {
        get => _state.PauseOnBattery;
        set
        {
            if (_state.PauseOnBattery != value)
            {
                _state.PauseOnBattery = value;
                OnPropertyChanged();
            }
        }
    }

    public bool PauseOnDisplaySleep
    {
        get => _state.PauseOnDisplaySleep;
        set
        {
            if (_state.PauseOnDisplaySleep != value)
            {
                _state.PauseOnDisplaySleep = value;
                OnPropertyChanged();
            }
        }
    }

    public MainViewModel(AppState state)
    {
        _state = state;
        _state.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(AppState.ActiveWallpaperId) || e.PropertyName == nameof(AppState.ActiveWallpaper))
            {
                OnPropertyChanged(nameof(ActiveWallpaper));
            }
            else if (e.PropertyName == nameof(AppState.IsPaused))
            {
                OnPropertyChanged(nameof(IsPaused));
            }
            else if (e.PropertyName == nameof(AppState.IsMuted))
            {
                OnPropertyChanged(nameof(IsMuted));
            }
        };
    }

    [RelayCommand]
    public void TogglePause() => _state.TogglePause();

    [RelayCommand]
    public void ToggleMute() => _state.ToggleMute();
}
