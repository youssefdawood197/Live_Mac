namespace Live.Core.Models;

using System;
using System.IO;
using System.Text.Json.Serialization;

/// <summary>
/// Core data model representing an individual wallpaper item in the library.
/// Provides 1:1 cross-platform symmetry with macOS WallpaperItem.swift.
/// </summary>
public record WallpaperItem
{
    [JsonPropertyName("id")]
    public Guid Id { get; init; } = Guid.NewGuid();

    [JsonPropertyName("title")]
    public string Title { get; init; } = string.Empty;

    [JsonPropertyName("type")]
    public WallpaperType Type { get; init; }

    [JsonPropertyName("pathOrURL")]
    public string PathOrUrl { get; init; } = string.Empty;

    [JsonPropertyName("thumbnailPath")]
    public string? ThumbnailPath { get; init; }

    private readonly float _volume = 1.0f;

    [JsonPropertyName("volume")]
    public float Volume
    {
        get => _volume;
        init
        {
            if (float.IsNaN(value)) _volume = 0.0f;
            else if (float.IsPositiveInfinity(value)) _volume = 1.0f;
            else if (float.IsNegativeInfinity(value)) _volume = 0.0f;
            else _volume = Math.Clamp(value, 0.0f, 1.0f);
        }
    }

    [JsonPropertyName("isMuted")]
    public bool IsMuted { get; init; } = true;

    [JsonPropertyName("isInteractive")]
    public bool IsInteractive { get; init; } = false;

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;

    [JsonPropertyName("itemDescription")]
    public string? Description { get; init; }

    [JsonPropertyName("author")]
    public string? Author { get; init; }

    [JsonPropertyName("license")]
    public string? License { get; init; }

    [JsonPropertyName("previewPath")]
    public string? PreviewPath { get; init; }

    [JsonPropertyName("isBundled")]
    public bool IsBundled { get; init; } = false;

    // Parameterless constructor for JSON deserialization
    public WallpaperItem() { }

    public WallpaperItem(
        Guid id,
        string title,
        WallpaperType type,
        string pathOrUrl,
        string? thumbnailPath = null,
        float volume = 1.0f,
        bool isMuted = true,
        bool isInteractive = false,
        DateTime createdAt = default,
        string? description = null,
        string? author = null,
        string? license = null,
        string? previewPath = null,
        bool isBundled = false)
    {
        Id = id == default ? Guid.NewGuid() : id;
        Title = title;
        Type = type;
        PathOrUrl = pathOrUrl;
        ThumbnailPath = thumbnailPath;
        Volume = volume;
        IsMuted = isMuted;
        IsInteractive = isInteractive;
        CreatedAt = createdAt == default ? DateTime.UtcNow : createdAt;
        Description = description;
        Author = author;
        License = license;
        PreviewPath = previewPath;
        IsBundled = isBundled;
    }

    [JsonIgnore]
    public bool FileExists
    {
        get
        {
            if (Type == WallpaperType.Url) return true;
            return !string.IsNullOrWhiteSpace(PathOrUrl) && File.Exists(PathOrUrl);
        }
    }
}
