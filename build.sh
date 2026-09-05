#!/bin/zsh
# Builds Scorebug.app and writes Outputs/Scorebug <version>.zip. Refuses to overwrite a delivered archive.
set -euo pipefail
cd "${0:A:h}"
BUILD_ROOT="${SCOREBUG_BUILD_ROOT:-/private/tmp/scorebug-build}"
OUTPUT_ROOT="${SCOREBUG_OUTPUT_ROOT:-../Outputs}"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ARCHIVE_PATH="$OUTPUT_ROOT/Scorebug $APP_VERSION.zip"
if [[ -e "$ARCHIVE_PATH" ]]; then
  print -u2 "Build destination already exists. Bump the version in Resources/Info.plist or choose a fresh SCOREBUG_OUTPUT_ROOT."
  exit 1
fi
swift build --scratch-path "$BUILD_ROOT" -c release --product Scorebug
BIN_PATH=$(swift build --scratch-path "$BUILD_ROOT" -c release --show-bin-path)
BUILD_STAGE=$(mktemp -d /private/tmp/scorebug-package.XXXXXX)
APP_PATH="$BUILD_STAGE/Scorebug.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/Scorebug" "$APP_PATH/Contents/MacOS/Scorebug"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R Resources/Overlays "$APP_PATH/Contents/Resources/Overlays"
cp Resources/seed-library.json "$APP_PATH/Contents/Resources/seed-library.json"
if /usr/bin/xattr -p com.apple.FinderInfo "$APP_PATH" >/dev/null 2>&1; then /usr/bin/xattr -d com.apple.FinderInfo "$APP_PATH"; fi
/usr/bin/codesign --force --sign - "$APP_PATH"
/usr/bin/codesign --verify --strict "$APP_PATH"
mkdir -p "$OUTPUT_ROOT"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
print "Local ad-hoc-signed development app: ${APP_PATH:A}"
print "Archive: ${ARCHIVE_PATH:A}"
