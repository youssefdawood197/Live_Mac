namespace Live.Engine.Flake;

using System;
using System.Drawing;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Windows.Foundation;
using Windows.UI;
using Live.Core.Flake;

public sealed class SnowplowAnimator
{
    private Rectangle _bounds;
    private bool _isActive;
    private float _currentX;
    private const float TraversalSpeed = 450.0f; // px/second across screen

    public bool IsActive => _isActive;
    public float CurrentX => _currentX;

    public SnowplowAnimator(Rectangle bounds)
    {
        _bounds = bounds;
    }

    public void UpdateBounds(Rectangle newBounds)
    {
        _bounds = newBounds;
    }

    public void Update(float dt, SnowAccumulator accumulator, FlakeConfiguration config)
    {
        if (!config.SnowplowEnabled) return;

        if (!_isActive && accumulator.GetBottomAverageDepth() > 32.0f)
        {
            _isActive = true;
            _currentX = _bounds.Left - 80;
        }

        if (_isActive)
        {
            _currentX += TraversalSpeed * dt;
            accumulator.ClearBottomBinsUpTo(_currentX + 30);

            if (_currentX > _bounds.Right + 80)
            {
                _isActive = false;
            }
        }
    }

    public void Reset() => _isActive = false;

    public void Draw(CanvasDrawingSession ds)
    {
        if (!_isActive) return;

        float y = _bounds.Bottom - 18;
        // Draw Classic Tractor Vehicle
        ds.FillRoundedRectangle(new Rect(_currentX, y - 24, 44, 24), 4, 4, Colors.Gold);
        ds.FillRoundedRectangle(new Rect(_currentX + 6, y - 36, 20, 14), 2, 2, Colors.CornflowerBlue);
        ds.FillRectangle(new Rect(_currentX + 38, y - 28, 8, 28), Colors.DimGray); // Blade
        ds.FillCircle(new Vector2(_currentX + 10, y), 8, Colors.DarkSlateGray); // Wheel 1
        ds.FillCircle(new Vector2(_currentX + 32, y), 8, Colors.DarkSlateGray); // Wheel 2
    }
}
