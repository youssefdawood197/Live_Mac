namespace Live.Engine.Flake;

using System;
using System.Drawing;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Windows.UI;
using Live.Core.Flake;

public sealed class SnowParticleEmitter : IDisposable
{
    public struct SnowParticle
    {
        public Vector2 Position;
        public Vector2 Velocity;
        public float Radius;
        public float Opacity;
        public float WobblePhase;
        public float WobbleSpeed;
        public bool IsActive;
    }

    private const int MaxPoolSize = 1000;
    private readonly SnowParticle[] _particles = new SnowParticle[MaxPoolSize];
    private readonly Random _rng = new();
    private Rectangle _bounds;
    private WindVector _wind;
    private int _targetParticleCount;

    public int ActiveParticleCount => _targetParticleCount;
    public ReadOnlySpan<SnowParticle> Particles => _particles.AsSpan(0, _targetParticleCount);

    public SnowParticleEmitter(Rectangle virtualBounds)
    {
        _bounds = virtualBounds;
        InitializePool();
    }

    private void InitializePool()
    {
        for (int i = 0; i < MaxPoolSize; i++)
        {
            ResetParticle(ref _particles[i], initialSpawn: true);
            _particles[i].IsActive = false;
        }
    }

    private void ResetParticle(ref SnowParticle p, bool initialSpawn)
    {
        float x = _rng.Next(_bounds.Left - 100, _bounds.Right + 100);
        float y = initialSpawn ? _rng.Next(_bounds.Top - 50, _bounds.Bottom) : _bounds.Top - 20;

        p.Position = new Vector2(x, y);
        p.Radius = (float)(_rng.NextDouble() * 2.5 + 1.0); // 1.0 to 3.5 px
        p.Opacity = (float)(_rng.NextDouble() * 0.45 + 0.50); // 0.5 to 0.95
        p.WobblePhase = (float)(_rng.NextDouble() * Math.PI * 2.0);
        p.WobbleSpeed = (float)(_rng.NextDouble() * 3.0 + 1.5);
        p.Velocity = new Vector2(0, (float)(_rng.NextDouble() * 20.0 + 40.0));
        p.IsActive = true;
    }

    public void UpdateConfiguration(FlakeConfiguration config)
    {
        _targetParticleCount = config.Intensity.GetMaxParticles();
        _wind = new WindVector(config.WindAngleDegrees, config.WindSpeed);
    }

    public void UpdateBounds(Rectangle newBounds)
    {
        _bounds = newBounds;
    }

    public void Update(float dt, SnowAccumulator accumulator)
    {
        for (int i = 0; i < MaxPoolSize; i++)
        {
            if (i >= _targetParticleCount)
            {
                _particles[i].IsActive = false;
                continue;
            }

            if (!_particles[i].IsActive)
            {
                ResetParticle(ref _particles[i], initialSpawn: false);
            }

            ref var p = ref _particles[i];

            // Apply wind acceleration
            p.Velocity.X += _wind.ForceX * dt * 0.5f;
            p.Velocity.Y = Math.Clamp(p.Velocity.Y + _wind.ForceY * dt * 0.2f, 20.0f, 350.0f);

            // Sinusoidal horizontal fluttering
            p.WobblePhase += p.WobbleSpeed * dt;
            float flutter = (float)Math.Sin(p.WobblePhase) * 18.0f * dt;

            p.Position.X += p.Velocity.X * dt + flutter;
            p.Position.Y += p.Velocity.Y * dt;

            // Check collision with accumulator ledges
            if (accumulator.TryDepositSnow(p.Position.X, p.Position.Y, p.Radius * 0.4f))
            {
                ResetParticle(ref p, initialSpawn: false);
                continue;
            }

            // Recycle off-screen particles
            if (p.Position.Y > _bounds.Bottom + 20 ||
                p.Position.X < _bounds.Left - 200 ||
                p.Position.X > _bounds.Right + 200)
            {
                ResetParticle(ref p, initialSpawn: false);
            }
        }
    }

    public void Draw(CanvasDrawingSession ds)
    {
        for (int i = 0; i < _targetParticleCount; i++)
        {
            if (!_particles[i].IsActive) continue;
            ref readonly var p = ref _particles[i];

            byte alpha = (byte)(p.Opacity * 255.0f);
            var color = Color.FromArgb(alpha, 255, 255, 255);
            ds.FillCircle(p.Position, p.Radius, color);
        }
    }

    public void Dispose() { }
}
