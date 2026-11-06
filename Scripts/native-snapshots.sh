#!/bin/zsh
# Render native SwiftUI content without opening a window. Build first; this does not install anything.
set -euo pipefail
scratch=/private/tmp/bama/build-scorebug
binary=${1:-$scratch/release/Scorebug}
if [[ ! -x "$binary" ]]; then
    print -u2 "FAIL: build Scorebug first at $binary"
    exit 1
fi
mkdir -p "$scratch"
run=$(mktemp -d "$scratch/native-snapshots.XXXXXX")
mkdir -p "$run/home" "$run/data" "$run/images"
CFFIXED_USER_HOME="$run/home" SCOREBUG_NATIVE_SNAPSHOTS="$run/images" SCOREBUG_SNAPSHOT=1 \
    "$binary" --data-directory "$run/data" --background --agent-screen &
pid=$!
trap 'if [[ -n ${pid:-} ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$run/home" "$run/data"' EXIT
wait "$pid"
pid=""
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
print(f"Report: {sys.argv[1]}")
print('Live visual check still needed for active window chrome, menus and WebKit previews.')
PY

swift "${0:A:h:h}/tools/check-layout.swift" "$run"/images/*-layout.json
