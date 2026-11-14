namespace Live.Interop.Tests;

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using Live.Core.Flake;
using Live.Interop.Win32;
using Xunit;

public class MockWindowInfoProvider : IWindowInfoProvider
{
    public List<RawWindowInfo> Windows { get; set; } = new();
    public List<Rectangle> Monitors { get; set; } = new();

    public IReadOnlyList<RawWindowInfo> EnumerateWindowsInZOrder() => Windows;
    public IReadOnlyList<Rectangle> GetMonitorWorkAreas() => Monitors;
}

public class WindowSurfaceDetectorTests
{
    [Fact]
    public void DetectSurfaces_FiltersCloakedMinimizedAndTinyWindows()
    {
        var mock = new MockWindowInfoProvider
        {
            Monitors = [new Rectangle(0, 0, 1920, 1080)],
            Windows =
            [
                // Normal visible window
                new RawWindowInfo(
                    Handle: 1001,
                    ClassName: "Chrome_WidgetWin_1",
                    Bounds: new Rectangle(100, 100, 800, 600),
                    IsVisible: true,
                    IsIconic: false,
                    IsCloaked: false
                ),
                // Minimized window
                new RawWindowInfo(
                    Handle: 1002,
                    ClassName: "Notepad",
                    Bounds: new Rectangle(0, 0, 400, 300),
                    IsVisible: true,
                    IsIconic: true,
                    IsCloaked: false
                ),
                // Cloaked window (inactive virtual desktop)
                new RawWindowInfo(
                    Handle: 1003,
                    ClassName: "ApplicationFrameWindow",
                    Bounds: new Rectangle(200, 200, 600, 400),
                    IsVisible: true,
                    IsIconic: false,
                    IsCloaked: true
                ),
                // Tiny tooltip / caret window
                new RawWindowInfo(
                    Handle: 1004,
                    ClassName: "tooltips_class32",
                    Bounds: new Rectangle(50, 50, 60, 40),
                    IsVisible: true,
                    IsIconic: false,
                    IsCloaked: false
                ),
                // Shell Desktop Progman
                new RawWindowInfo(
                    Handle: 1005,
                    ClassName: "Progman",
                    Bounds: new Rectangle(0, 0, 1920, 1080),
                    IsVisible: true,
                    IsIconic: false,
                    IsCloaked: false
                ),
                // Windows Taskbar
                new RawWindowInfo(
                    Handle: 1006,
                    ClassName: "Shell_TrayWnd",
                    Bounds: new Rectangle(0, 1040, 1920, 40),
                    IsVisible: true,
                    IsIconic: false,
                    IsCloaked: false
                )
            ]
        };

        var detector = new Win32WindowSurfaceDetector(mock);
        var surfaces = detector.DetectSurfaces(new Rectangle(0, 0, 1920, 1080));

        // Expected surfaces:
        // 1. Ground plane (Id = 0)
        // 2. Normal window (Id = 1001)
        // 3. Taskbar (Id = 1006, IsTaskbar = true)
        Assert.Contains(surfaces, s => s.Id == 0);
        Assert.Contains(surfaces, s => s.Id == 1001);
        Assert.Contains(surfaces, s => s.Id == 1006 && s.IsTaskbar);

        // Minimized (1002), cloaked (1003), tiny (1004), and Progman (1005) must be excluded
        Assert.DoesNotContain(surfaces, s => s.Id == 1002);
        Assert.DoesNotContain(surfaces, s => s.Id == 1003);
        Assert.DoesNotContain(surfaces, s => s.Id == 1004);
        Assert.DoesNotContain(surfaces, s => s.Id == 1005);
    }

    [Fact]
    public void ClipLedgeByOccluders_SplitsWindowLedgeAroundHigherZWindow()
    {
        // Window B: Top ledge from X=100 to X=500 at elevation Y=200
        int startX = 100;
        int endX = 500;
        int topY = 200;

        // Higher-Z Window A: Bounds at (200, 150, width: 100, height: 200) -> [200, 300] covers Y=200
        var occluders = new List<Rectangle>
        {
            new Rectangle(200, 150, 100, 200)
        };

        var visibleSegments = Win32WindowSurfaceDetector.ClipLedgeByOccluders(startX, endX, topY, occluders);

        // Should split into two segments: [100, 200] and [300, 500]
        Assert.Equal(2, visibleSegments.Count);

        Assert.Equal(100, visibleSegments[0].MinX);
        Assert.Equal(200, visibleSegments[0].MaxX);

        Assert.Equal(300, visibleSegments[1].MinX);
        Assert.Equal(500, visibleSegments[1].MaxX);
    }

    [Fact]
    public void ClipLedgeByOccluders_DiscardsTinySliversBelowThreshold()
    {
        // Window ledge from 100 to 130 (width 30px, below 40px threshold)
        int startX = 100;
        int endX = 130;
        int topY = 200;
        var occluders = new List<Rectangle>();

        var visibleSegments = Win32WindowSurfaceDetector.ClipLedgeByOccluders(startX, endX, topY, occluders);

        Assert.Empty(visibleSegments);
    }

    [Fact]
    public void ClipLedgeByOccluders_PassesThroughDisjointLedges()
    {
        int startX = 100;
        int endX = 500;
        int topY = 200;

        // Occluder is completely below the ledge (Y=300 to 500)
        var occluders = new List<Rectangle>
        {
            new Rectangle(150, 300, 200, 200)
        };

        var visibleSegments = Win32WindowSurfaceDetector.ClipLedgeByOccluders(startX, endX, topY, occluders);

        Assert.Single(visibleSegments);
        Assert.Equal(100, visibleSegments[0].MinX);
        Assert.Equal(500, visibleSegments[0].MaxX);
    }
}
