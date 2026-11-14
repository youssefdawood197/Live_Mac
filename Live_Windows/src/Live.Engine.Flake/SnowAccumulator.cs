namespace Live.Engine.Flake;

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Geometry;
using Windows.UI;
using Live.Core.Flake;

public sealed class SnowAccumulator : IDisposable
{
    private readonly Dictionary<ulong, float[]> _heightmaps = new();
    private readonly Dictionary<ulong, CollisionSurface> _activeSurfaces = new();
    private readonly Dictionary<ulong, Point> _lastWindowPositions = new();

    public IReadOnlyDictionary<ulong, CollisionSurface> ActiveSurfaces => _activeSurfaces;
    public IReadOnlyDictionary<ulong, float[]> Heightmaps => _heightmaps;

    public void UpdateSurfaces(IReadOnlyList<CollisionSurface> surfaces, FlakeConfiguration config)
    {
        var currentIds = new HashSet<ulong>();

        foreach (var surface in surfaces)
        {
            currentIds.Add(surface.Id);
            int binCount = Math.Max(1, surface.Width / 10);

            if (_lastWindowPositions.TryGetValue(surface.Id, out Point lastPos))
            {
                int dx = surface.Frame.Left - lastPos.X;
                int dy = surface.Frame.Top - lastPos.Y;
                double dist = Math.Sqrt(dx * dx + dy * dy);

                // Fast move (> 50px) or window snapped: Avalanche release!
                if (dist > 50.0)
                {
                    _heightmaps.Remove(surface.Id);
                }
            }
            _lastWindowPositions[surface.Id] = new Point(surface.Frame.Left, surface.Frame.Top);

            if (!_heightmaps.ContainsKey(surface.Id) || _heightmaps[surface.Id].Length != binCount)
            {
                _heightmaps[surface.Id] = new float[binCount];
            }

            _activeSurfaces[surface.Id] = surface;
        }

        // Clean up closed windows
        var toRemove = new List<ulong>();
        foreach (var id in _heightmaps.Keys)
        {
            if (!currentIds.Contains(id)) toRemove.Add(id);
        }
        foreach (var id in toRemove)
        {
            _heightmaps.Remove(id);
            _activeSurfaces.Remove(id);
            _lastWindowPositions.Remove(id);
        }
    }

    public bool TryDepositSnow(float x, float y, float amount)
    {
        foreach (var (id, surface) in _activeSurfaces)
        {
            if (!surface.ContainsX((int)x)) continue;

            var bins = _heightmaps[id];
            int binIndex = Math.Clamp((int)((x - surface.MinX) / 10), 0, bins.Length - 1);

            // In Windows Win2D, Y grows downward. Ledge top is TopEdgeY.
            // Snow accumulation mounds upward (TopEdgeY - bins[binIndex]).
            float currentTop = surface.TopEdgeY - bins[binIndex];

            if (Math.Abs(y - currentTop) <= 6.0f)
            {
                float maxCap = surface.Id == 0 ? 50.0f : 22.0f;
                bins[binIndex] = Math.Min(maxCap, bins[binIndex] + amount);
                return true;
            }
        }
        return false;
    }

    public void SimulateAccumulation(float dt, FlakeConfiguration config)
    {
        float rate = config.Intensity.GetBirthRate() * 0.00035f;

        foreach (var (id, surface) in _activeSurfaces)
        {
            var bins = _heightmaps[id];
            float maxCap = surface.Id == 0 ? 50.0f : 22.0f;

            // Natural steady accumulation
            for (int i = 0; i < bins.Length; i++)
            {
                if (bins[i] < maxCap)
                {
                    bins[i] = Math.Min(maxCap, bins[i] + rate * (0.8f + (float)Random.Shared.NextDouble() * 0.4f));
                }
            }

            // 3-Point Angle-of-Repose Smoothing Convolution
            ApplyAngleOfReposeSmoothing(bins);
        }
    }

    public static void ApplyAngleOfReposeSmoothing(float[] bins)
    {
        if (bins.Length > 2)
        {
            float[] smoothed = new float[bins.Length];
            smoothed[0] = (2.0f * bins[0] + bins[1]) / 3.0f;
            smoothed[^1] = (bins[^2] + 2.0f * bins[^1]) / 3.0f;

            for (int i = 1; i < bins.Length - 1; i++)
            {
                smoothed[i] = (bins[i - 1] + 2.0f * bins[i] + bins[i + 1]) / 4.0f;
            }
            Array.Copy(smoothed, bins, bins.Length);
        }
    }

    public float GetBottomAverageDepth()
    {
        if (_heightmaps.TryGetValue(0, out var bins) && bins.Length > 0)
        {
            float sum = 0;
            for (int i = 0; i < bins.Length; i++) sum += bins[i];
            return sum / bins.Length;
        }
        return 0;
    }

    public void ClearBottomBinsUpTo(float x)
    {
        if (_heightmaps.TryGetValue(0, out var bins) && _activeSurfaces.TryGetValue(0, out var surface))
        {
            int maxBin = Math.Clamp((int)((x - surface.MinX) / 10), 0, bins.Length);
            for (int i = 0; i < maxBin; i++)
            {
                bins[i] = 0;
            }
        }
    }

    public void ClearAtCursor(Point cursor, float radius)
    {
        foreach (var (id, surface) in _activeSurfaces)
        {
            if (Math.Abs(cursor.Y - surface.TopEdgeY) > radius + 20) continue;

            var bins = _heightmaps[id];
            for (int i = 0; i < bins.Length; i++)
            {
                float binX = surface.MinX + i * 10.0f + 5.0f;
                if (Math.Abs(cursor.X - binX) < radius)
                {
                    bins[i] = Math.Max(0.0f, bins[i] - 12.0f);
                }
            }
        }
    }

    public void ClearAll()
    {
        foreach (var bins in _heightmaps.Values)
        {
            Array.Clear(bins, 0, bins.Length);
        }
    }

    public void Draw(CanvasDrawingSession ds)
    {
        foreach (var (id, surface) in _activeSurfaces)
        {
            var bins = _heightmaps[id];
            if (bins.Length == 0) continue;

            using var pb = new CanvasPathBuilder(ds);
            pb.BeginFigure(surface.MinX, surface.TopEdgeY);

            for (int i = 0; i < bins.Length; i++)
            {
                float x = surface.MinX + i * 10.0f + 5.0f;
                float y = surface.TopEdgeY - bins[i]; // Mounds upward into negative Y
                pb.AddLine(x, y);
            }

            pb.AddLine(surface.MaxX, surface.TopEdgeY);
            pb.EndFigure(CanvasFigureLoop.Closed);

            using var geometry = CanvasGeometry.CreatePath(pb);
            ds.FillGeometry(geometry, Color.FromArgb(235, 255, 255, 255));
            ds.DrawGeometry(geometry, Color.FromArgb(100, 255, 255, 255), 1.0f);
        }
    }

    public void Dispose()
    {
        _heightmaps.Clear();
        _activeSurfaces.Clear();
        _lastWindowPositions.Clear();
    }
}
