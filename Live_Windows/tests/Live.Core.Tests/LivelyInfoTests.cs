namespace Live.Core.Tests;

using System;
using Live.Core.Models;
using Xunit;

public class LivelyInfoTests
{
    private const string SampleVideoJson = """
    {
      "AppVersion": "2.0.0.0",
      "Title": "Sunset Beach",
      "Thumbnail": "sunset_thumb.jpg",
      "Preview": "sunset_preview.gif",
      "Desc": "Relaxing looping waves at sunset",
      "Author": "LiveTeam",
      "License": "MIT",
      "Contact": "https://github.com/livewallpaper",
      "Type": 2,
      "FileName": "sunset.mp4",
      "Arguments": null,
      "IsAbsolutePath": false
    }
    """;

    private const string SampleWebJson = """
    {
      "AppVersion": "2.0.0.0",
      "Title": "Matrix Digital Rain",
      "Thumbnail": "matrix_thumb.jpg",
      "Preview": null,
      "Desc": "Green falling digital rain canvas",
      "Author": "LiveTeam",
      "License": "MIT",
      "Contact": null,
      "Type": "Web",
      "FileName": "index.html",
      "Arguments": null,
      "IsAbsolutePath": false
    }
    """;

    [Fact]
    public void Parse_OfficialJsonSchema_CorrectlyMapsProperties()
    {
        var info = LivelyInfo.Parse(SampleVideoJson);

        Assert.Equal("2.0.0.0", info.AppVersion);
        Assert.Equal("Sunset Beach", info.Title);
        Assert.Equal("sunset_thumb.jpg", info.Thumbnail);
        Assert.Equal("sunset_preview.gif", info.Preview);
        Assert.Equal("Relaxing looping waves at sunset", info.Desc);
        Assert.Equal("LiveTeam", info.Author);
        Assert.Equal(LivelyWallpaperType.Video, info.Type);
        Assert.Equal("sunset.mp4", info.FileName);
        Assert.Equal(WallpaperType.Video, info.NativeWallpaperType);
    }

    [Fact]
    public void MakeWallpaperItem_PreservesMetadataAndResolvesPaths()
    {
        var info = LivelyInfo.Parse(SampleVideoJson);
        string folder = "C:\\Wallpapers\\Sunset";
        var item = info.MakeWallpaperItem(folder);

        Assert.Equal("Sunset Beach", item.Title);
        Assert.Equal(WallpaperType.Video, item.Type);
        Assert.Equal("C:\\Wallpapers\\Sunset\\sunset.mp4", item.PathOrUrl);
        Assert.Equal("C:\\Wallpapers\\Sunset\\sunset_thumb.jpg", item.ThumbnailPath);
        Assert.Equal("Relaxing looping waves at sunset", item.Description);
        Assert.Equal("LiveTeam", item.Author);
        Assert.False(item.IsInteractive);
    }

    [Fact]
    public void PolymorphicTypeConverter_HandlesIntegerAndStringTypes()
    {
        var webInfo = LivelyInfo.Parse(SampleWebJson);
        Assert.Equal(LivelyWallpaperType.Web, webInfo.Type);
        Assert.Equal(WallpaperType.Web, webInfo.NativeWallpaperType);

        var webItem = webInfo.MakeWallpaperItem();
        Assert.True(webItem.IsInteractive);
    }
}
