#!/bin/sh
# Runs the Swift Testing tests with only the Command Line Tools, which ship the Testing macros
# but don't tell SwiftPM where they are.
set -e
cd "$(dirname "$0")"
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
