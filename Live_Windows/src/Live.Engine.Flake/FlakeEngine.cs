namespace Live.Engine.Flake;

using System;
using System.Drawing;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Windows.UI;
using Live.Core.Flake;
using Live.Core.Interfaces;
using Live.Core.Power;

public sealed class FlakeEngine : IDisposable
{
    private readonly IWindowSurfaceDetector _surfaceDetector;
    private readonly IPowerManager _powerManager;
    private readonly CanvasAnimatedControl _canvasControl;

    private readonly SnowParticleEmitter _particleEmitter;
    private readonly SnowAccumulator _accumulator;
    private readonly SnowplowAnimator _snowplow;
    private readonly FairyLightsRenderer _fairyLights;

    private FlakeConfiguration _config = new();
    private Rectangle _virtualBounds;
    private double _lastSurfacePollTime;

    public SnowParticleEmitter ParticleEmitter => _particleEmitter;
    public SnowAccumulator Accumulator => _accumulator;
    public SnowplowAnimator Snowplow => _snowplow;
    public FairyLightsRenderer FairyLights => _fairyLights;

    public FlakeEngine(
        CanvasAnimatedControl canvasControl,
        IWindowSurfaceDetector surfaceDetector,
        IPowerManager powerManager,
        Rectangle virtualBounds)
    {
        _canvasControl = canvasControl;
        _surfaceDetector = surfaceDetector;
        _powerManager = powerManager;
        _virtualBounds = virtualBounds;

        _particleEmitter = new SnowParticleEmitter(virtualBounds);
        _accumulator = new SnowAccumulator();
        _snowplow = new SnowplowAnimator(virtualBounds);
        _fairyLights = new FairyLightsRenderer();

        _canvasControl.Update += OnCanvasUpdate;
        _canvasControl.Draw += OnCanvasDraw;

        _powerManager.PauseStateChanged += OnPauseStateChanged;
    }

    public void ApplyConfiguration(FlakeConfiguration config)
    {
        _config = config;
        _particleEmitter.UpdateConfiguration(config);
        _canvasControl.Paused = !config.IsEnabled || _powerManager.IsPaused;

        if (!config.IsEnabled)
        {
            _accumulator.ClearAll();
            _snowplow.Reset();
        }
    }

    public void UpdateBounds(Rectangle newBounds)
    {
        _virtualBounds = newBounds;
        _particleEmitter.UpdateBounds(newBounds);
        _snowplow.UpdateBounds(newBounds);
    }

    private void OnPauseStateChanged(object? sender, PauseReasons reasons)
    {
        bool shouldPause = (reasons != PauseReasons.None) || !_config.IsEnabled;
        _canvasControl.Paused = shouldPause;
    }

    private void OnCanvasUpdate(ICanvasAnimatedControl sender, CanvasAnimatedUpdateEventArgs args)
    {
        if (!_config.IsEnabled || _powerManager.IsPaused) return;

        double currentTime = args.TotalTime.TotalSeconds;
        float dt = (float)args.Time.ElapsedStepTime.TotalSeconds;

        // 1. Throttle window ledge polling to 10 Hz (every 100ms)
        if (currentTime - _lastSurfacePollTime >= 0.10)
        {
            _lastSurfacePollTime = currentTime;
            var surfaces = _surfaceDetector.DetectSurfaces(_virtualBounds, _config);
            _accumulator.UpdateSurfaces(surfaces, _config);
        }

        // 2. Step 60 Hz physics
        _particleEmitter.Update(dt, _accumulator);
        _accumulator.SimulateAccumulation(dt, _config);
        _snowplow.Update(dt, _accumulator, _config);
        _fairyLights.Update(dt);
    }

    private void OnCanvasDraw(ICanvasAnimatedControl sender, CanvasAnimatedDrawEventArgs args)
    {
        if (!_config.IsEnabled || _powerManager.IsPaused) return;

        var ds = args.DrawingSession;
        ds.Clear(Color.FromArgb(0, 0, 0, 0)); // Transparent swapchain background

        _particleEmitter.Draw(ds);
        _accumulator.Draw(ds);
        _fairyLights.Draw(ds, _config, _accumulator.ActiveSurfaces);
        _snowplow.Draw(ds);
    }

    public void Dispose()
    {
        _canvasControl.Update -= OnCanvasUpdate;
        _canvasControl.Draw -= OnCanvasDraw;
        _powerManager.PauseStateChanged -= OnPauseStateChanged;
        _particleEmitter.Dispose();
        _accumulator.Dispose();
    }
}
