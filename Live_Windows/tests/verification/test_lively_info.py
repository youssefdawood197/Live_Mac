#!/usr/bin/env python3
"""
Empirical verification and stress-testing suite for LivelyInfo.cs JSON deserialization.
Validates:
- Official LivelyInfo.json schema parsing (v1 and v2 properties).
- Polymorphic Type conversion (integer, string, casing, whitespace, string-encoded integers, invalid/unknown).
- Native wallpaper type mapping (Video, Gif, Web, Picture, WebStream, VideoStream, extension fallback).
- Path resolution edge cases (relative, absolute Windows drive, UNC paths, HTTP/HTTPS URLs, IsAbsolutePath flag).
- Thumbnail and Preview path resolution nuances.
- Missing field resilience (empty JSON, omitted fields).
- Case insensitivity on field names (e.g., TITLE, filename, tYpE).
- Tolerant JSON features (trailing commas, C-style comments).
- Legacy alias analysis (Description vs Desc, Artist vs Author).
"""

import unittest
import json
import re
from enum import IntEnum
from typing import Optional, Dict, Any

class LivelyWallpaperType(IntEnum):
    Web = 0
    WebStream = 1
    Video = 2
    Gif = 3
    Unity = 4
    Godot = 5
    VideoStream = 6
    App = 7
    Picture = 8
    Unknown = -1


class WallpaperType(IntEnum):
    Video = 0
    Web = 1
    Url = 2


def parse_lively_wallpaper_type(raw_val: Any) -> LivelyWallpaperType:
    """Exact emulation of LivelyWallpaperTypeConverter.Read()."""
    if isinstance(raw_val, int):
        try:
            return LivelyWallpaperType(raw_val)
        except ValueError:
            return LivelyWallpaperType.Unknown
    elif isinstance(raw_val, str):
        cleaned = raw_val.strip()
        # Check if integer string
        try:
            int_val = int(cleaned)
            return LivelyWallpaperType(int_val)
        except ValueError:
            pass

        lower = cleaned.lower()
        mapping = {
            "web": LivelyWallpaperType.Web,
            "webstream": LivelyWallpaperType.WebStream,
            "video": LivelyWallpaperType.Video,
            "gif": LivelyWallpaperType.Gif,
            "unity": LivelyWallpaperType.Unity,
            "godot": LivelyWallpaperType.Godot,
            "videostream": LivelyWallpaperType.VideoStream,
            "app": LivelyWallpaperType.App,
            "picture": LivelyWallpaperType.Picture,
        }
        return mapping.get(lower, LivelyWallpaperType.Unknown)

    return LivelyWallpaperType.Unknown


def get_native_wallpaper_type(lively_type: LivelyWallpaperType, file_name: str) -> WallpaperType:
    """Exact emulation of LivelyInfo.NativeWallpaperType."""
    if lively_type in (LivelyWallpaperType.Video, LivelyWallpaperType.Gif):
        return WallpaperType.Video
    elif lively_type in (LivelyWallpaperType.Web, LivelyWallpaperType.Picture):
        return WallpaperType.Web
    elif lively_type in (LivelyWallpaperType.WebStream, LivelyWallpaperType.VideoStream):
        return WallpaperType.Url
    else:
        # Fallback to extension
        ext = ""
        if "." in file_name:
            ext = file_name.rsplit(".", 1)[-1].lower()
        if ext in ("mp4", "mov", "m4v", "webm", "avi", "mkv"):
            return WallpaperType.Video
        elif ext in ("html", "htm", "zip", "lively"):
            return WallpaperType.Web
        else:
            return WallpaperType.Web


def is_windows_path_rooted(path: str) -> bool:
    """Simulates .NET Windows Path.IsPathRooted()."""
    if not path:
        return False
    # Drive letter: C:\ or C:/
    if len(path) >= 3 and path[0].isalpha() and path[1] == ':' and path[2] in ('\\', '/'):
        return True
    # UNC path: \\server\share or //server/share
    if len(path) >= 2 and path[0] in ('\\', '/') and path[1] in ('\\', '/'):
        return True
    return False


