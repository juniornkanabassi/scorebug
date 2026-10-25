#!/bin/zsh
# Builds Scorebug, signs it (Developer ID when available, otherwise ad hoc) and installs it as "/Applications/JuniorOS Apps/Scorebug.app" (SCOREBUG_INSTALL_ROOT overrides the folder for disposable tests), replacing the previous copy, then opens it.
# Like Content Template: no zip to unpack, just the app in Applications.
set -euo pipefail
cd "${0:A:h}"
BUILD_ROOT="${SCOREBUG_BUILD_ROOT:-/private/tmp/scorebug-build}"
INSTALL_ROOT="${SCOREBUG_INSTALL_ROOT:-/Applications/JuniorOS Apps}"
DEST="$INSTALL_ROOT/Scorebug.app"
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
mkdir -p "$APP/Contents/Resources/Scripts" "$APP/Contents/Resources/mcp"
cp Scripts/scorebug.mjs Scripts/match-lib.mjs "$APP/Contents/Resources/Scripts/"
cp mcp/scorebug-mcp.mjs "$APP/Contents/Resources/mcp/"

[[ -f Resources/squads.json ]] && cp Resources/squads.json "$APP/Contents/Resources/squads.json"
# The Developer ID identity, when present, keeps one stable signature across rebuilds, so the keychain item holding
# the football-data key stops asking for access after every install. Ad hoc otherwise. No notarisation here.
DEV_ID_SHA="C297CD17464A0EF6C93704A59BC2E1D4D1759400"
SIGN_ID="-"
if /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_ID_SHA"; then SIGN_ID="$DEV_ID_SHA"; fi
/usr/bin/codesign --force --options runtime --sign "$SIGN_ID" "$APP"

/usr/bin/codesign --verify --strict "$APP"
# Refuse before replacing either a production or disposable app that is running.
if pgrep -f "$DEST/Contents/MacOS/Scorebug" >/dev/null; then
  print -u2 "Scorebug is running at $DEST; quit it first. Nothing replaced."
  exit 1
fi
mkdir -p "$INSTALL_ROOT"
NEW_DEST=$(mktemp -d "$INSTALL_ROOT/.Scorebug-new.XXXXXX")
/usr/bin/ditto "$APP" "$NEW_DEST/Scorebug.app"
/usr/bin/codesign --verify --strict "$NEW_DEST/Scorebug.app"
BACKUP="$NEW_DEST/previous.app"
[[ ! -e "$DEST" ]] || mv "$DEST" "$BACKUP"
if ! mv "$NEW_DEST/Scorebug.app" "$DEST"; then
  [[ ! -e "$BACKUP" ]] || mv "$BACKUP" "$DEST"
  exit 1
fi
rm -rf "$NEW_DEST" "$STAGE"
if [[ -z "${SCOREBUG_INSTALL_ROOT+x}" ]]; then
  touch "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$DEST/Contents/Resources/Scripts/scorebug.mjs" "$HOME/.local/bin/scorebug"
  open -g "$DEST" --args --screen "Prompter XL"
fi
NODE_PATH=$(command -v node)
SHIM_PATH="$DEST/Contents/Resources/mcp/scorebug-mcp.mjs"
print "Built and copied $DEST ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist))"
print "claude mcp add scorebug -- $NODE_PATH \"$SHIM_PATH\""
print '[mcp_servers.scorebug]'
print "command = \"$NODE_PATH\""
print "args = [\"$SHIM_PATH\"]"
