# Installing Topside with an AI agent

Instructions for an AI coding agent (Claude Code, Codex, Cursor and similar) asked to install, update or uninstall Topside's apps on the user's Mac. Follow them in order, and tell the user what you did.

Topside is eleven separate menu bar apps: Week, Awake, Pipette, Mirror, Upnext, Shelf, Scrub, Zones, Beam, Hush and Drawer. If the user named some, install only those; otherwise install them all. The names are case-sensitive.

## Install or update

1. **Check the Mac can run them.** The apps need macOS 26 or later on Apple silicon. Drawer needs macOS 27.

   ```sh
   sw_vers -productVersion   # must be 26 or higher (27 or higher for Drawer)
   uname -m                  # must be arm64
   ```

   If either check fails, stop and tell the user Topside won't run on this Mac. Don't try to build or install it anyway. On macOS 26, leave Drawer out and tell the user why.

2. **Run the installer.** It downloads each app from the latest GitHub release, replaces any older copy in `~/Applications`, clears the quarantine flag (the apps aren't notarized) and opens them. It needs no admin password.

   Every app (on macOS 26 it skips Drawer by itself):

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh | sh
   ```

   Only some, for example Week and Hush:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh | sh -s -- Week Hush
   ```

   It keeps each app's settings. It exits with an error if an app name is unknown or a download fails.

3. **Check it worked.** For each app installed, for example Week:

   ```sh
   pgrep -x Week && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ~/Applications/Week.app/Contents/Info.plist
   ```

   This should print a process ID and a version number. Compare the version with the latest release on https://github.com/Luis-Sejer/topside/releases/latest.

4. **Tell the user how to use them.** The apps have no Dock icon or window; each lives in the menu bar as its own icon. Click an icon to use it, and right-click it for Check for Updates…, Open at Login, About and Quit. Use the README's table (https://github.com/Luis-Sejer/topside#the-apps) to say what each installed app does. Point out the permissions: Mirror asks for the camera, Upnext for the calendar, Scrub and Beam may trigger macOS's paste prompt, and Drawer needs Accessibility (Screen Recording is optional, for the real icon pictures). Each app updates itself from its right-click menu.

   If the user says macOS blocked an app, have them open **System Settings → Privacy & Security** and click **Open Anyway**.

## Uninstall

Every app:

```sh
curl -fsSL https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh | sh -s -- --uninstall
```

Only some, for example Week:

```sh
curl -fsSL https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh | sh -s -- --uninstall Week
```

This quits the apps and removes them. It keeps their settings, in case the user reinstalls.

Only if the user asks to remove everything, also delete each removed app's settings (the bundle ID is the name in lowercase):

```sh
defaults delete dk.sejer.week
```

## Don't

- Don't use `sudo`. Nothing here needs admin rights.
- Don't build from source unless the user asks. The releases are built by GitHub Actions from the tagged source.
- Don't grant permissions on the user's behalf. Tell them which app asks for what, and let them allow it in System Settings.
