using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using LivelyWallpaper.Windows.Physics;

namespace LivelyWallpaper.Windows.Core;

/// <summary>
/// A transparent, borderless overlay window on Windows providing 100% click-through
/// event transparency for falling snowflakes and physical window snowdrifts.
/// </summary>
public sealed class FlakeOverlayWindow : Form
{
    private const int WS_EX_LAYERED = 0x80000;
    private const int WS_EX_TRANSPARENT = 0x20;
    private const int WS_EX_TOOLWINDOW = 0x80;
    private const int WS_EX_TOPMOST = 0x8;

    private readonly FlakeConfiguration _config;
    private readonly WindowSurfaceDetector _surfaceDetector;

    public FlakeOverlayWindow(Rectangle screenBounds, FlakeConfiguration config)
    {
        _config = config;
        _surfaceDetector = new WindowSurfaceDetector();

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Bounds = screenBounds;
        BackColor = Color.Black;
        TransparencyKey = Color.Black;
        TopMost = true;

        SetStyle(ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.UserPaint |
                 ControlStyles.Opaque, true);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED;
            cp.ExStyle |= WS_EX_TOOLWINDOW;
            cp.ExStyle |= WS_EX_TOPMOST;

            // When no interactive tool is selected, enable 100% click-through
            if (_config.ActiveTool == InteractiveTool.None)
            {
                cp.ExStyle |= WS_EX_TRANSPARENT;
            }

            return cp;
        }
    }

    /// <summary>
    /// Refreshes click-through state when switching interactive tools.
    /// </summary>
    public void UpdateClickThroughState()
    {
        RecreateHandle();
    }
}
