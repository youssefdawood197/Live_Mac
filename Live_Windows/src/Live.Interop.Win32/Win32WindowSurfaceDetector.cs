namespace Live.Interop.Win32;

using System;
using System.Collections.Generic;
using System.Drawing;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Dwm;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.WindowsAndMessaging;
using Live.Core.Flake;
using Live.Core.Interfaces;

/// <summary>
/// Abstraction record to allow mocking of Win32 window queries in automated unit tests.
/// </summary>
public record RawWindowInfo(
    nint Handle,
    string ClassName,
    Rectangle Bounds,
    bool IsVisible,
    bool IsIconic,
    bool IsCloaked
);

/// <summary>
/// Abstraction interface for querying top-level windows and monitor work areas.
/// </summary>
public interface IWindowInfoProvider
{
    IReadOnlyList<RawWindowInfo> EnumerateWindowsInZOrder();
    IReadOnlyList<Rectangle> GetMonitorWorkAreas();
}

/// <summary>
/// Production window info provider querying live Win32 / DWM APIs.
/// </summary>
public sealed class SystemWindowInfoProvider : IWindowInfoProvider
{
    public IReadOnlyList<RawWindowInfo> EnumerateWindowsInZOrder()
    {
        var windows = new List<RawWindowInfo>();

        PInvoke.EnumWindows((hwnd, lParam) =>
        {
            if (!PInvoke.IsWindowVisible(hwnd)) return true;

            bool isIconic = PInvoke.IsIconic(hwnd);

            // Check DWM cloaking (virtual desktops, suspended apps)
            bool isCloaked = false;
            int cloakedVal = 0;
            unsafe
            {
                HRESULT hr = PInvoke.DwmGetWindowAttribute(
                    hwnd,
                    DWMWINDOWATTRIBUTE.DWMWA_CLOAKED,
                    &cloakedVal,
                    (uint)sizeof(int)
                );
                if (hr.Succeeded && cloakedVal != 0)
                {
                    isCloaked = true;
                }
            }

            // Extract true physical frame bounds (no drop shadows)
            Rectangle bounds = Rectangle.Empty;
            RECT frameRect;
            unsafe
            {
                HRESULT hr = PInvoke.DwmGetWindowAttribute(
                    hwnd,
                    DWMWINDOWATTRIBUTE.DWMWA_EXTENDED_FRAME_BOUNDS,
                    &frameRect,
                    (uint)sizeof(RECT)
                );
                if (hr.Succeeded)
                {
                    bounds = new Rectangle(frameRect.left, frameRect.top, frameRect.right - frameRect.left, frameRect.bottom - frameRect.top);
                }
                else if (PInvoke.GetWindowRect(hwnd, out RECT winRect))
                {
                    bounds = new Rectangle(winRect.left, winRect.top, winRect.right - winRect.left, winRect.bottom - winRect.top);
                }
            }

            // Extract window class name
            string className = string.Empty;
            unsafe
            {
                char* buffer = stackalloc char[256];
                int len = PInvoke.GetClassName(hwnd, buffer, 256);
                if (len > 0)
                {
                    className = new string(buffer, 0, len);
                }
            }

            windows.Add(new RawWindowInfo(
                hwnd.Value,
                className,
                bounds,
                PInvoke.IsWindowVisible(hwnd),
                isIconic,
                isCloaked
            ));

            return true;
        }, 0);

        return windows;
    }

    public IReadOnlyList<Rectangle> GetMonitorWorkAreas()
    {
        var monitors = new List<Rectangle>();
        unsafe
        {
            PInvoke.EnumDisplayMonitors(
                HDC.Null,
                null,
                (hMonitor, hdcMonitor, lprcMonitor, lParam) =>
                {
                    var mi = new MONITORINFO { cbSize = (uint)sizeof(MONITORINFO) };
                    if (PInvoke.GetMonitorInfo(hMonitor, ref mi))
                    {
                        monitors.Add(new Rectangle(
                            mi.rcWork.left,
                            mi.rcWork.top,
                            mi.rcWork.right - mi.rcWork.left,
                            mi.rcWork.bottom - mi.rcWork.top
                        ));
                    }
                    return true;
                },
                0
            );
        }
        return monitors;
    }
}

/// <summary>
/// Detects visible horizontal window ledges and taskbar surfaces for snow accumulation,
/// complete with top-down horizontal interval occlusion clipping.
/// </summary>
public sealed class Win32WindowSurfaceDetector : IWindowSurfaceDetector
{
    private readonly IWindowInfoProvider _windowProvider;
    private readonly nint _overlayHwnd;

    public Win32WindowSurfaceDetector(IWindowInfoProvider? windowProvider = null, nint overlayHwnd = 0)
    {
        _windowProvider = windowProvider ?? new SystemWindowInfoProvider();
        _overlayHwnd = overlayHwnd;
    }

