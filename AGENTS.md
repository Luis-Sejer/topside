# AGENTS.md

Guide for AI coding agents working on Topside: small macOS menu bar apps in one Swift package, built on what [Snicker](https://github.com/Luis-Sejer/snicker-gif) learned.

- SwiftUI + AppKit, Swift Package Manager, **no third-party dependencies**
- macOS 26+, Apple Silicon. No Dock icon (`LSUIElement`), no sandbox, not notarized

## Commands

```sh
./build.sh                  # build every app into build/ (release)
./build.sh install Week     # build, install to ~/Applications, relaunch
./test.sh                   # Swift Testing tests, with the Command Line Tools
swift build                 # quick compile check
```

Tests cover the logic that can be wrong without looking wrong: link cleaning (Scrub), meeting links and countdowns (Upnext), color formats (Pipette), ISO weeks (Week) and time zone offsets (Zones). Views are checked by eye: run `./build.sh install <App>` and ask the user for a screenshot, since the agent can't see the screen.

## Code map

| Path | Responsibility |
|---|---|
| `Package.swift` | The `apps` list. Every app is one executable target that depends on `Kit` |
| `Sources/Kit/` | Shared by all apps: `Kit.run` (app startup), `MenuBarItem` (status item, popover or menu or action, right-click About/Quit, `flash`), `HotKey` (Carbon global shortcut), closure-based `NSMenuItem` |
| `Sources/<App>/<App>.swift` | One file per app: its `@main`, its class and its views |
| `build.sh` | Per-app permission strings; writes each `.app` bundle, its Info.plist and its icon from `docs/assets/icons/` |
| `docs/src/icons.html` | Every app icon, drawn in SVG to the icon guide, `docs/ICONS.md` (`?app=week` shows one at 1024 px; no parameter shows all eleven) |
| `docs/src/render-icons.sh` | Renders the icons with headless Chrome to `docs/assets/icons/<app>.png`; run it after changing `icons.html` |

## Adding an app

1. Add its name to `apps` in `Package.swift` and to `ALL` and the `case` in `build.sh` (with any usage string). Draw its icon in `docs/src/icons.html`, add it to `render-icons.sh`, and run that.
2. Create `Sources/<Name>/<Name>.swift` with `@main enum Main { @MainActor static func main() { Kit.run { Name() } } }`.
3. Give the class a `MenuBarItem`. Pure logic gets a `nonisolated static` function and a test.
4. Add it to the README table.

The website, apps.luissejer.dk, is a separate private repo (`../apps` on the owner's machine). Its menu bar recreates every app's real menu or popover, so when an app's behaviour changes, change it there too.

## Rules that are easy to break

1. **Build with the Command Line Tools, not Xcode.** On the macOS 27 SDK, `@State` and `@Observable` are macros whose plugins ship only with Xcode. Keep view state in an `ObservableObject` with `@Published`. `@ObservedObject`, `@AppStorage`, `@Binding` and `@Environment` are fine. Swift Testing works only because `test.sh` passes the CLT's Testing plugin path.
2. **A hidden app must cost nothing.** Cameras, animations and clocks run only while their popover shows (`onShow`/`onClose`). Background timers are allowed only where nothing else works, and get a `ponytail:` comment saying why.
3. **Ask only for the permission the app needs**, and only when it needs it. That's the reason the suite is separate apps.
4. **Popover sizes are fixed up front** (`MenuBarItem.Click.popover(_, size:)`). Letting SwiftUI size them after showing makes them grow up under the menu bar.
5. **Clipboard reads trigger macOS's paste prompt.** Scrub checks `changeCount` and `detectedPatterns` first, and reads the text only when it holds a link.
6. **Accessibility is a requirement.** Icon-only buttons need `accessibilityLabel`; menu bar confirmations also call `Kit.announce`.
7. **Signing.** Local builds sign ad-hoc, so macOS forgets camera and calendar permission on each rebuild. Before the first public release, create one certificate and sign every release with it, forever (see Snicker's AGENTS.md).

## Conventions

- Match the surrounding style: one file per app, doc comments that explain *why*, named constants on the type.
- The smallest change that works; no new abstractions or dependencies without a clear need. Something Kit could share goes into Kit only once two apps need it.
- Commits use [Conventional Commits](https://www.conventionalcommits.org).
