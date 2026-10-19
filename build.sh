#!/bin/sh
# Builds every app into build/<App>.app. Needs only the Xcode Command Line Tools.
#   ./build.sh                    all apps
#   ./build.sh Week Hush          just those
#   ./build.sh install [App…]     also install to ~/Applications and launch
set -e
cd "$(dirname "$0")"

ALL="Week Awake Pipette Mirror Upnext Shelf Scrub Zones Beam Hush Drawer"
INSTALL=
[ "$1" = "install" ] && { INSTALL=1; shift; }
APPS=${*:-$ALL}

VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
VERSION=${VERSION:-0.1.0}
BUILD=$(git rev-parse --short HEAD 2>/dev/null || echo local)

swift build -c release
mkdir -p build

for APP_NAME in $APPS; do
    # Any permission the app asks for. Only the apps that need one ask.
    USAGE=
    case $APP_NAME in
        Mirror) USAGE="<key>NSCameraUsageDescription</key><string>Mirror shows your camera so you can check how you look before a call.</string>" ;;
        Upnext) USAGE="<key>NSCalendarsFullAccessUsageDescription</key><string>Upnext reads your calendar to count down to your next meeting and find its link.</string>" ;;
        Week|Awake|Pipette|Shelf|Scrub|Zones|Beam|Hush|Drawer) ;;
        *) echo "Unknown app: $APP_NAME (one of: $ALL)"; exit 1 ;;
    esac

    APP=build/$APP_NAME.app
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

    # The icon art is drawn in docs/src/icons.html and rendered by docs/src/render-icons.sh.
    ICON=docs/assets/icons/$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]').png
    ICONSET=build/$APP_NAME.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    cp "$ICON" "$ICONSET/icon_512x512@2x.png"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        [ $size = 512 ] || sips -z $((size * 2)) $((size * 2)) "$ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"

    BUNDLE_ID=dk.sejer.$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    $USAGE
</dict>
</plist>
PLIST
    # Apple Silicon refuses unsigned code. Ad-hoc signing needs no certificate, but macOS forgets granted
    # permissions (camera, calendar) on every build. Releases need one fixed certificate, as Snicker learned.
    codesign --force --sign "${TOPSIDE_SIGNING_IDENTITY:--}" "$APP"
    echo "Built $APP ($VERSION)"

    if [ -n "$INSTALL" ]; then
        # ~/Applications needs no admin rights and is still indexed by Spotlight.
        mkdir -p "$HOME/Applications"
        if pkill -x "$APP_NAME"; then sleep 1; fi
        rm -rf "$HOME/Applications/$APP_NAME.app"
        cp -R "$APP" "$HOME/Applications/"
        open "$HOME/Applications/$APP_NAME.app"
    fi
done
