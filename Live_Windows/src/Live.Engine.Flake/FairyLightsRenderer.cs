namespace Live.Engine.Flake;

using System;
using System.Collections.Generic;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Windows.UI;
using Live.Core.Flake;

public sealed class FairyLightsRenderer
{
    private static readonly Color[] Palette =
    [
        Color.FromArgb(255, 255, 215, 0),   // Warm Gold
        Color.FromArgb(255, 235, 50, 50),    // Holiday Red
        Color.FromArgb(255, 46, 204, 113),   // Emerald Green
        Color.FromArgb(255, 52, 152, 219),   // Ice Blue
        Color.FromArgb(255, 230, 126, 34)    // Sunset Orange
    ];

    private double _time;

    public void Update(float dt) => _time += dt;

    public void Draw(
        CanvasDrawingSession ds,
        FlakeConfiguration config,
        IReadOnlyDictionary<ulong, CollisionSurface> surfaces)
    {
        if (!config.FairyLightsEnabled) return;

        foreach (var (id, surface) in surfaces)
        {
            // Only decorate application window ledges, not screen bottom
            if (id == 0 || surface.Width < 50) continue;

            float spacing = 28.0f;
            int count = (int)(surface.Width / spacing);
            float startX = surface.MinX + (surface.Width - count * spacing) / 2.0f;
            float wireY = surface.TopEdgeY - 2.0f;

            // Draw dark wire along top edge
            ds.DrawLine(
                new Vector2(surface.MinX, wireY),
                new Vector2(surface.MaxX, wireY),
                Color.FromArgb(180, 40, 50, 40),
                1.5f
            );

            for (int i = 0; i <= count; i++)
            {
                float x = startX + i * spacing;
                float bulbY = wireY + 4.0f + (float)Math.Sin(i * 0.8) * 1.5f;

                Color baseColor = Palette[i % Palette.Length];

                // Twinkling pulsation sine wave
                float phase = i * 0.618f;
                float glowAlpha = (float)(0.6 + 0.4 * Math.Sin(_time * 3.0 + phase));

                // Outer glow
                var glowColor = Color.FromArgb((byte)(glowAlpha * 80), baseColor.R, baseColor.G, baseColor.B);
                ds.FillCircle(new Vector2(x, bulbY), 6.0f, glowColor);

                // Bulb core
                var coreColor = Color.FromArgb((byte)(glowAlpha * 255), baseColor.R, baseColor.G, baseColor.B);
                ds.FillCircle(new Vector2(x, bulbY), 2.5f, coreColor);
            }
        }
    }
}
