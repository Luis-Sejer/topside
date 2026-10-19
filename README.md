# Topside

Eleven small, free Mac menu bar apps that each solve one small problem. Each is its own download and asks only for the permission it needs.

| App | What it does | Asks for |
|---|---|---|
| **Week** | The week number in the menu bar ("Uge 40"), and a month calendar with the weeks | – |
| **Awake** | Keeps the Mac and its display awake for 15 minutes to 4 hours, or until turned off | – |
| **Pipette** | Click, pick any pixel, and its hex code is copied. Right-click for recent colors as hex, RGB or SwiftUI | – |
| **Mirror** | Your camera, mirrored, for a look before a call. The camera runs only while it's open | Camera |
| **Upnext** | "Standup in 4 min", and the Teams, Zoom or Meet link one click away | Calendar |
| **Shelf** | Drop files on the icon to park them, and drag them out wherever they're going | – |
| **Scrub** | Strips tracking parameters (utm_source, fbclid, si…) from links as you copy them | Clipboard |
| **Zones** | Your team's local times; pin one city to the menu bar | – |
| **Beam** | The clipboard as a QR code, so your phone's camera can open the link | Clipboard |
| **Hush** | Mutes the microphone itself, so it works in every call app. Click or press ⌃⌥M | – |
| **Drawer** | Hides the menu bar icons you don't need. ⌘-drag them left of the │ divider; click the chevron or press ⌃⌥B to show them. Optional: a bar under the menu bar with the hidden icons and a search, and a tint, shape, border and shadow for the menu bar | Accessibility, Screen Recording (both optional) |

Right-click any icon for About and Quit. ⌘-drag an icon to move it in the menu bar.

macOS 26 or later, Apple Silicon. What's next, including the features that need more permissions: [ROADMAP.md](ROADMAP.md).

## Build

```sh
./build.sh                  # every app, into build/
./build.sh install Week     # build, install to ~/Applications and launch
./test.sh                   # the logic tests
```

Needs only the Xcode Command Line Tools.

Try every app in your browser first, on [apps.luissejer.dk](https://apps.luissejer.dk).
