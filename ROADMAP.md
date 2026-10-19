# Roadmap

What the apps could do next. The first version of each app asks for no permission it can do without, so the features below were left out on purpose. Most need **Accessibility** or **Screen Recording**, which an admin Mac can grant in System Settings → Privacy & Security.

Ask for a permission only in the app that needs it, and only when the user turns the feature on. That is what keeping the apps separate is for.

## Needs a permission

### Drawer (Accessibility + Screen Recording, like Ice and Bartender)

**Built. Checked on macOS 27 without the permissions:**

- Hiding: the divider sized to the free space hides the icons to its left (seen on a notched MacBook).
- Finding icons through each app's `AXExtrasMenuBar`, and their frames, on Drawer's own icons. An app may read its own Accessibility tree without the permission.
- Opening an icon with Accessibility's press, also on Drawer's own icon.
- The appearance overlay window: one level below the menu bar, covering it exactly.
- The coordinate, crop, search and shape logic, in the tests.
- The bar and the Appearance window, drawn to images.

**Not yet tried: other apps' icons, which need the permissions.** Try these on an admin Mac:

1. `./build.sh install Drawer`. Right-click the chevron, choose Show Hidden Icons In → Drawer Bar, and allow Accessibility. Screen Recording is optional.
2. Click the chevron. Does the bar list the hidden icons, and does clicking one open its menu?
3. With Screen Recording on: show the icons in the menu bar once (switch back to The Menu Bar, click the chevron, switch again). Does the bar then show the real icons instead of app icons?
4. Type in the bar's search field. Does it find visible icons too, and does Return open the first match?
5. Right-click the chevron → Menu Bar Appearance…: try a tint, each shape, a border and a shadow. Does the tint show *behind* the menu bar's text? The overlay sits one level below the menu bar; if it doesn't show through, try `.mainMenu` or `.statusBar` as its level in `Appearance.swift`.

Ad-hoc builds lose these permissions on every rebuild; re-allow Drawer in System Settings after each one, or sign with a fixed certificate.

Still to build:

- **Icons behind the notch, opened from the bar.** Drawer shows the icons and clicks the one picked. If it lands behind the notch, the click misses. Ice handles this by ⌘-dragging the icon somewhere visible with synthetic events, clicking it, then putting it back.
- **Layout editor.** Arrange icons by dragging them in a window instead of ⌘-dragging in the menu bar. It needs Accessibility to move them with synthetic ⌘-drags.
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

- **Every app: updates.** Snicker's `Updater` (a daily check of GitHub releases, Update / Later) and `WhatsNew`, moved into Kit.
- **Every app: remappable shortcuts.** Snicker's `ShortcutStore` in Kit, for Hush (⌃⌥M) and Drawer (⌃⌥B, ⌃⌥⇧B).
- **Every app: releases.** One self-made signing certificate for all of them, kept forever (macOS forgets permissions when it changes), and a release workflow like Snicker's that builds every app.
- **Shelf:** keep the shelf across restarts (security-scoped bookmarks), an option to remove a file once it's dragged out, and a Share menu for AirDrop.
- **Awake:** stay awake while a chosen app runs or a download finishes, and an option to keep the system awake with the display off.
- **Pipette:** more formats (HSL, OKLCH, Tailwind's nearest color), and a contrast check between the last two colors picked.
- **Zones:** search the cities instead of browsing regions.
- **Scrub:** more sites' tracking parameters, and a list of sites to leave alone.
- **Mirror:** a lighting check and a grid for framing.
