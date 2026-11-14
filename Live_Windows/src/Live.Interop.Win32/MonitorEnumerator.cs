namespace Live.Interop.Win32;

using System;
using System.Collections.Generic;
using System.Drawing;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.HiDpi;

public readonly record struct DisplayMonitorInfo(
    nint Handle,
    string DeviceName,
    Rectangle Bounds,
    Rectangle WorkArea,
    bool IsPrimary,
    uint DpiX,
    uint DpiY
)
{
    public float ScaleFactorX => DpiX / 96.0f;
    public float ScaleFactorY => DpiY / 96.0f;
}

public static class MonitorEnumerator
{
    public static IReadOnlyList<DisplayMonitorInfo> EnumerateMonitors()
    {
        var monitors = new List<DisplayMonitorInfo>();

        unsafe
        {
            PInvoke.EnumDisplayMonitors(
                HDC.Null,
                null,
                (hMonitor, hdcMonitor, lprcMonitor, lParam) =>
                {
                    var mi = new MONITORINFOEXW { MonitorInfo = new MONITORINFO { cbSize = (uint)sizeof(MONITORINFOEXW) } };
                    if (PInvoke.GetMonitorInfo(hMonitor, (MONITORINFO*)&mi))
                    {
                        string name = new string(mi.szDevice.AsSpan()).TrimEnd('\0');
                        var bounds = new Rectangle(
                            mi.MonitorInfo.rcMonitor.left,
                            mi.MonitorInfo.rcMonitor.top,
                            mi.MonitorInfo.rcMonitor.right - mi.MonitorInfo.rcMonitor.left,
                            mi.MonitorInfo.rcMonitor.bottom - mi.MonitorInfo.rcMonitor.top
                        );
                        var workArea = new Rectangle(
                            mi.MonitorInfo.rcWork.left,
                            mi.MonitorInfo.rcWork.top,
                            mi.MonitorInfo.rcWork.right - mi.MonitorInfo.rcWork.left,
                            mi.MonitorInfo.rcWork.bottom - mi.MonitorInfo.rcWork.top
                        );
                        bool isPrimary = (mi.MonitorInfo.dwFlags & 1) != 0; // MONITORINFOF_PRIMARY

                        uint dpiX = 96, dpiY = 96;
                        try
                        {
                            PInvoke.GetDpiForMonitor(hMonitor, MONITOR_DPI_TYPE.MDT_EFFECTIVE_DPI, out dpiX, out dpiY);
                        }
                        catch
                        {
                            dpiX = 96;
                            dpiY = 96;
                        }

                        monitors.Add(new DisplayMonitorInfo(
                            hMonitor.Value,
                            name,
                            bounds,
                            workArea,
                            isPrimary,
                            dpiX,
                            dpiY
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
