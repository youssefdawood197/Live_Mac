namespace Live.Core.Models;

using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

public enum LivelyWallpaperType
{
    Web = 0,
    WebStream = 1,
    Video = 2,
    Gif = 3,
    Unity = 4,
    Godot = 5,
    VideoStream = 6,
    App = 7,
    Picture = 8,
    Unknown = -1
}

public class LivelyWallpaperTypeConverter : JsonConverter<LivelyWallpaperType>
{
    public override LivelyWallpaperType Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number)
        {
            if (reader.TryGetInt32(out int intVal))
            {
                return Enum.IsDefined(typeof(LivelyWallpaperType), intVal)
                    ? (LivelyWallpaperType)intVal
                    : LivelyWallpaperType.Unknown;
            }
        }
        else if (reader.TokenType == JsonTokenType.String)
        {
            string? strVal = reader.GetString();
            if (strVal != null)
            {
                if (int.TryParse(strVal, out int parsedInt) && Enum.IsDefined(typeof(LivelyWallpaperType), parsedInt))
                {
                    return (LivelyWallpaperType)parsedInt;
                }

                return strVal.Trim().ToLowerInvariant() switch
                {
                    "web" => LivelyWallpaperType.Web,
                    "webstream" => LivelyWallpaperType.WebStream,
                    "video" => LivelyWallpaperType.Video,
                    "gif" => LivelyWallpaperType.Gif,
                    "unity" => LivelyWallpaperType.Unity,
                    "godot" => LivelyWallpaperType.Godot,
                    "videostream" => LivelyWallpaperType.VideoStream,
                    "app" => LivelyWallpaperType.App,
                    "picture" => LivelyWallpaperType.Picture,
                    _ => LivelyWallpaperType.Unknown
                };
            }
        }

        return LivelyWallpaperType.Unknown;
    }

    public override void Write(Utf8JsonWriter writer, LivelyWallpaperType value, JsonSerializerOptions options)
    {
        writer.WriteNumberValue((int)value);
    }
}

public record LivelyInfo
{
    [JsonPropertyName("AppVersion")]
    public string? AppVersion { get; init; }

    [JsonPropertyName("Title")]
    public string Title { get; init; } = string.Empty;

    [JsonPropertyName("Thumbnail")]
    public string? Thumbnail { get; init; }

    [JsonPropertyName("Preview")]
    public string? Preview { get; init; }

    [JsonPropertyName("Desc")]
    public string? Desc { get; init; }

    [JsonPropertyName("Author")]
    public string? Author { get; init; }

    [JsonPropertyName("License")]
    public string? License { get; init; }

    [JsonPropertyName("Contact")]
    public string? Contact { get; init; }

    [JsonPropertyName("Type")]
    [JsonConverter(typeof(LivelyWallpaperTypeConverter))]
    public LivelyWallpaperType Type { get; init; } = LivelyWallpaperType.Unknown;

    [JsonPropertyName("FileName")]
    public string FileName { get; init; } = string.Empty;

    [JsonPropertyName("Arguments")]
    public string? Arguments { get; init; }

    [JsonPropertyName("IsAbsolutePath")]
    public bool? IsAbsolutePath { get; init; }

    public WallpaperType NativeWallpaperType => Type switch
    {
        LivelyWallpaperType.Video or LivelyWallpaperType.Gif => WallpaperType.Video,
        LivelyWallpaperType.Web or LivelyWallpaperType.Picture => WallpaperType.Web,
        LivelyWallpaperType.WebStream or LivelyWallpaperType.VideoStream => WallpaperType.Url,
        _ => WallpaperTypeExtensions.FromExtension(Path.GetExtension(FileName)) ?? WallpaperType.Web
    };

    public WallpaperItem MakeWallpaperItem(string? directoryPath = null)
    {
        bool isAbsolute = IsAbsolutePath == true || Path.IsPathRooted(FileName) ||
                          FileName.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                          FileName.StartsWith("https://", StringComparison.OrdinalIgnoreCase);

        string resolvedPath = isAbsolute || directoryPath == null
            ? FileName
            : Path.Combine(directoryPath, FileName);

        string? resolvedThumbnail = null;
        if (!string.IsNullOrWhiteSpace(Thumbnail))
        {
            resolvedThumbnail = Path.IsPathRooted(Thumbnail) || directoryPath == null
                ? Thumbnail
                : Path.Combine(directoryPath, Thumbnail);
        }

        string? resolvedPreview = null;
        if (!string.IsNullOrWhiteSpace(Preview))
        {
            resolvedPreview = Path.IsPathRooted(Preview) || directoryPath == null
                ? Preview
                : Path.Combine(directoryPath, Preview);
        }

        bool isWeb = NativeWallpaperType is WallpaperType.Web or WallpaperType.Url;

        return new WallpaperItem(
            id: Guid.NewGuid(),
            title: Title,
            type: NativeWallpaperType,
            pathOrUrl: resolvedPath,
            thumbnailPath: resolvedThumbnail,
            volume: 1.0f,
            isMuted: true,
            isInteractive: isWeb,
            createdAt: DateTime.UtcNow,
            description: Desc,
            author: Author,
            license: License,
            previewPath: resolvedPreview,
            isBundled: false
        );
    }

    public static LivelyInfo Parse(string json)
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true
        };
        return JsonSerializer.Deserialize<LivelyInfo>(json, options)
            ?? throw new InvalidOperationException("Failed to parse LivelyInfo JSON.");
    }

    public static LivelyInfo FromDirectory(string directoryPath)
    {
        string[] candidates = ["LivelyInfo.json", "livelyinfo.json", "LIVELYINFO.JSON"];
        foreach (string candidate in candidates)
        {
            string fullPath = Path.Combine(directoryPath, candidate);
            if (File.Exists(fullPath))
            {
                string json = File.ReadAllText(fullPath);
                return Parse(json);
            }
        }
        throw new FileNotFoundException($"No LivelyInfo.json found in directory: {directoryPath}");
    }
}
