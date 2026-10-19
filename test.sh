#!/bin/sh
# Runs the Swift Testing tests with only the Command Line Tools, which ship the Testing macros and framework
# but don't tell SwiftPM where they are.
set -e
cd "$(dirname "$0")"
DEV="$(xcode-select -p)/Library/Developer"
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" \
    -Xswiftc -F -Xswiftc "$DEV/Frameworks" -Xlinker -rpath -Xlinker "$DEV/Frameworks" -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
