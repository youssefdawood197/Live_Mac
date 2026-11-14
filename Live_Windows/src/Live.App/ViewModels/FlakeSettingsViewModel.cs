namespace Live.App.ViewModels;

using System;
using CommunityToolkit.Mvvm.ComponentModel;
using Live.Core.Flake;
using Live.Core.Models;

public partial class FlakeSettingsViewModel : ObservableObject
{
    private readonly AppState _state;

    public FlakeConfiguration Config => _state.FlakeConfig;

    public bool IsEnabled
    {
        get => _state.FlakeConfig.IsEnabled;
        set
        {
            if (_state.FlakeConfig.IsEnabled != value)
            {
                _state.FlakeConfig = _state.FlakeConfig with { IsEnabled = value };
                OnPropertyChanged();
            }
        }
    }

    public int IntensityIndex
    {
        get => (int)_state.FlakeConfig.Intensity;
        set
        {
            var intensity = (SnowfallIntensity)Math.Clamp(value, 0, 2);
            if (_state.FlakeConfig.Intensity != intensity)
            {
                _state.FlakeConfig = _state.FlakeConfig with { Intensity = intensity };
                OnPropertyChanged();
            }
        }
    }

    public double WindAngleDegrees
    {
        get => _state.FlakeConfig.WindAngleDegrees;
        set
        {
            if (Math.Abs(_state.FlakeConfig.WindAngleDegrees - value) > 0.01)
            {
                _state.FlakeConfig = _state.FlakeConfig with { WindAngleDegrees = value };
                OnPropertyChanged();
            }
        }
    }

    public double WindSpeed
    {
        get => _state.FlakeConfig.WindSpeed;
        set
        {
            if (Math.Abs(_state.FlakeConfig.WindSpeed - value) > 0.01)
            {
                _state.FlakeConfig = _state.FlakeConfig with { WindSpeed = value };
                OnPropertyChanged();
            }
        }
    }

    public int ToolIndex
    {
        get => (int)_state.FlakeConfig.ActiveTool;
        set
        {
            var tool = (InteractiveTool)Math.Clamp(value, 0, 2);
            if (_state.FlakeConfig.ActiveTool != tool)
            {
                _state.FlakeConfig = _state.FlakeConfig with { ActiveTool = tool };
                OnPropertyChanged();
            }
        }
    }

    public bool SnowplowEnabled
    {
        get => _state.FlakeConfig.SnowplowEnabled;
        set
        {
            if (_state.FlakeConfig.SnowplowEnabled != value)
            {
                _state.FlakeConfig = _state.FlakeConfig with { SnowplowEnabled = value };
                OnPropertyChanged();
            }
        }
    }

    public bool FairyLightsEnabled
    {
        get => _state.FlakeConfig.FairyLightsEnabled;
        set
        {
            if (_state.FlakeConfig.FairyLightsEnabled != value)
            {
                _state.FlakeConfig = _state.FlakeConfig with { FairyLightsEnabled = value };
                OnPropertyChanged();
            }
        }
    }

    public bool AmbientSoundEnabled
    {
        get => _state.FlakeConfig.AmbientSoundEnabled;
        set
        {
            if (_state.FlakeConfig.AmbientSoundEnabled != value)
            {
                _state.FlakeConfig = _state.FlakeConfig with { AmbientSoundEnabled = value };
                OnPropertyChanged();
            }
        }
    }

    public double SoundVolume
    {
        get => _state.FlakeConfig.SoundVolume;
        set
        {
            float fVal = (float)Math.Clamp(value, 0.0, 1.0);
            if (Math.Abs(_state.FlakeConfig.SoundVolume - fVal) > 0.01f)
            {
                _state.FlakeConfig = _state.FlakeConfig with { SoundVolume = fVal };
                OnPropertyChanged();
            }
        }
    }

    public FlakeSettingsViewModel(AppState state)
    {
        _state = state;
        _state.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(AppState.FlakeConfig))
            {
                OnPropertyChanged(string.Empty);
            }
        };
    }
}
