#!/bin/bash
# Builds "Graphire Tablet.app" (native Apple Silicon) into ./build.
# Usage: ./build.sh            build only
#        ./build.sh install    build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Graphire Tablet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -parse-as-library \
    Sources/*.swift -o "$APP/Contents/MacOS/GraphireTablet"

# A stable signing identity keeps the Accessibility permission across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "install" ]]; then
    pkill -x GraphireTablet 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/Graphire Tablet.app"
    cp -R "$APP" /Applications/
    open "/Applications/Graphire Tablet.app"
    echo "Installed and launched /Applications/Graphire Tablet.app"
fi
