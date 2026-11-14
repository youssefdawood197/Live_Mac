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
      --add-wallpaper <file|folder>              Import a video or web wallpaper into library
      --status                                   Display live runtime state and diagnostics
      --list                                     List all wallpapers in library
      -h, --help                                 Show this help message and exit
    """)
    exit(0)
}

if CommandLine.arguments.contains("--status") {
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let statusURL = appSupport.appendingPathComponent("LivelyWallpaper/status.json")

    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })

    if let running = running,
       let data = try? Data(contentsOf: statusURL),
       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let title = dict["activeWallpaperTitle"] as? String ?? "None"
        let type = (dict["activeWallpaperType"] as? String ?? "video").uppercased()
        let isPaused = dict["isPaused"] as? Bool ?? false
        let isMuted = dict["isMuted"] as? Bool ?? true
        let isInteractive = dict["isInteractive"] as? Bool ?? false
        let flake = dict["flakeEnabled"] as? Bool ?? false
        let intensity = (dict["flakeIntensity"] as? String ?? "steady").capitalized
        let angle = Int(dict["flakeWindAngle"] as? Double ?? 90)
        let speed = String(format: "%.1fx", dict["flakeWindSpeed"] as? Double ?? 1.0)
        let tool = (dict["activeTool"] as? String ?? "None").capitalized
        let displays = dict["displayCount"] as? Int ?? 1

        print("Lively Wallpaper Status:")
        print("--------------------------------------------------------------------------------")
        print("State            : Running (PID: \(running.processIdentifier))")
        print("Active Wallpaper : \(title) [\(type)]")
        print("Playback State   : \(isPaused ? "Paused" : "Playing") (Audio: \(isMuted ? "Muted" : "Unmuted"))")
        print("Interactivity    : \(isInteractive ? "Interactive (Capturing Input)" : "Off (Click-through to desktop)")")
        print("Flake Snow Mode  : \(flake ? "Enabled [\(intensity)]" : "Disabled")")
        if flake {
            print("Wind Physics     : \(angle)° @ \(speed)")
            print("Cursor Tool      : \(tool)")
        }
        print("Displays         : \(displays) active monitor\(displays == 1 ? "" : "s")")
        print("--------------------------------------------------------------------------------")
    } else if let running = running {
        print("Lively Wallpaper is running (PID: \(running.processIdentifier)), but status snapshot is initializing.")
    } else {
        print("Lively Wallpaper is currently not running.")
        print("Launch with: open build/LivelyWallpaper.app")
    }
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
