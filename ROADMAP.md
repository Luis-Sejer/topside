# Roadmap

What the apps could do next. Each app asks for no permission it can do without, so the features below were left out on purpose. Most need **Accessibility** or **Screen Recording**, which an admin Mac can grant in System Settings → Privacy & Security.

Ask for a permission only in the app that needs it, and only when the user turns the feature on. That is what keeping the apps separate is for.

Want one? Say so in an [issue](https://github.com/Luis-Sejer/topside/issues/new/choose), or build it: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Needs a permission

### Drawer (Accessibility + Screen Recording)

Built for macOS 27, which hides the menu bar icons that don't fit behind its own » button. Drawer lists those hidden icons in a bar with a search, and opens the one you click from the real icon. Ideas next:

- **Rearranging icons.** Choose which icons stay visible and in what order, from a window instead of ⌘-dragging. macOS 27 keeps the order in a protected file, so Drawer can't simply write it; Thaw does it with a "Menu Bar Layout Access" permission.
- **Triggers.** Show an icon when it changes, such as the battery icon when it's low. Needs Screen Recording to notice the change.

### Hush (Accessibility)

- **Mute inside the call app, not just the mic.** Press the app's own mute (⌘⇧M in Teams, ⌘⇧A in Zoom, ⌘D in Meet) with synthetic keystrokes, so the call shows you as muted too.
- **Read each app's mute state.** Zoom's menu says "Mute Audio" or "Unmute Audio", readable through Accessibility. Teams has a local third-party API (turn it on under Teams → Settings → Privacy), the one Stream Deck uses, so no permission is needed there. Meet runs in a browser tab, which is the hardest case.
- **A notch pill** that shows muted or live next to the notch.

### Beam (Screen Recording)

- **Scan a QR code on screen.** The reverse of Beam: find a QR code in a window and open its link. Vision does the decoding.

### Upnext (Notifications)

- **A heads-up a minute before a meeting**, with a Join button in the notification.
- **A notch pill** with the countdown.

## No permission needed

- **Every app: remappable shortcuts.** Snicker's `ShortcutStore` in Kit, for Hush (⌃⌥M) and Drawer (⌃⌥B, ⌃⌥⇧B).
- **Shelf:** keep the shelf across restarts (security-scoped bookmarks), an option to remove a file once it's dragged out, and a Share menu for AirDrop.
- **Awake:** stay awake while a chosen app runs or a download finishes, and an option to keep the system awake with the display off.
- **Pipette:** more formats (HSL, OKLCH, Tailwind's nearest color), and a contrast check between the last two colors picked.
- **Zones:** search the cities instead of browsing regions.
- **Scrub:** more sites' tracking parameters, and a list of sites to leave alone.
- **Mirror:** a lighting check and a grid for framing.
