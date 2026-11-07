#!/bin/zsh
# Render native SwiftUI content without opening a window. Build first; this does not install anything.
# Renders under the app's safe scratch root. With SCOREBUG_SNAPSHOTS set, copies only the PNGs, layout probes and
# report there afterwards and deletes the run; otherwise the images stay in the run folder it prints.
set -euo pipefail
repo=${0:A:h:h}
out=${SCOREBUG_SNAPSHOTS:-}
if [[ -n $out ]]; then
    dest=${out:A}
    case $dest in
        /|/Users|/Volumes|/System|/System/*|/Library|/Library/*|/Applications|/Applications/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/private|/private/etc|/private/etc/*|/private/var|/private/var/db|/private/var/db/*|$HOME|$HOME/Library|$HOME/Library/*|$repo|$repo/*)
            print -u2 "FAIL: unsafe snapshot output $dest (a system, home, Library, production data or checkout folder)"; exit 1 ;;
    esac
    [[ ! -e $dest || -d $dest ]] || { print -u2 "FAIL: unsafe snapshot output $dest is not a folder"; exit 1; }
    # Only replace what an earlier snapshot run left; never write into a folder holding anything else.
    if [[ -d $dest ]] && (( $(find "$dest" -mindepth 1 ! -name '*.png' ! -name '*-layout.json' ! -name report.json | wc -l) )); then
        print -u2 "FAIL: unsafe snapshot output $dest holds files that are not snapshots"; exit 1
    fi
fi
source "${0:A:h}/agent-launch.zsh"
agent_setup "${1:-${SCOREBUG_SCRATCH:-$safe}/release/Scorebug}" native-snapshots
[[ -n $out ]] || agent_keep_run=1
trap agent_cleanup EXIT
mkdir -p "$run/images"
CFFIXED_USER_HOME="$run/home" SCOREBUG_NATIVE_SNAPSHOTS="$run/images" SCOREBUG_SNAPSHOT=1 \
    deadline 180 "$app" --data-directory "$run/data" --background --agent-screen
python3 - "$run/images/report.json" <<'PY'
import hashlib, json, pathlib, sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert report['status'] == 'PASS' and report['count'] == 22, report
names = {image['name'] for image in report['images']}
for name in ['primary', 'secondary', 'library', 'library-club', 'library-competition',
             'library-icons', 'settings-obs', 'settings-live-data', 'settings-advanced',
             'slot-1-zoom-2', 'slot-2-zoom-2']:
    for appearance in ['light', 'dark']:
        assert f'{name}-{appearance}' in names, (name, appearance)
for image in report['images']:
    path = pathlib.Path(sys.argv[1]).parent / image['file']
    assert path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), path
    assert image['width'] > 0 and image['height'] > 0 and image['bytes'] > 2000, image
    assert image['sampledColourCount'] >= 8, image
for name in ['primary', 'secondary', 'library', 'settings-obs', 'settings-live-data', 'settings-advanced']:
    light = pathlib.Path(sys.argv[1]).parent / f'{name}-light.png'
    dark = pathlib.Path(sys.argv[1]).parent / f'{name}-dark.png'
    assert hashlib.sha256(light.read_bytes()).digest() != hashlib.sha256(dark.read_bytes()).digest(), name
print(f"PASS: verified {report['count']} PNGs covering every page in light and dark")
print('Live visual check still needed for active window chrome, menus and WebKit previews.')
PY

swift "$repo/tools/check-layout.swift" "$run"/images/*-layout.json
if [[ -n $out ]]; then
    mkdir -p "$dest"
    cp "$run"/images/*.png "$run"/images/*-layout.json "$run"/images/report.json "$dest/"
    # The copies must not name the disposable run, its home or data folder.
    if grep -rlF -e "$run" -e "$HOME" "$dest" >/dev/null; then print -u2 "FAIL: snapshot output names a private path"; exit 1; fi
    print "Snapshots: $dest ($(ls "$dest"/*.png | wc -l | tr -d ' ') PNGs)"
else
    print "Report: $run/images/report.json"
fi
