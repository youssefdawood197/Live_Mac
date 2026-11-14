using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

namespace LivelyWallpaper.Windows.Physics;

public readonly struct CollisionSurface
{
    public IntPtr WindowHandle { get; init; }
    public Rectangle Bounds { get; init; }
    public int TopEdgeY => Bounds.Top;
    public int MinX => Bounds.Left;
    public int MaxX => Bounds.Right;
    public int Width => Bounds.Width;
    public bool IsTaskbar { get; init; }

    public bool ContainsX(int x) => x >= MinX && x <= MaxX;
}

/// <summary>
/// Detects top ledges of visible Windows application windows and the Windows Taskbar for physical snow accumulation.
/// Uses zero-hook Win32 enumeration and DWM extended frame queries.
/// </summary>
public sealed class WindowSurfaceDetector
{
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public Rectangle ToRectangle() => new(Left, Top, Right - Left, Bottom - Top);
    }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    /// <summary>
    /// Detects visible collision ledges across active displays.
    /// </summary>
    public IReadOnlyList<CollisionSurface> DetectSurfaces(Rectangle screenBounds, FlakeConfiguration config)
    {
        var surfaces = new List<CollisionSurface>();

        // 1. Bottom of the display screen
        if (config.AccumulateOnScreenBottom)
        {
            surfaces.Add(new CollisionSurface
            {
                WindowHandle = IntPtr.Zero,
                Bounds = new Rectangle(screenBounds.Left, screenBounds.Bottom - 1, screenBounds.Width, 1),
                IsTaskbar = false
            });
        }

        // 2. Windows Taskbar
        if (config.AccumulateOnTaskbar)
        {
            IntPtr taskbarHwnd = FindWindow("Shell_TrayWnd", null);
            if (taskbarHwnd != IntPtr.Zero && IsWindowVisible(taskbarHwnd))
            {
                if (DwmGetWindowAttribute(taskbarHwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT taskbarRect, Marshal.SizeOf<RECT>()) == 0)
                {
                    Rectangle rect = taskbarRect.ToRectangle();
                    if (rect.IntersectsWith(screenBounds))
                    {
                        surfaces.Add(new CollisionSurface
                        {
                            WindowHandle = taskbarHwnd,
                            Bounds = rect,
                            IsTaskbar = true
                        });
                    }
                }
            }
        }

        // 3. Application Windows
        if (config.AccumulateOnWindows)
        {
            EnumWindows((hWnd, lParam) =>
            {
                if (!IsWindowVisible(hWnd) || IsIconic(hWnd))
                    return true;

                if (DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT rectStruct, Marshal.SizeOf<RECT>()) == 0)
                {
                    Rectangle rect = rectStruct.ToRectangle();

                    // Filter out microscopic or off-screen windows
                    if (rect.Width >= 120 && rect.Height >= 80 && rect.IntersectsWith(screenBounds))
                    {
                        surfaces.Add(new CollisionSurface
                        {
                            WindowHandle = hWnd,
                            Bounds = rect,
                            IsTaskbar = false
                        });
                    }
                }
                return true;
            }, IntPtr.Zero);
        }

        return surfaces;
    }
}
