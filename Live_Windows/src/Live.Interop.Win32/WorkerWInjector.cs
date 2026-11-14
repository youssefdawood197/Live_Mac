namespace Live.Interop.Win32;

using System;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;
using Live.Core.Interfaces;

/// <summary>
/// Manages the Windows Explorer WorkerW handshake (0x052C) to inject live wallpapers
/// behind desktop icons, with automatic recovery upon Explorer crashes.
/// </summary>
public sealed class WorkerWInjector : IDesktopWindowManager
{
    private const uint WM_SPAWN_WORKER = 0x052C;
    private readonly uint _wmTaskbarCreated;
    private HWND _workerwHwnd = HWND.Null;
    private HWND _reparentedChildHwnd = HWND.Null;
    private bool _isDisposed;

    public HWND WorkerWHandle => _workerwHwnd;

    public event EventHandler? DesktopReset;
    public event EventHandler? WorkerWReset;

    public WorkerWInjector()
    {
        _wmTaskbarCreated = PInvoke.RegisterWindowMessage("TaskbarCreated");
    }

    /// <summary>
    /// Obtains the handle of the WorkerW window positioned directly behind desktop icons.
    /// If not yet initialized or invalid, executes the 0x052C handshake protocol.
    /// </summary>
    public HWND GetWorkerW()
    {
        if (_workerwHwnd != HWND.Null && PInvoke.IsWindow(_workerwHwnd))
        {
            return _workerwHwnd;
        }

        HWND progman = PInvoke.FindWindow("Progman", null);
        if (progman == HWND.Null)
        {
            return HWND.Null;
        }

        // Step 1: Send 0x052C to Progman to trigger WorkerW split
        nuint result = 0;
        PInvoke.SendMessageTimeout(
            progman,
            WM_SPAWN_WORKER,
            new WPARAM(0x0000000D),
            new LPARAM(0x00000001),
            SEND_MESSAGE_TIMEOUT_FLAGS.SMTO_NORMAL,
            1000,
            out result
        );

        // Step 2: Enumerate top-level windows to find the sibling WorkerW behind SHELLDLL_DefView
        HWND foundWorkerW = HWND.Null;
        PInvoke.EnumWindows((topHwnd, lParam) =>
        {
            HWND shellDll = PInvoke.FindWindowEx(topHwnd, HWND.Null, "SHELLDLL_DefView", null);
            if (shellDll != HWND.Null)
            {
                // The target WorkerW follows immediately behind the window hosting SHELLDLL_DefView
                foundWorkerW = PInvoke.FindWindowEx(HWND.Null, topHwnd, "WorkerW", null);
            }
            return true;
        }, 0);

        _workerwHwnd = foundWorkerW;
        return _workerwHwnd;
    }

    public nint GetDesktopWorkerW() => (nint)GetWorkerW().Value;

    /// <summary>
    /// Reparents a wallpaper rendering window to the WorkerW desktop background.
    /// </summary>
    public bool AttachToDesktop(HWND contentHwnd, int x, int y, int width, int height)
    {
        HWND targetWorkerW = GetWorkerW();
        if (targetWorkerW == HWND.Null)
        {
            return false;
        }

        _reparentedChildHwnd = contentHwnd;

        // Set child window styles
        nint currentStyle = PInvoke.GetWindowLongPtr(contentHwnd, WINDOW_LONG_PTR_INDEX.GWL_STYLE);
        currentStyle |= (nint)(WINDOW_STYLE.WS_CHILD | WINDOW_STYLE.WS_VISIBLE | WINDOW_STYLE.WS_CLIPSIBLINGS | WINDOW_STYLE.WS_CLIPCHILDREN);
        currentStyle &= ~(nint)(WINDOW_STYLE.WS_POPUP | WINDOW_STYLE.WS_CAPTION | WINDOW_STYLE.WS_THICKFRAME);
        PInvoke.SetWindowLongPtr(contentHwnd, WINDOW_LONG_PTR_INDEX.GWL_STYLE, currentStyle);

        PInvoke.SetParent(contentHwnd, targetWorkerW);
        PInvoke.SetWindowPos(
            contentHwnd,
            HWND.Null,
            x, y, width, height,
            SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE |
            SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW |
            SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED
        );

        return true;
    }

    public bool AttachWallpaper(nint contentHwnd, int x, int y, int width, int height) =>
        AttachToDesktop(new HWND(contentHwnd), x, y, width, height);

    /// <summary>
    /// Processes window messages to detect Explorer restarts and recover WorkerW reparenting.
    /// </summary>
    public bool HandleWindowMessage(uint msg, WPARAM wParam, LPARAM lParam)
    {
        if (msg == _wmTaskbarCreated && _wmTaskbarCreated != 0)
        {
            // Explorer restarted! Invalidate handle and recover
            _workerwHwnd = HWND.Null;
            HWND newWorkerW = GetWorkerW();

            if (_reparentedChildHwnd != HWND.Null && newWorkerW != HWND.Null)
            {
                PInvoke.SetParent(_reparentedChildHwnd, newWorkerW);
            }

            WorkerWReset?.Invoke(this, EventArgs.Empty);
            DesktopReset?.Invoke(this, EventArgs.Empty);
            return true;
        }

        return false;
    }

    public void Detach(HWND contentHwnd)
    {
        if (contentHwnd == _reparentedChildHwnd)
        {
            PInvoke.SetParent(contentHwnd, HWND.Null);
            _reparentedChildHwnd = HWND.Null;
        }
    }

    public void DetachWallpaper(nint contentHwnd) => Detach(new HWND(contentHwnd));

    public void Dispose()
    {
        if (!_isDisposed)
        {
            if (_reparentedChildHwnd != HWND.Null)
            {
                Detach(_reparentedChildHwnd);
            }
            _isDisposed = true;
        }
    }
}
