#!/bin/sh
# FlowGorithmForMac · Copyright © 2026 SkryxDev
# GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

# Builds dist/FlowGorithmForMac-<version>.dmg: the app next to a link to Applications, on the
# background drawn by Scripts/make-dmg-background.swift, with the app's icon on the disk.
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
BACKGROUND="$ROOT/Scripts/dmg-background.tiff"

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
if [ -f "$BACKGROUND" ]; then
    mkdir "$WORK/stage/.background"
    cp "$BACKGROUND" "$WORK/stage/.background/background.tiff"
fi

# A writable image first, so Finder can lay out the window, then a compressed copy.
hdiutil create -quiet -volname "$NAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW "$WORK/rw.dmg"
ATTACHED="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg")"
DEVICE="$(echo "$ATTACHED" | awk '/Apple_HFS/ {print $1}')"
VOLUME="$(echo "$ATTACHED" | awk -F '\t' '/Apple_HFS/ {print $NF}')"
[ -n "$DEVICE" ] || { echo "Couldn't mount the image"; exit 1; }

# A 640×400 window: the app at the left of the background's arrow, Applications at its right.
osascript <<EOF || echo "Finder layout skipped"
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        set bounds of container window to {200, 120, 840, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        if exists file ".background:background.tiff" then
            set background picture of viewOptions to file ".background:background.tiff"
        end if
        set position of item "$NAME.app" of container window to {160, 200}
        set position of item "Applications" of container window to {480, 200}
        -- Hidden files show when Finder is set to show them: they go outside the window.
        repeat with hiddenName in {".background", ".fseventsd", ".DS_Store", ".Trashes"}
            if exists item hiddenName of container window then
                set position of item hiddenName of container window to {900, 900}
            end if
        end repeat
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# The disk shows the app's icon in Finder and on the desktop. Copied after the layout, and
# left where it is: Finder deletes the file whenever it opens the window with it inside.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ] && [ -d "$VOLUME" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$VOLUME/.VolumeIcon.icns"
    SetFile -c icnC -a V "$VOLUME/.VolumeIcon.icns" || true
    SetFile -a C "$VOLUME" || true
fi

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