    public IReadOnlyList<CollisionSurface> DetectSurfaces(
        Rectangle virtualScreenBounds,
        FlakeConfiguration? config = null)
    {
        var cfg = config ?? new FlakeConfiguration();
        var surfaces = new List<CollisionSurface>();
        var occludingRectangles = new List<Rectangle>();

        // 1. Screen bottom surface ledge (ground plane, Id = 0, 1:1 macOS parity)
        if (cfg.AccumulateOnScreenBottom)
        {
            var workAreas = _windowProvider.GetMonitorWorkAreas();
            if (workAreas.Count > 0)
            {
                foreach (var area in workAreas)
                {
                    surfaces.Add(new CollisionSurface(
                        Id: 0,
                        Frame: area,
                        TopEdgeY: area.Bottom,
                        MinX: area.Left,
                        MaxX: area.Right,
                        IsTaskbar: false
                    ));
                }
            }
            else
            {
                surfaces.Add(new CollisionSurface(
                    Id: 0,
                    Frame: virtualScreenBounds,
                    TopEdgeY: virtualScreenBounds.Bottom,
                    MinX: virtualScreenBounds.Left,
                    MaxX: virtualScreenBounds.Right,
                    IsTaskbar: false
                ));
            }
        }

        if (!cfg.AccumulateOnWindows && !cfg.AccumulateOnTaskbar)
        {
            return surfaces;
        }

        // 2. Enumerate windows in top-down Z-order
        var windows = _windowProvider.EnumerateWindowsInZOrder();

        foreach (var win in windows)
        {
            // Skip self and shell windows
            if (win.Handle == _overlayHwnd) continue;
            if (string.Equals(win.ClassName, "Progman", StringComparison.OrdinalIgnoreCase)) continue;
            if (string.Equals(win.ClassName, "WorkerW", StringComparison.OrdinalIgnoreCase)) continue;
            if (string.Equals(win.ClassName, "Shell_LightDismissOverlay", StringComparison.OrdinalIgnoreCase)) continue;

            // Visibility & Cloak filters
            if (!win.IsVisible || win.IsIconic || win.IsCloaked) continue;

            bool isTaskbar = string.Equals(win.ClassName, "Shell_TrayWnd", StringComparison.OrdinalIgnoreCase) ||
                             string.Equals(win.ClassName, "Shell_SecondaryTrayWnd", StringComparison.OrdinalIgnoreCase);

            if (isTaskbar && !cfg.AccumulateOnTaskbar) continue;
            if (!isTaskbar && !cfg.AccumulateOnWindows) continue;

            // Size thresholds
            if (win.Bounds.Width < 120 || win.Bounds.Height < 80)
            {
                if (!isTaskbar) continue;
            }

            int topY = win.Bounds.Top;
            int minX = win.Bounds.Left;
            int maxX = win.Bounds.Right;

            // Clip horizontal top ledge against all higher-Z occluding window rectangles
            var visibleSegments = ClipLedgeByOccluders(minX, maxX, topY, occludingRectangles);

            foreach (var (segMinX, segMaxX) in visibleSegments)
            {
                surfaces.Add(new CollisionSurface(
                    Id: (ulong)win.Handle,
                    Frame: win.Bounds,
                    TopEdgeY: topY,
                    MinX: segMinX,
                    MaxX: segMaxX,
                    IsTaskbar: isTaskbar
                ));
            }

            // Register this window's bounding box as an occluder for lower-Z windows
            occludingRectangles.Add(win.Bounds);
        }

        return surfaces;
    }

    /// <summary>
    /// Clips a horizontal line segment [startX, endX] at elevation topY against occluding window rectangles.
    /// Returns only visible segments with width >= 40px.
    /// </summary>
    public static List<(int MinX, int MaxX)> ClipLedgeByOccluders(
        int startX,
        int endX,
        int topY,
        List<Rectangle> occluders)
    {
        var currentSegments = new List<(int MinX, int MaxX)> { (startX, endX) };

        foreach (var occluder in occluders)
        {
            // Does this occluding window vertically cover the ledge elevation topY?
            if (topY < occluder.Top || topY > occluder.Bottom) continue;

            int occLeft = occluder.Left;
            int occRight = occluder.Right;

            // Occluder does not horizontally overlap
            if (occRight <= startX || occLeft >= endX) continue;

            var nextSegments = new List<(int MinX, int MaxX)>();

            foreach (var (segLeft, segRight) in currentSegments)
            {
                if (occRight <= segLeft || occLeft >= segRight)
                {
                    // Disjoint: segment remains untouched
                    nextSegments.Add((segLeft, segRight));
                }
                else if (occLeft <= segLeft && occRight >= segRight)
                {
                    // Segment completely occluded: discarded
                }
                else if (occLeft <= segLeft && occRight < segRight)
                {
                    // Occluder cuts into left side
                    nextSegments.Add((occRight, segRight));
                }
                else if (occLeft > segLeft && occRight >= segRight)
                {
                    // Occluder cuts into right side
                    nextSegments.Add((segLeft, occLeft));
                }
                else
                {
                    // Occluder punches a hole in the middle: split into two
                    nextSegments.Add((segLeft, occLeft));
                    nextSegments.Add((occRight, segRight));
                }
            }

            currentSegments = nextSegments;
            if (currentSegments.Count == 0) break;
        }

        // Filter out tiny slivers (< 40px threshold)
        var result = new List<(int MinX, int MaxX)>();
        foreach (var seg in currentSegments)
        {
            if (seg.MaxX - seg.MinX >= 40)
            {
                result.Add(seg);
            }
        }

        return result;
    }
}
