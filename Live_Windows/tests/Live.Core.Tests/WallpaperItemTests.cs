namespace Live.Core.Tests;

using System;
using Live.Core.Models;
using Xunit;

public class WallpaperItemTests
{
    [Fact]
    public void Volume_DefensivelyClampsValuesAndHandlesNaN()
    {
        var item1 = new WallpaperItem { Volume = 1.5f };
        Assert.Equal(1.0f, item1.Volume);

        var item2 = new WallpaperItem { Volume = -0.5f };
        Assert.Equal(0.0f, item2.Volume);

        var item3 = new WallpaperItem { Volume = float.NaN };
        Assert.Equal(0.0f, item3.Volume);

        var item4 = new WallpaperItem { Volume = float.PositiveInfinity };
        Assert.Equal(1.0f, item4.Volume);

        var item5 = new WallpaperItem { Volume = float.NegativeInfinity };
        Assert.Equal(0.0f, item5.Volume);

        var item6 = new WallpaperItem { Volume = 0.65f };
        Assert.Equal(0.65f, item6.Volume);
    }

    [Fact]
    public void WallpaperTypeExtensions_ReturnsCorrectProperties()
    {
        Assert.True(WallpaperType.Video.SupportsAudio());
        Assert.False(WallpaperType.Video.IsWebBased());
        Assert.False(WallpaperType.Video.SupportsInteraction());

        Assert.True(WallpaperType.Web.SupportsAudio());
        Assert.True(WallpaperType.Web.IsWebBased());
        Assert.True(WallpaperType.Web.SupportsInteraction());

        Assert.True(WallpaperType.Url.IsWebBased());
        Assert.True(WallpaperType.Url.SupportsInteraction());

        Assert.Equal(WallpaperType.Video, WallpaperTypeExtensions.FromExtension(".mp4"));
        Assert.Equal(WallpaperType.Video, WallpaperTypeExtensions.FromExtension("webm"));
        Assert.Equal(WallpaperType.Web, WallpaperTypeExtensions.FromExtension(".html"));
        Assert.Equal(WallpaperType.Web, WallpaperTypeExtensions.FromExtension("zip"));
        Assert.Null(WallpaperTypeExtensions.FromExtension(".unknown"));
    }

    [Fact]
    public void FileExists_EvaluatesCorrectlyForUrlsAndLocalFiles()
    {
        var urlItem = new WallpaperItem
        {
            Type = WallpaperType.Url,
            PathOrUrl = "https://shadertoy.com/view/4dXGR4"
        };
        // Url items always return true for FileExists without hitting the filesystem
        Assert.True(urlItem.FileExists);

        var nonexistentItem = new WallpaperItem
        {
            Type = WallpaperType.Video,
            PathOrUrl = "C:\\nonexistent_video_path_12345.mp4"
        };
        Assert.False(nonexistentItem.FileExists);
    }
}
