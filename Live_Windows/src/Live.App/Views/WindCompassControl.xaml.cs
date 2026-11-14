namespace Live.App.Views;

using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;

public sealed partial class WindCompassControl : UserControl
{
    public static readonly DependencyProperty WindAngleDegreesProperty =
        DependencyProperty.Register(
            nameof(WindAngleDegrees),
            typeof(double),
            typeof(WindCompassControl),
            new PropertyMetadata(90.0, OnWindAngleChanged));

    public static readonly DependencyProperty WindSpeedProperty =
        DependencyProperty.Register(
            nameof(WindSpeed),
            typeof(double),
            typeof(WindCompassControl),
            new PropertyMetadata(1.0));

    public double WindAngleDegrees
    {
        get => (double)GetValue(WindAngleDegreesProperty);
        set => SetValue(WindAngleDegreesProperty, value);
    }

    public double WindSpeed
    {
        get => (double)GetValue(WindSpeedProperty);
        set => SetValue(WindSpeedProperty, value);
    }

    public WindCompassControl()
    {
        InitializeComponent();
        UpdateNeedle(WindAngleDegrees);
    }

    private static void OnWindAngleChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is WindCompassControl control && e.NewValue is double angle)
        {
            control.UpdateNeedle(angle);
        }
    }

    private void AngleSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        UpdateNeedle(e.NewValue);
    }

    private void UpdateNeedle(double angleDegrees)
    {
        if (NeedleLine == null) return;

        double rad = angleDegrees * Math.PI / 180.0;
        double radius = 45.0;
        double centerX = 70.0;
        double centerY = 70.0;

        // Polar to Cartesian
        NeedleLine.X2 = centerX + radius * Math.Cos(rad - Math.PI / 2.0);
        NeedleLine.Y2 = centerY + radius * Math.Sin(rad - Math.PI / 2.0);
    }
}
