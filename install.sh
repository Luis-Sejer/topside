#!/bin/sh
# Installs or updates Topside's apps in ~/Applications from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh | sh                   every app
#   curl -fsSL https://raw.githubusercontent.com/Luis-Sejer/topside/main/install.sh | sh -s -- Week Hush   just those
#   … | sh -s -- --uninstall [App…]   removes the apps (every app if none is named) but keeps their settings
# Each app's Update menu item runs this for that one app.
set -e
REPO=Luis-Sejer/topside
ALL="Week Awake Pipette Mirror Upnext Shelf Scrub Zones Beam Hush Drawer"
INSTALL_DIR="$HOME/Applications"

UNINSTALL=
[ "$1" = "--uninstall" ] && { UNINSTALL=1; shift; }

# Names are case-sensitive, as they are on the release's zips.
for APP_NAME in "$@"; do
    case " $ALL " in
        *" $APP_NAME "*) ;;
        *) echo "Unknown app: $APP_NAME. Choose from: $ALL" >&2; exit 1 ;;
    esac
done
APPS=${*:-$ALL}

bundle_id() { echo "dk.sejer.$(echo "$1" | tr '[:upper:]' '[:lower:]')"; }

if [ -n "$UNINSTALL" ]; then
    for APP_NAME in $APPS; do
        if pkill -x "$APP_NAME"; then sleep 1; fi
        # The README's hand install may have put it in /Applications instead.
        rm -rf "$INSTALL_DIR/$APP_NAME.app" "/Applications/$APP_NAME.app"
        echo "Removed $APP_NAME."
    done
    echo "Settings are kept in case you come back. To remove them too, run for each app:"
    for APP_NAME in $APPS; do echo "  defaults delete $(bundle_id "$APP_NAME")"; done
    exit 0
fi

# Drawer works with the » button macOS 27 hides menu bar icons behind; the other apps run on macOS 26.
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
SKIPPED=
if [ "$MACOS_MAJOR" -lt 27 ]; then
    case " $APPS " in
        *" Drawer "*)
            if [ $# -gt 0 ]; then
                echo "Drawer needs macOS 27 or later, and this Mac runs macOS $(sw_vers -productVersion)." >&2
                exit 1
            fi
            APPS=$(echo "$APPS" | sed 's/ *Drawer//')
            SKIPPED="Drawer"
            echo "Skipping Drawer: it needs macOS 27 or later."
            ;;
    esac
fi

DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
mkdir -p "$INSTALL_DIR"

# gh works while the repo is private; plain curl works once it is public.
USE_GH=
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then USE_GH=1; fi

install_app() {
    ZIP="$DOWNLOAD_DIR/$1.zip"
    if [ -n "$USE_GH" ]; then
        gh release download --repo "$REPO" --pattern "$1.zip" --dir "$DOWNLOAD_DIR" --clobber || return 1
    else
        curl -fsSL "https://github.com/$REPO/releases/latest/download/$1.zip" -o "$ZIP" || return 1
    fi
    if pkill -x "$1"; then sleep 1; fi
    rm -rf "$INSTALL_DIR/$1.app"
    ditto -x -k "$ZIP" "$INSTALL_DIR" || return 1
    # Not notarized, so drop the quarantine flag that would make Gatekeeper block it.
    xattr -dr com.apple.quarantine "$INSTALL_DIR/$1.app" 2>/dev/null || true
    open "$INSTALL_DIR/$1.app" || return 1
}

INSTALLED=
FAILED=
for APP_NAME in $APPS; do
    echo "Installing $APP_NAME…"
    if install_app "$APP_NAME"; then
        INSTALLED="$INSTALLED $APP_NAME"
    else
        echo "Couldn't install $APP_NAME." >&2
        FAILED="$FAILED $APP_NAME"
    fi
done

echo
[ -n "$INSTALLED" ] && echo "Installed in $INSTALL_DIR:$INSTALLED. Look for them in the menu bar; right-click any icon for its menu."
[ -n "$SKIPPED" ] && echo "Skipped: $SKIPPED (needs macOS 27)."
if [ -n "$FAILED" ]; then
    echo "Failed:$FAILED. Check your connection, or download them from https://github.com/$REPO/releases/latest" >&2
    exit 1
fi
exit 0
