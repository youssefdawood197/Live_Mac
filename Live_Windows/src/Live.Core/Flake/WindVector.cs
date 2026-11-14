namespace Live.Core.Flake;

using System;

/// <summary>
/// Computes trigonometric directional forces for snow particle simulation.
/// Adapts Cocoa coordinate formulas to Windows Win2D (+Y downward) coordinate space.
/// </summary>
public readonly record struct WindVector(double AngleDegrees, double Speed)
{
    public float ForceX { get; }
    public float ForceY { get; }

    public WindVector(double angleDegrees, double speed) : this()
    {
        AngleDegrees = angleDegrees;
        Speed = speed;

        double rad = angleDegrees * Math.PI / 180.0;

        // Horizontal force: 0° = East (+X), 180° = West (-X)
        ForceX = (float)(Math.Cos(rad - Math.PI / 2.0) * speed * 85.0);

        // Vertical force: In Windows Win2D, Y grows DOWNWARD.
        // Therefore, downward falling acceleration has a POSITIVE sign.
        ForceY = (float)(Math.Abs(Math.Sin(rad - Math.PI / 2.0)) * speed * 70.0 + 90.0);
    }
}
