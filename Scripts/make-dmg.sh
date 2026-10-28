#!/bin/sh
# FlowGorithmForMac · Copyright © 2026 SkryxDev
# GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

# Builds dist/FlowGorithmForMac-<version>.dmg: the app next to a link to Applications.
# Usage: Scripts/make-dmg.sh <version>   (e.g. 1.0.0). Build the Release app first.
#
# Optional, so the app opens without Gatekeeper warnings (needs an Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   signs the app and the image
#   NOTARY_PROFILE=<profile>   notarizes and staples the image; create the profile once with
#                              xcrun notarytool store-credentials <profile>
set -e

VERSION="${1:?usage: Scripts/make-dmg.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Release/FlowGorithmForMac.app"
NAME="FlowGorithmForMac"
DMG="$ROOT/dist/$NAME-$VERSION.dmg"
WORK="$(mktemp -d)"
DEVICE=""

# Whatever happens, don't leave the image mounted or the work folder behind.
cleanup() {
    if [ -n "$DEVICE" ]; then hdiutil detach -quiet -force "$DEVICE" || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

[ -d "$APP" ] || { echo "Build the Release app first: $APP is missing"; exit 1; }
# Finder finds the disk by name, so another volume with the same name would get the layout.
[ -d "/Volumes/$NAME" ] && { echo "Eject the volume \"$NAME\" first"; exit 1; }
mkdir -p "$ROOT/dist"
rm -f "$DMG"

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/$NAME.app"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$WORK/stage/$NAME.app"
fi
ln -s /Applications "$WORK/stage/Applications"

# A writable image first, so Finder can lay out the window, then a compressed copy.
hdiutil create -quiet -volname "$NAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW "$WORK/rw.dmg"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')"
[ -n "$DEVICE" ] || { echo "Couldn't mount the image"; exit 1; }

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
DEVICE=""
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "$DMG"
shasum -a 256 "$DMG"
