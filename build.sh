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
BUILD_STAGE=$(mktemp -d "${TMPDIR:-/private/tmp}/scorebug-package.XXXXXX")
APP_PATH="$BUILD_STAGE/Scorebug.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/Scorebug" "$APP_PATH/Contents/MacOS/Scorebug"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R Resources/Overlays "$APP_PATH/Contents/Resources/Overlays"
cp Resources/seed-library.json "$APP_PATH/Contents/Resources/seed-library.json"
mkdir -p "$APP_PATH/Contents/Resources/Scripts" "$APP_PATH/Contents/Resources/mcp"
cp Scripts/scorebug.mjs Scripts/match-lib.mjs "$APP_PATH/Contents/Resources/Scripts/"
cp mcp/scorebug-mcp.mjs "$APP_PATH/Contents/Resources/mcp/"
[[ -f Resources/squads.json ]] && cp Resources/squads.json "$APP_PATH/Contents/Resources/squads.json"

if /usr/bin/xattr -p com.apple.FinderInfo "$APP_PATH" >/dev/null 2>&1; then /usr/bin/xattr -d com.apple.FinderInfo "$APP_PATH"; fi
# Releases are Developer ID signed with the hardened runtime, notarised and stapled, so they open on any Mac
# (the same certificate and "JuniorOS" notarytool profile as Video Prompter and Talk & Read). A Mac without the
# certificate signs ad hoc. SCOREBUG_NOTARISE=0 skips notarisation for a quick local build.
DEV_ID_SHA="C297CD17464A0EF6C93704A59BC2E1D4D1759400"
NOTARY_PROFILE="${SCOREBUG_NOTARY_PROFILE:-JuniorOS}"
SIGN_ID="-"
if /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_ID_SHA"; then SIGN_ID="$DEV_ID_SHA"; fi
SIGN_OPTS=(--force --options runtime --sign "$SIGN_ID")
[[ "$SIGN_ID" == "-" ]] || SIGN_OPTS+=(--timestamp)   # notarisation needs Apple's secure timestamp
/usr/bin/codesign "${SIGN_OPTS[@]}" "$APP_PATH"
/usr/bin/codesign --verify --strict "$APP_PATH"
print "Signed with: $SIGN_ID"
NOTARISED=0
if [[ "$SIGN_ID" != "-" && "${SCOREBUG_NOTARISE:-1}" == 1 ]]; then
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$BUILD_STAGE/notarise.zip"
  /usr/bin/xcrun notarytool submit "$BUILD_STAGE/notarise.zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m | tee "$BUILD_STAGE/notarise.log"
  grep -q "status: Accepted" "$BUILD_STAGE/notarise.log" || { print -u2 "Notarisation was not accepted (see the log above). Work kept at $BUILD_STAGE."; exit 1; }
  /usr/bin/xcrun stapler staple "$APP_PATH"
  /usr/bin/xcrun stapler validate "$APP_PATH"
  /usr/sbin/spctl --assess --type execute -vv "$APP_PATH"
  NOTARISED=1
  print "Notarised and stapled"
fi
mkdir -p "$OUTPUT_ROOT"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
# The website download is a disk image of the same stapled app, signed, notarised and stapled itself.
if (( NOTARISED )); then
  DMG_PATH="$OUTPUT_ROOT/Scorebug $APP_VERSION.dmg"
  [[ ! -e "$DMG_PATH" ]] || { /bin/rm -f "$ARCHIVE_PATH"; print -u2 "Refusing to overwrite $DMG_PATH; $ARCHIVE_PATH removed again."; exit 1; }
  DMG_STAGE="$BUILD_STAGE/dmg"
  TMP_DMG="$BUILD_STAGE/Scorebug $APP_VERSION.dmg"
  mkdir -p "$DMG_STAGE"
  /usr/bin/ditto "$APP_PATH" "$DMG_STAGE/Scorebug.app"
  /bin/ln -s /Applications "$DMG_STAGE/Applications"
  /usr/bin/hdiutil create -quiet -volname "Scorebug" -srcfolder "$DMG_STAGE" -format UDZO "$TMP_DMG"
  /usr/bin/codesign --force --timestamp --sign "$SIGN_ID" "$TMP_DMG"
  /usr/bin/xcrun notarytool submit "$TMP_DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m | tee "$BUILD_STAGE/notarise-dmg.log"
  grep -q "status: Accepted" "$BUILD_STAGE/notarise-dmg.log" || { /bin/rm -f "$ARCHIVE_PATH"; print -u2 "Disk image notarisation was not accepted (see the log above); $ARCHIVE_PATH removed again."; exit 1; }
  /usr/bin/xcrun stapler staple "$TMP_DMG"
  /usr/bin/xcrun stapler validate "$TMP_DMG"
  /usr/sbin/spctl -a -vv -t open --context context:primary-signature "$TMP_DMG"
  /bin/cp -n "$TMP_DMG" "$DMG_PATH"
  print "Disk image: ${DMG_PATH:A}"
fi
if (( NOTARISED )); then print "Developer ID signed, notarised and stapled app: ${APP_PATH:A}"
elif [[ "$SIGN_ID" == "-" ]]; then print "Local ad-hoc-signed development app: ${APP_PATH:A}"
else print "Developer ID signed app, not notarised (SCOREBUG_NOTARISE=0): ${APP_PATH:A}"; fi
print "Archive: ${ARCHIVE_PATH:A}"
