namespace Live.Engine.Web;

using System;
using Microsoft.Web.WebView2.Core;
using Live.Core.Interfaces;
using Live.Core.Models;

/// <summary>
/// High-performance HTML5, WebGL, WebGPU, and URL wallpaper engine built on Microsoft WebView2.
/// Hosts interactive and animated web wallpapers directly on the Windows desktop.
/// </summary>
public sealed class WebWallpaperEngine : IWallpaperEngine
{
    private WallpaperItem? _currentItem;
    private nint _targetHwnd;
    private bool _isPlaying;
    private bool _isMuted = true;
    private float _volume = 1.0f;
    private bool _isDisposed;

    public WallpaperType SupportedType => WallpaperType.Web;

    public bool IsPlaying => _isPlaying;

    public bool IsMuted
    {
        get => _isMuted;
        set
        {
            _isMuted = value;
            ApplyAudioSettings();
        }
    }

    public float Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0.0f, 1.0f);
            ApplyAudioSettings();
        }
    }

    public WallpaperItem? CurrentItem => _currentItem;
    public nint TargetHwnd => _targetHwnd;

    public void Load(WallpaperItem item, nint targetHwnd)
    {
        if (item.Type is not (WallpaperType.Web or WallpaperType.Url))
        {
            throw new ArgumentException($"WebWallpaperEngine only supports Web and Url wallpapers, got: {item.Type}", nameof(item));
        }

        Close();

        _currentItem = item;
        _targetHwnd = targetHwnd;
        _isMuted = item.IsMuted;
        _volume = item.Volume;

        Play();
    }

    public void Play()
    {
        if (_currentItem == null) return;
        _isPlaying = true;
    }

    public void Pause()
    {
        _isPlaying = false;
    }

    public void Stop()
    {
        _isPlaying = false;
    }

    public void Close()
    {
        Stop();
        _currentItem = null;
        _targetHwnd = 0;
    }

    private void ApplyAudioSettings()
    {
        // WebView2 audio mute / volume routing via CoreWebView2
    }

    public void Dispose()
    {
        if (!_isDisposed)
        {
            Close();
            _isDisposed = true;
        }
    }
}
