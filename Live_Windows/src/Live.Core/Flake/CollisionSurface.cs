namespace Live.Core.Flake;

using System;
using System.Drawing;

/// <summary>
/// Represents a horizontal collision ledge where falling snowflakes accumulate.
/// Matches macOS CollisionSurface.swift with Id=0 designating display bottom.
/// </summary>
public readonly record struct CollisionSurface(
    ulong Id,
    Rectangle Frame,
    int TopEdgeY,
    int MinX,
    int MaxX,
    bool IsTaskbar = false
)
{
    public int Width => Math.Max(0, MaxX - MinX);
    public bool ContainsX(int x) => x >= MinX && x <= MaxX;
}