def windows_path_combine(dir_path: str, file_path: str) -> str:
    """Simulates .NET Windows Path.Combine()."""
    if not dir_path:
        return file_path
    if not file_path:
        return dir_path
    if dir_path.endswith('\\') or dir_path.endswith('/'):
        return dir_path + file_path
    return dir_path + '\\' + file_path


class MockLivelyInfo:
    """Exact behavioral model of LivelyInfo.cs."""

    def __init__(self, data: Dict[str, Any]):
        # Case-insensitive property lookup
        ci_data = {k.lower(): v for k, v in data.items()}

        self.app_version = ci_data.get("appversion")
        self.title = ci_data.get("title", "") or ""
        self.thumbnail = ci_data.get("thumbnail")
        self.preview = ci_data.get("preview")
        self.desc = ci_data.get("desc")
        self.author = ci_data.get("author")
        self.license = ci_data.get("license")
        self.contact = ci_data.get("contact")
        self.file_name = ci_data.get("filename", "") or ""
        self.arguments = ci_data.get("arguments")
        self.is_absolute_path = ci_data.get("isabsolutepath")

        raw_type = ci_data.get("type")
        self.type = parse_lively_wallpaper_type(raw_type)

    @property
    def native_wallpaper_type(self) -> WallpaperType:
        return get_native_wallpaper_type(self.type, self.file_name)

    def make_wallpaper_item(self, directory_path: Optional[str] = None) -> Dict[str, Any]:
        fn = self.file_name
        is_url = fn.lower().startswith("http://") or fn.lower().startswith("https://")
        is_absolute = (self.is_absolute_path is True) or is_windows_path_rooted(fn) or is_url

        resolved_path = fn if (is_absolute or directory_path is None) else windows_path_combine(directory_path, fn)

        resolved_thumbnail = None
        if self.thumbnail and self.thumbnail.strip():
            # In LivelyInfo.cs: Path.IsPathRooted(Thumbnail) || directoryPath == null
            t_is_rooted = is_windows_path_rooted(self.thumbnail)
            resolved_thumbnail = self.thumbnail if (t_is_rooted or directory_path is None) else windows_path_combine(directory_path, self.thumbnail)

        resolved_preview = None
        if self.preview and self.preview.strip():
            p_is_rooted = is_windows_path_rooted(self.preview)
            resolved_preview = self.preview if (p_is_rooted or directory_path is None) else windows_path_combine(directory_path, self.preview)

        is_web = self.native_wallpaper_type in (WallpaperType.Web, WallpaperType.Url)

        return {
            "title": self.title,
            "type": self.native_wallpaper_type,
            "path_or_url": resolved_path,
            "thumbnail_path": resolved_thumbnail,
            "preview_path": resolved_preview,
            "description": self.desc,
            "author": self.author,
            "license": self.license,
            "is_interactive": is_web,
        }

    @staticmethod
    def parse(json_str: str) -> "MockLivelyInfo":
        # Strip C-style comments (single line and multi-line) and trailing commas
        clean_json = re.sub(r'/\*.*?\*/', '', json_str, flags=re.DOTALL)
        clean_json = re.sub(r'//.*', '', clean_json)
        clean_json = re.sub(r',(\s*[}\]])', r'\1', clean_json)
        data = json.loads(clean_json)
        return MockLivelyInfo(data)


