using System;
using System.Runtime.InteropServices;

namespace LivelyWallpaper.Windows.Core;

/// <summary>
/// Manages the desktop-level window hierarchy on Windows.
/// Hooks into the Windows Explorer shell (Progman / WorkerW) to place live wallpapers
/// directly behind desktop icons without interfering with file icons, widgets, or mouse interactions.
/// </summary>
public sealed class DesktopWindowManager
{
    private const uint WM_SPAWN_WORKER = 0x052C;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string? windowTitle);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private IntPtr _workerWHwnd = IntPtr.Zero;

    /// <summary>
    /// Locates or creates the WorkerW window behind desktop icons.
    /// </summary>
    public IntPtr GetDesktopWorkerW()
    {
        if (_workerWHwnd != IntPtr.Zero)
            return _workerWHwnd;

        IntPtr progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero)
            return IntPtr.Zero;

        // Send 0x052C message to Progman to spawn WorkerW
        SendMessageTimeout(progman, WM_SPAWN_WORKER, UIntPtr.Zero, IntPtr.Zero, 0, 1000, out _);

        // Enumerate top-level windows to find the WorkerW that contains the desktop view
        EnumWindows((tophandle, _) =>
        {
            IntPtr defView = FindWindowEx(tophandle, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView != IntPtr.Zero)
            {
                // Find next WorkerW sibling
                _workerWHwnd = FindWindowEx(IntPtr.Zero, tophandle, "WorkerW", null);
                return false; // Stop enumeration
            }
            return true;
        }, IntPtr.Zero);

        return _workerWHwnd;
    }

    /// <summary>
    /// Parents a given window directly behind the Windows desktop icons.
    /// </summary>
    public bool AttachToDesktop(IntPtr windowHandle)
    {
        IntPtr workerW = GetDesktopWorkerW();
        if (workerW == IntPtr.Zero)
            return false;

        SetParent(windowHandle, workerW);
        return true;
    }
}
