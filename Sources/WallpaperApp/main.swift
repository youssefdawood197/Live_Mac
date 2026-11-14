import AppKit
import WallpaperCore

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
      --list                                     List all wallpapers in library
      -h, --help                                 Show this help message and exit
    """)
    exit(0)
}

if CommandLine.arguments.contains("--list") {
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let jsonURL = appSupport.appendingPathComponent("LivelyWallpaper/wallpapers.json")
    if let data = try? Data(contentsOf: jsonURL),
       let items = try? JSONDecoder().decode([WallpaperItem].self, from: data) {
        print("Lively Wallpaper Library (\(items.count) wallpapers):")
        print("--------------------------------------------------------------------------------")
        print("TYPE      TITLE                             FILE")
        print("--------------------------------------------------------------------------------")
        for item in items {
            let shortFile = (item.pathOrURL as NSString).lastPathComponent
            let shortTitle = item.title.count > 32 ? String(item.title.prefix(29)) + "..." : item.title
            let typePad = item.type.rawValue.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
            let titlePad = shortTitle.padding(toLength: 32, withPad: " ", startingAt: 0)
            print("\(typePad)  \(titlePad)  \(shortFile)")
        }
        print("--------------------------------------------------------------------------------")
    } else {
        print("No wallpapers found or library not yet initialized.")
    }
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
