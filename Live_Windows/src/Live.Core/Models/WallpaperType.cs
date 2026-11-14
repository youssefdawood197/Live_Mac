namespace Live.Core.Models;

using System;
using System.Text.Json.Serialization;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum WallpaperType
{
    [JsonPropertyName("video")]
    Video,

    [JsonPropertyName("web")]
    Web,

    [JsonPropertyName("url")]
    Url
}

public static class WallpaperTypeExtensions
{
    public static string GetDisplayName(this WallpaperType type) => type switch
    {
        WallpaperType.Video => "Video",
        WallpaperType.Web => "Web Page",
        WallpaperType.Url => "Web URL",
        _ => "Unknown"
    };

    public static string GetIconGlyph(this WallpaperType type) => type switch
    {
        WallpaperType.Video => "\uE714", // Video icon
        WallpaperType.Web => "\uE774",   // Globe / Web icon
        WallpaperType.Url => "\uE71B",   // Link icon
        _ => "\uE7C3"
    };

    public static bool IsWebBased(this WallpaperType type) =>
        type is WallpaperType.Web or WallpaperType.Url;

    public static bool SupportsAudio(this WallpaperType type) =>
        type is WallpaperType.Video or WallpaperType.Web;

    public static bool SupportsInteraction(this WallpaperType type) =>
        type is WallpaperType.Web or WallpaperType.Url;

    public static WallpaperType? FromExtension(string extension)
    {
        string clean = extension.TrimStart('.').ToLowerInvariant();
        return clean switch
        {
            "mp4" or "mov" or "m4v" or "webm" or "avi" or "mkv" => WallpaperType.Video,
            "html" or "htm" or "zip" or "lively" => WallpaperType.Web,
            _ => null
        };
    }
}
