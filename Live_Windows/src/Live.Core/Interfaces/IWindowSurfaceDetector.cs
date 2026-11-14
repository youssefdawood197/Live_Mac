namespace Live.Core.Interfaces;

using System.Collections.Generic;
using System.Drawing;
using Live.Core.Flake;

/// <summary>
/// Contract for querying visible application window ledges and taskbar surfaces for snow accumulation.
/// </summary>
public interface IWindowSurfaceDetector
{
    IReadOnlyList<CollisionSurface> DetectSurfaces(Rectangle virtualScreenBounds, FlakeConfiguration? config = null);
}
