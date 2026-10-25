#!/bin/zsh
# Builds Scorebug, signs it (Developer ID when available, otherwise ad hoc) and installs it as "/Applications/JuniorOS Apps/Scorebug.app" (SCOREBUG_INSTALL_ROOT overrides the folder for disposable tests), replacing the previous copy, then opens it.
# Like Content Template: no zip to unpack, just the app in Applications.
set -euo pipefail
cd "${0:A:h}"
INSTALL_ROOT="${SCOREBUG_INSTALL_ROOT:-/Applications/JuniorOS Apps}"
DEST="$INSTALL_ROOT/Scorebug.app"
STAGE=$(mktemp -d /private/tmp/scorebug-install.XXXXXX)
# build.sh's own bundle: Sparkle embedded and signed inside-out, updates off unless Developer ID with a real key.
# Not notarised by default (SCOREBUG_NOTARISE=1 to notarise); the archive goes to this stage, never Outputs.
# A disposable install (SCOREBUG_INSTALL_ROOT) is signed ad hoc, so build.sh strips its feed and it can never update.
LOCAL_SIGNING="${SCOREBUG_LOCAL_SIGNING:-}"
[[ -z "${SCOREBUG_INSTALL_ROOT+x}" ]] || LOCAL_SIGNING=1
SCOREBUG_LOCAL_SIGNING="$LOCAL_SIGNING" SCOREBUG_NOTARISE="${SCOREBUG_NOTARISE:-0}" SCOREBUG_OUTPUT_ROOT="$STAGE/out" zsh ./build.sh
/usr/bin/ditto -x -k "$STAGE/out/Scorebug $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist).zip" "$STAGE"
APP="$STAGE/Scorebug.app"

/usr/bin/codesign --verify --deep --strict "$APP"
# Refuse before replacing either a production or disposable app that is running.
if pgrep -f "$DEST/Contents/MacOS/Scorebug" >/dev/null; then
  print -u2 "Scorebug is running at $DEST; quit it first. Nothing replaced."
  exit 1
fi
mkdir -p "$INSTALL_ROOT"
NEW_DEST=$(mktemp -d "$INSTALL_ROOT/.Scorebug-new.XXXXXX")
/usr/bin/ditto "$APP" "$NEW_DEST/Scorebug.app"
/usr/bin/codesign --verify --deep --strict "$NEW_DEST/Scorebug.app"
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
