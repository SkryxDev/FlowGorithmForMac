#!/bin/sh
# Builds dist/FlowGorithmForMac-<version>.dmg: the app next to a link to Applications.
# Usage: Scripts/make-dmg.sh <version>   (e.g. 1.0.0-beta). Build the Release app first.
set -e

VERSION="${1:?usage: Scripts/make-dmg.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Release/FlowGorithmForMac.app"
NAME="FlowGorithmForMac"
DMG="$ROOT/dist/$NAME-$VERSION.dmg"
WORK="$(mktemp -d)"

[ -d "$APP" ] || { echo "Build the Release app first: $APP is missing"; exit 1; }
mkdir -p "$ROOT/dist"
rm -f "$DMG"

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/$NAME.app"
ln -s /Applications "$WORK/stage/Applications"

# A writable image first, so Finder can lay out the window, then a compressed copy.
hdiutil create -quiet -volname "$NAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW "$WORK/rw.dmg"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')"
MOUNT="/Volumes/$NAME"

osascript <<EOF || echo "Finder layout skipped"
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 760, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set position of item "$NAME.app" of container window to {150, 150}
        set position of item "Applications" of container window to {410, 150}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach -quiet "$DEVICE"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$WORK"
echo "$DMG"
