#!/bin/zsh
# Builds Scorebug and installs it as /Applications/Scorebug.app, replacing the previous copy, then opens it.
# Like Content Template: no zip to unpack, just the app in Applications.
set -euo pipefail
cd "${0:A:h}"
BUILD_ROOT="${SCOREBUG_BUILD_ROOT:-/private/tmp/scorebug-build}"
swift build --scratch-path "$BUILD_ROOT" -c release --product Scorebug
BIN_PATH=$(swift build --scratch-path "$BUILD_ROOT" -c release --show-bin-path)
STAGE=$(mktemp -d /private/tmp/scorebug-install.XXXXXX)
APP="$STAGE/Scorebug.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Scorebug" "$APP/Contents/MacOS/Scorebug"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Overlays "$APP/Contents/Resources/Overlays"
cp Resources/seed-library.json "$APP/Contents/Resources/seed-library.json"
[[ -f Resources/squads.json ]] && cp Resources/squads.json "$APP/Contents/Resources/squads.json"
/usr/bin/codesign --force --sign - "$APP"
osascript -e 'tell application id "local.scorebug.mac" to quit' >/dev/null 2>&1 || true
sleep 1
mkdir -p "/Applications"
rm -rf "/Applications/Scorebug.app"
/usr/bin/ditto "$APP" "/Applications/Scorebug.app"
rm -rf "$STAGE"
open "/Applications/Scorebug.app"
print "Installed and opened /Applications/Scorebug.app ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist))"
