# Product

## Platform

Native macOS menu bar apps, one Swift package. The website, [apps.luissejer.dk](https://apps.luissejer.dk), is a separate repository; this repo has no site of its own.

## Stack

SwiftUI and AppKit, Swift Package Manager, no third-party dependencies, built with the Xcode Command Line Tools only. Releases are built by GitHub Actions from the tag.

## Users

- **People who work on a Mac all day** and keep meeting the same small annoyances: what week is it, is my mic muted, what time is it in Lisbon, how do I get this link to my phone. They want the one fix, not a utility suite with a settings window.
- **Mac enthusiasts** who collect well-crafted menu bar apps and care about native design, small size and few permissions.

## Product Purpose

Topside is eleven small, free menu bar apps that each solve one small problem: Week, Awake, Pipette, Mirror, Upnext, Shelf, Scrub, Zones, Beam, Hush and Drawer. Success is the problem gone in one click, by an app you forget is running until you need it.

## Positioning

The lead promise is "one small problem, one small app". Supporting proof: each app is its own download, so you install only what you want, and each asks only for the permission it needs (most ask for none). They share one look, one icon family and one version number. Free and open source (MIT), from the maker of [Snicker](https://github.com/Luis-Sejer/snicker-gif).

## Operating Context

Glanced at or clicked for seconds, from the menu bar, between other work. Installed with a one-line `curl` command (all apps or named ones) or per-app zips from GitHub Releases; not on the Mac App Store and not notarized, so hand installs need System Settings → Privacy & Security → Open Anyway. Each app checks GitHub for updates and offers them in its right-click menu.

## Capabilities and Constraints

- One app per job; the README table is the source of truth for what each does and which permission it asks for.
- macOS 26 or later on Apple Silicon. Drawer needs macOS 27, because it works with the » button macOS 27 hides icons behind.
- A hidden app costs nothing: cameras, clocks and animations run only while its popover is open.
- Pricing: say only that the apps are free (and open source, MIT). Make no promises about the future.

## Brand Commitments

- Name: Topside (the top side of the screen, where the apps live). App names are single plain words.
- Icons follow [docs/ICONS.md](docs/ICONS.md): a tonal gradient ground in each app's own hue, one bold porcelain object, one accent. In Dock order the hues run round the colour wheel, with graphite for Drawer.
- Menu bar glyphs are SF Symbols template images, so they match macOS.
- The voice is plain and short: what it does, in the user's words.

## Evidence on Hand

- `docs/assets/icons/*.png`: the eleven app icons (1024 px).
- `docs/assets/social/github-social.png`: the GitHub social preview.
- No screenshots, video, testimonials, user counts or press exist in this repo. Do not invent any.

## Product Principles

1. One problem per app, solved in one click.
2. Ask for nothing you can do without.
3. Native and small beats feature-heavy.
4. Nothing to set up and nothing collected.

## Accessibility & Inclusion

Every control has a VoiceOver label, menu bar confirmations are announced, and everything works from the keyboard.
