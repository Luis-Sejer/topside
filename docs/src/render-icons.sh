#!/bin/sh
# Renders every app icon from icons.html to docs/assets/icons/<app>.png (1024 × 1024, transparent).
# Needs Google Chrome. build.sh makes each app's iconset from these.
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for app in week awake pipette mirror upnext shelf scrub zones beam hush drawer; do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
        --window-size=1024,1024 --screenshot="$PWD/../assets/icons/$app.png" "file://$PWD/icons.html?app=$app" 2>/dev/null
done
echo "Rendered docs/assets/icons/"
