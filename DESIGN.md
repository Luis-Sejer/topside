# Design System: Topside

Topside's apps are native: they follow Apple's Human Interface Guidelines through SwiftUI and AppKit system controls and materials, and have no web tokens of their own. The website's design lives in its own repository. This file covers what the apps share.

## Overview

**North Star: "Part of the menu bar"**

Each app should look like something macOS could have shipped: a template SF Symbol in the menu bar, a system popover or menu under it, system fonts, colours and materials inside. Nothing branded inside the apps; the colour lives in the app icons.

## The menu bar

- **Glyphs** are SF Symbols, as template images, so they follow light, dark and tinted menu bars. Week shows text ("Uge 40"), Zones may show a pinned city's time.
- **Left click** does the app's one job: open a popover (Week, Mirror, Shelf, Beam), open a menu built fresh on every click (Awake, Upnext, Scrub, Zones) or act at once (Pipette, Hush, Drawer's bar).
- **Right click** (or Control-click) opens the shared menu from `Kit`: "Update to X…" when one is out, the app's own items, then Check for Updates…, Open at Login, About and Quit.
- **Confirmations** flash a checkmark on the icon (`MenuBarItem.flash`) and are announced to VoiceOver.

## Popovers

- **Fixed sizes**, set up front (`MenuBarItem.Click.popover(_, size:)`), so they never grow up under the menu bar.
- **System materials and controls only**: SwiftUI's default popover background, standard buttons, lists and pickers. No custom colours beyond the system accent and semantic colours.
- **System type**: SF Pro through SwiftUI's text styles; monospaced digits for times and numbers that change.
- **Nothing runs while closed**: cameras, timers and animations start in `onShow` and stop in `onClose`.

## What's New

After an update, each app shows its CHANGELOG section once: headings (`### Added`, `### Changed`, `### Fixed`) and `- ` bullets, nothing else. Write entries as one user-facing sentence, starting with the app's name.

## Icons

The app icons are one family, drawn in SVG in `docs/src/icons.html` and rendered by `docs/src/render-icons.sh`. The rules (canvas, gradient ground, porcelain object, one accent, palettes) are in [docs/ICONS.md](docs/ICONS.md).

## Social preview

`docs/src/social.html` renders the GitHub social preview: Apple's light gray (`#f5f5f7`) with a menu bar across the top, the name in SF Pro at 700 with tight tracking, a one-line tagline in `#515154`, and the eleven icons. Same layout as Snicker's banner, so the two read as one maker's.

## Do's and Don'ts

### Do:
- **Do** use SF Symbols for every glyph, as template images in the menu bar.
- **Do** use system controls, materials, fonts and semantic colours inside the apps.
- **Do** give icon-only buttons an `accessibilityLabel`, and announce menu bar confirmations.
- **Do** keep each app to one job and one popover or menu.

### Don't:
- **Don't** add brand colours, gradients or custom chrome inside the apps; the icons carry the colour.
- **Don't** add a settings window where a right-click menu item will do.
- **Don't** let a popover size itself after it shows.
- **Don't** hand-draw menu bar glyphs.
