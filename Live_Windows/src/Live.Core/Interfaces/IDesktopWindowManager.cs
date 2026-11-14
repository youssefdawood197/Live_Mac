namespace Live.Core.Interfaces;

using System;

/// <summary>
/// Manages desktop window hierarchy, WorkerW reparenting, and Explorer desktop crash recovery.
/// </summary>
public interface IDesktopWindowManager : IDisposable
{
    nint GetDesktopWorkerW();
    bool AttachWallpaper(nint contentHwnd, int x, int y, int width, int height);
    void DetachWallpaper(nint contentHwnd);
    event EventHandler? DesktopReset;
}