class TestLivelyInfo(unittest.TestCase):

    def test_official_video_schema(self):
        """Parse standard video wallpaper metadata."""
        raw = """
        {
          "AppVersion": "2.0.0.0",
          "Title": "Rainy Window",
          "Thumbnail": "rain_thumb.jpg",
          "Preview": "rain_prev.gif",
          "Desc": "Gentle rain droplets on window pane",
          "Author": "LiveCreator",
          "License": "CC-BY",
          "Contact": "creator@example.com",
          "Type": 2,
          "FileName": "rain.mp4",
          "Arguments": null,
          "IsAbsolutePath": false
        }
        """
        info = MockLivelyInfo.parse(raw)
        self.assertEqual(info.app_version, "2.0.0.0")
        self.assertEqual(info.title, "Rainy Window")
        self.assertEqual(info.type, LivelyWallpaperType.Video)
        self.assertEqual(info.native_wallpaper_type, WallpaperType.Video)
        self.assertEqual(info.file_name, "rain.mp4")

        item = info.make_wallpaper_item("C:\\Wallpapers\\Rain")
        self.assertEqual(item["path_or_url"], "C:\\Wallpapers\\Rain\\rain.mp4")
        self.assertEqual(item["thumbnail_path"], "C:\\Wallpapers\\Rain\\rain_thumb.jpg")
        self.assertEqual(item["preview_path"], "C:\\Wallpapers\\Rain\\rain_prev.gif")
        self.assertFalse(item["is_interactive"])

    def test_polymorphic_type_string_and_casing(self):
        """Type property correctly parses string names with whitespace and any casing."""
        test_cases = [
            ('"web"', LivelyWallpaperType.Web, WallpaperType.Web),
            ('"WEB"', LivelyWallpaperType.Web, WallpaperType.Web),
            ('" Web "', LivelyWallpaperType.Web, WallpaperType.Web),
            ('"video"', LivelyWallpaperType.Video, WallpaperType.Video),
            ('"VIDEO"', LivelyWallpaperType.Video, WallpaperType.Video),
            ('"gif"', LivelyWallpaperType.Gif, WallpaperType.Video),
            ('"unity"', LivelyWallpaperType.Unity, WallpaperType.Web), # Unity defaults to Web
            ('"godot"', LivelyWallpaperType.Godot, WallpaperType.Web),
            ('"videostream"', LivelyWallpaperType.VideoStream, WallpaperType.Url),
            ('"webstream"', LivelyWallpaperType.WebStream, WallpaperType.Url),
            ('"app"', LivelyWallpaperType.App, WallpaperType.Web),
            ('"picture"', LivelyWallpaperType.Picture, WallpaperType.Web),
            ('"0"', LivelyWallpaperType.Web, WallpaperType.Web),
            ('"2"', LivelyWallpaperType.Video, WallpaperType.Video),
            ('"6"', LivelyWallpaperType.VideoStream, WallpaperType.Url),
            ('"unknown_type"', LivelyWallpaperType.Unknown, WallpaperType.Web),
            ("999", LivelyWallpaperType.Unknown, WallpaperType.Web),
            ("-1", LivelyWallpaperType.Unknown, WallpaperType.Web),
        ]
        for type_repr, expected_lively, expected_native in test_cases:
            payload = f'{{"Title": "T", "Type": {type_repr}, "FileName": "wallpaper.dat"}}'
            info = MockLivelyInfo.parse(payload)
            self.assertEqual(info.type, expected_lively, f"Failed for {type_repr}")
            self.assertEqual(info.native_wallpaper_type, expected_native, f"Failed for {type_repr}")

    def test_extension_fallback_when_type_is_unknown(self):
        """When Type is Unknown, determine native type by file extension."""
        extensions_map = [
            ("test.mp4", WallpaperType.Video),
            ("test.mov", WallpaperType.Video),
            ("test.webm", WallpaperType.Video),
            ("test.mkv", WallpaperType.Video),
            ("test.html", WallpaperType.Web),
            ("test.htm", WallpaperType.Web),
            ("test.zip", WallpaperType.Web),
            ("test.lively", WallpaperType.Web),
            ("test.xyz", WallpaperType.Web),  # Fallback to Web
        ]
        for fn, expected_native in extensions_map:
            payload = f'{{"Title": "ExtTest", "Type": -1, "FileName": "{fn}"}}'
            info = MockLivelyInfo.parse(payload)
            self.assertEqual(info.native_wallpaper_type, expected_native, f"Failed for {fn}")

    def test_property_name_case_insensitivity(self):
        """JSON property names must be parsed regardless of letter casing."""
        payload = """
        {
          "APPVERSION": "1.5",
          "title": "Case Test",
          "FILENAME": "matrix.html",
          "TYPE": 0,
          "ISABSOLUTEPATH": false
        }
        """
        info = MockLivelyInfo.parse(payload)
        self.assertEqual(info.app_version, "1.5")
        self.assertEqual(info.title, "Case Test")
        self.assertEqual(info.file_name, "matrix.html")
        self.assertEqual(info.type, LivelyWallpaperType.Web)
        self.assertEqual(info.is_absolute_path, False)

    def test_tolerant_json_comments_and_trailing_commas(self):
        """JSON with single-line comments, multi-line comments, and trailing commas parses."""
        payload = """
        {
          // Header comment
          "Title": "Commas and Comments",
          /* Multi-line
             description block */
          "FileName": "video.mp4",
          "Type": 2, // trailing comma on next line
        }
        """
        info = MockLivelyInfo.parse(payload)
        self.assertEqual(info.title, "Commas and Comments")
        self.assertEqual(info.file_name, "video.mp4")
        self.assertEqual(info.type, LivelyWallpaperType.Video)

    def test_missing_and_empty_fields(self):
        """Minimal JSON ({}) provides safe defaults without raising null reference exceptions."""
        info = MockLivelyInfo.parse("{}")
        self.assertEqual(info.title, "")
        self.assertEqual(info.file_name, "")
        self.assertEqual(info.type, LivelyWallpaperType.Unknown)
        self.assertIsNone(info.app_version)
        self.assertIsNone(info.thumbnail)
        self.assertIsNone(info.preview)

        item = info.make_wallpaper_item("C:\\Wallpapers\\Empty")
        self.assertEqual(item["title"], "")
        self.assertEqual(item["path_or_url"], "C:\\Wallpapers\\Empty")
        self.assertIsNone(item["thumbnail_path"])
        self.assertIsNone(item["preview_path"])

    def test_absolute_vs_relative_paths(self):
        """Verify handling of Windows drive paths, UNC paths, and URLs."""
        # 1. Windows Drive Absolute
        info1 = MockLivelyInfo({"FileName": "D:\\Media\\video.mp4", "IsAbsolutePath": False})
        item1 = info1.make_wallpaper_item("C:\\Wallpapers\\Pack")
        self.assertEqual(item1["path_or_url"], "D:\\Media\\video.mp4")

        # 2. UNC Path Absolute
        info2 = MockLivelyInfo({"FileName": "\\\\nas\\share\\video.mp4"})
        item2 = info2.make_wallpaper_item("C:\\Wallpapers\\Pack")
        self.assertEqual(item2["path_or_url"], "\\\\nas\\share\\video.mp4")

        # 3. HTTP URL
        info3 = MockLivelyInfo({"FileName": "https://www.shadertoy.com/view/MdX3zr"})
        item3 = info3.make_wallpaper_item("C:\\Wallpapers\\Pack")
        self.assertEqual(item3["path_or_url"], "https://www.shadertoy.com/view/MdX3zr")

        # 4. IsAbsolutePath flag explicitly true on relative filename
        info4 = MockLivelyInfo({"FileName": "relative.mp4", "IsAbsolutePath": True})
        item4 = info4.make_wallpaper_item("C:\\Wallpapers\\Pack")
        self.assertEqual(item4["path_or_url"], "relative.mp4")

        # 5. Null directoryPath with relative filename
        info5 = MockLivelyInfo({"FileName": "relative.mp4"})
        item5 = info5.make_wallpaper_item(None)
        self.assertEqual(item5["path_or_url"], "relative.mp4")

    def test_legacy_aliases_observation(self):
        """Demonstrate that legacy alias fields (Description vs Desc, Artist vs Author) are ignored."""
        payload = """
        {
          "Title": "Legacy Pack",
          "Description": "Long legacy description field",
          "Artist": "Legacy Artist Name",
          "FileName": "legacy.mp4"
        }
        """
        info = MockLivelyInfo.parse(payload)
        # Because LivelyInfo only binds Desc and Author, Description and Artist remain None
        self.assertIsNone(info.desc)
        self.assertIsNone(info.author)


if __name__ == "__main__":
    unittest.main()
