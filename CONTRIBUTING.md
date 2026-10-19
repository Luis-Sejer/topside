# Contributing to Topside

Thanks for helping make Topside better. Bug reports, ideas and pull requests are all welcome.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and suggesting features

Open an [issue](https://github.com/Luis-Sejer/topside/issues/new/choose) and pick the template that fits. For bugs, include which app, its version (right-click its menu bar icon → About), your macOS version and the steps that show the problem.

Found a security issue? Please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Development setup

You need macOS 26 or later (macOS 27 for Drawer) and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```sh
git clone https://github.com/Luis-Sejer/topside.git
cd topside
./build.sh install Week
```

### Project layout

| Path | What lives there |
|---|---|
| `Package.swift` | The list of apps. Each is one executable target that depends on `Kit` |
| `Sources/Kit/` | What every app shares: startup, the menu bar item and its right-click menu, global shortcuts, updates and What's New |
| `Sources/<App>/` | One app each: its entry point, its logic and its views |
| `Tests/TopsideTests/` | Tests for the logic that can be wrong without looking wrong |
| `build.sh` | Builds each `.app`: its Info.plist, permission strings, icon and What's New |
| `docs/src/icons.html`, `render-icons.sh` | Every app icon, drawn in SVG, and the script that renders them to `docs/assets/icons/` (see [docs/ICONS.md](docs/ICONS.md)) |
| `docs/src/social.html` | The GitHub social preview image |

The website, [apps.luissejer.dk](https://apps.luissejer.dk), lives in its own repository.

## Guidelines

- **Stay native.** Use SwiftUI and AppKit, and follow Apple’s [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines). Topside has no third-party dependencies and should keep it that way.
- **Build with the Command Line Tools.** Avoid APIs that need full Xcode. For example, keep view state in `ObservableObject` instead of `@State`, whose macro plugin ships only with Xcode.
- **One app, one job.** A new feature belongs in the app it's about. Something shared goes into `Kit` only once two apps need it.
- **Ask only for the permission an app needs**, and only when the user turns on the feature that needs it.
- **A hidden app must cost nothing.** Cameras, animations and timers run only while the app's popover is open.
- **Keep it accessible.** Every control needs a VoiceOver label and everything must work from the keyboard.
- **Keep it small.** Prefer the simplest change that works, and match the style of the surrounding code.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change and check it builds with `./build.sh`, and run the tests with `./test.sh`. CI runs both on your pull request too.
3. Try it: `./build.sh install <App>` builds, installs and launches your version.
4. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) if users will notice the change. Start it with the app's name, like `- Week: …`.
5. Open a pull request that explains what changed and why, with a screenshot for anything visual.

## Releases

Every app shares one version number. Maintainers release by moving the **Unreleased** entries in `CHANGELOG.md` under a new version heading, committing, and running:

```sh
./release.sh 1.1.0
```

That tags the commit. GitHub Actions then builds every app, signs it with the Topside certificate stored as a repository secret, and publishes one zip per app, using the changelog entry as release notes.
