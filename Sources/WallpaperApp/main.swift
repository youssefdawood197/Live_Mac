import AppKit

if CommandLine.arguments.contains("-h") || CommandLine.arguments.contains("--help") {
    print("""
    Lively Wallpaper for macOS
    Usage: WallpaperApp [OPTIONS]

    Options:
      --play                                     Resume live wallpaper playback
      --pause                                    Pause live wallpaper playback
      --mute                                     Mute wallpaper audio
      --unmute                                   Unmute wallpaper audio
      --interactive <on|off>                     Toggle interactive desktop mode
      --flake <on|off>                           Toggle Flake ambient snow mode
      --flake-intensity <light|steady|blizzard>  Set snowfall intensity
      --clear-snow                               Clear all active snowdrifts
      --set-wallpaper <title|path>               Switch active wallpaper
      -h, --help                                 Show this help message and exit
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
