import AppKit

let bundleID = "com.lively.wallpaper"
let cliNotificationName = Notification.Name("com.lively.wallpaper.command")

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

// Enforce single-instance: forward commands if already running
let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

if !runningInstances.isEmpty {
    let args = Array(CommandLine.arguments.dropFirst())
    let payload = args.isEmpty ? ["--show-manager"] : args
    DistributedNotificationCenter.default().postNotificationName(
        cliNotificationName,
        object: nil,
        userInfo: ["args": payload],
        deliverImmediately: true
    )
    if args.isEmpty {
        print("Lively Wallpaper is already running. Brought manager window to front.")
    } else {
        print("Command sent to running Lively Wallpaper instance: \(args.joined(separator: " "))")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
