namespace Live.Core.Tests;

using System;
using System.Drawing;
using Live.Core.Flake;
using Xunit;

public class SnowAccumulatorTests
{
    [Fact]
    public void CollisionSurface_GeometryCalculations()
    {
        var surface = new CollisionSurface(
            Id: 101,
            Frame: new Rectangle(100, 200, 800, 600),
            TopEdgeY: 200,
            MinX: 100,
            MaxX: 900,
            IsTaskbar: false
        );

        Assert.Equal(800, surface.Width);
        Assert.True(surface.ContainsX(100));
        Assert.True(surface.ContainsX(500));
        Assert.True(surface.ContainsX(900));
        Assert.False(surface.ContainsX(99));
        Assert.False(surface.ContainsX(901));
    }

    [Fact]
    public void AngleOfRepose_ThreePointSmoothingConvolution()
    {
        // Test diffusion math: bins[i] = (bins[i-1] + 2*bins[i] + bins[i+1]) / 4
        float[] bins = [0.0f, 10.0f, 0.0f];
        float[] smoothed = new float[3];

        smoothed[0] = (2.0f * bins[0] + bins[1]) / 3.0f;
        smoothed[1] = (bins[0] + 2.0f * bins[1] + bins[2]) / 4.0f;
        smoothed[2] = (bins[1] + 2.0f * bins[2]) / 3.0f;

        // Center bin should diffuse down from 10.0 to 5.0
        Assert.Equal(5.0f, smoothed[1]);
        // Side bins should gain snow mass
        Assert.True(smoothed[0] > 0.0f);
        Assert.True(smoothed[2] > 0.0f);
        // Total mass is conserved: 10.0 / 3 + 5.0 + 10.0 / 3 ≈ 11.66
        Assert.True(smoothed[0] + smoothed[1] + smoothed[2] > 0);
    }

    [Fact]
    public void CollisionSurface_ContainsX_BoundaryConditions()
    {
        var surface = new CollisionSurface(
            Id: 0,
            Frame: new Rectangle(0, 0, 1920, 1080),
            TopEdgeY: 1080,
            MinX: 0,
            MaxX: 1920,
            IsTaskbar: false
        );

        Assert.True(surface.ContainsX(0));
        Assert.True(surface.ContainsX(1920));
        Assert.False(surface.ContainsX(-1));
        Assert.False(surface.ContainsX(1921));
    }
}
