namespace Live.Engine.Flake;

using System;
using System.Drawing;
using System.Runtime.InteropServices;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;
using Live.Core.Flake;

/// <summary>
/// Manages a topmost, borderless, transparent layered Win32 window covering the virtual desktop.
/// Supports dynamic click-through passthrough toggling for interactive clearing tools.
/// </summary>
public sealed class FlakeOverlayWindow : IDisposable
{
    private const string WindowClassName = "LiveFlakeOverlayWindow";
    private readonly WNDPROC _wndProcDelegate;
    private HWND _hwnd = HWND.Null;
    private bool _isDisposed;
    private Rectangle _virtualBounds;
    private InteractiveTool _currentTool = InteractiveTool.None;

    public HWND Handle => _hwnd;
    public Rectangle VirtualBounds => _virtualBounds;
    public InteractiveTool CurrentTool => _currentTool;

    public event Action<Point>? MouseMoved;
    public event Action<Point>? MouseDragged;

    public FlakeOverlayWindow()
    {
        _wndProcDelegate = WndProc;
        RegisterWindowClass();
        UpdateVirtualScreenBounds();
        CreateWindow();
    }

    private void UpdateVirtualScreenBounds()
    {
        int x = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_XVIRTUALSCREEN);
        int y = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_YVIRTUALSCREEN);
        int cx = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXVIRTUALSCREEN);
        int cy = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYVIRTUALSCREEN);
        _virtualBounds = new Rectangle(x, y, cx, cy);
    }

    private unsafe void RegisterWindowClass()
    {
        fixed (char* pClassName = WindowClassName)
        {
            var wc = new WNDCLASSEXW
            {
                cbSize = (uint)sizeof(WNDCLASSEXW),
                style = WNDCLASS_STYLES.CS_HREDRAW | WNDCLASS_STYLES.CS_VREDRAW,
                lpfnWndProc = _wndProcDelegate,
                lpszClassName = pClassName,
                hInstance = (HINSTANCE)PInvoke.GetModuleHandle((string?)null).Value
            };

            PInvoke.RegisterClassEx(wc);
        }
    }

    private void CreateWindow()
    {
        WINDOW_STYLE style = WINDOW_STYLE.WS_POPUP | WINDOW_STYLE.WS_VISIBLE;
        WINDOW_EX_STYLE exStyle =
            WINDOW_EX_STYLE.WS_EX_TOPMOST |
            WINDOW_EX_STYLE.WS_EX_TOOLWINDOW |
            WINDOW_EX_STYLE.WS_EX_LAYERED |
            WINDOW_EX_STYLE.WS_EX_TRANSPARENT |
            WINDOW_EX_STYLE.WS_EX_NOACTIVATE;

        _hwnd = PInvoke.CreateWindowEx(
            exStyle,
            WindowClassName,
            "Live Wallpaper Flake Overlay",
            style,
            _virtualBounds.X,
            _virtualBounds.Y,
            _virtualBounds.Width,
            _virtualBounds.Height,
            HWND.Null,
            null,
            null,
            null
        );
    }

    /// <summary>
    /// Switches dynamic mouse event passthrough between idle click-through and tool interaction.
    /// </summary>
    public void SetInteractiveTool(InteractiveTool tool)
    {
        if (_hwnd == HWND.Null || _currentTool == tool) return;

        _currentTool = tool;
        nint currentExStyle = PInvoke.GetWindowLongPtr(_hwnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);

        if (tool == InteractiveTool.None)
        {
            // Restore click-through passthrough
            currentExStyle |= (nint)WINDOW_EX_STYLE.WS_EX_TRANSPARENT;
        }
        else
        {
            // Intercept mouse clicks for mitten/shovel without stealing focus
            currentExStyle &= ~(nint)WINDOW_EX_STYLE.WS_EX_TRANSPARENT;
        }

        PInvoke.SetWindowLongPtr(_hwnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE, currentExStyle);

        PInvoke.SetWindowPos(
            _hwnd,
            HWND.HWND_TOPMOST,
            0, 0, 0, 0,
            SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
            SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
            SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE |
            SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED
        );
    }

    /// <summary>
    /// Updates geometry when display parameters or resolutions change.
    /// </summary>
    public void RefreshDisplayBounds()
    {
        UpdateVirtualScreenBounds();
        if (_hwnd != HWND.Null)
        {
            PInvoke.SetWindowPos(
                _hwnd,
                HWND.HWND_TOPMOST,
                _virtualBounds.X,
                _virtualBounds.Y,
                _virtualBounds.Width,
                _virtualBounds.Height,
                SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE | SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW
            );
        }
    }

    private LRESULT WndProc(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam)
    {
        switch (msg)
        {
            case PInvoke.WM_MOUSEACTIVATE:
                // MA_NOACTIVATE (3): Never steal focus from active application
                return new LRESULT(3);

            case PInvoke.WM_MOUSEMOVE:
                if (_currentTool != InteractiveTool.None)
                {
                    int x = (short)(lParam.Value & 0xFFFF);
                    int y = (short)((lParam.Value >> 16) & 0xFFFF);
                    var pt = new Point(x, y);

                    if ((wParam.Value & 0x0001) != 0) // MK_LBUTTON
                    {
                        MouseDragged?.Invoke(pt);
                    }
                    else
                    {
                        MouseMoved?.Invoke(pt);
                    }
                }
                return new LRESULT(0);

            case PInvoke.WM_DISPLAYCHANGE:
                RefreshDisplayBounds();
                return new LRESULT(0);

            case PInvoke.WM_DESTROY:
                _hwnd = HWND.Null;
                return new LRESULT(0);
        }

        return PInvoke.DefWindowProc(hwnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        if (!_isDisposed)
        {
            if (_hwnd != HWND.Null)
            {
                PInvoke.DestroyWindow(_hwnd);
                _hwnd = HWND.Null;
            }
            _isDisposed = true;
        }
    }
}
