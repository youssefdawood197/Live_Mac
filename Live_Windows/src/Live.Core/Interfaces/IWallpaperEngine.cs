namespace Live.Core.Interfaces;

using System;
using Live.Core.Models;

/// <summary>
/// Lifecycle and playback contract for wallpaper rendering engines (Video, Web).
/// </summary>
public interface IWallpaperEngine : IDisposable
{
    WallpaperType SupportedType { get; }
    bool IsPlaying { get; }
    bool IsMuted { get; set; }
    float Volume { get; set; }

    void Load(WallpaperItem item, nint targetHwnd);
    void Play();
    void Pause();
    void Stop();
    void Close();
}
