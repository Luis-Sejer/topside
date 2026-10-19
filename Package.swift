// swift-tools-version:5.9
import PackageDescription

/// Every app in the suite. Each is one folder in Sources/ and one .app built by build.sh.
let apps = ["Week", "Awake", "Pipette", "Mirror", "Upnext", "Shelf", "Scrub", "Zones", "Beam", "Hush", "Drawer"]

let package = Package(
    name: "Topside",
    platforms: [.macOS("26.0")],
    targets: [.target(name: "Kit")]
        + apps.map { .executableTarget(name: $0, dependencies: ["Kit"]) }
        + [.testTarget(name: "TopsideTests", dependencies: ["Kit", "Week", "Pipette", "Upnext", "Scrub", "Zones", "Drawer"])]
)
