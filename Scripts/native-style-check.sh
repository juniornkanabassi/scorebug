#!/bin/zsh
set -euo pipefail
repo=${0:A:h:h}
mkdir -p /private/tmp/bama/build-scorebug
scratch=$(mktemp -d /private/tmp/bama/build-scorebug/native-style-check.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/module-cache"
clang -c "$repo/Tests/TestOffscreen/TestOffscreen.m" -I "$repo/Tests/TestOffscreen/include" -o "$scratch/TestOffscreen.o"
swiftc -module-cache-path "$scratch/module-cache" \
  "$repo/Sources/Scorebug/UI/Surfaces.swift" \
  "$repo/Sources/Scorebug/UI/SidebarSection.swift" \
  "$repo/Sources/Scorebug/UI/ColorHex.swift" \
  "$repo/Sources/Scorebug/Views/Slot/MatchCommandContext.swift" \
  "$repo/Sources/Scorebug/UI/MatchCommandGate.swift" "$repo/Scripts/NativeStyleChecks/main.swift" \
  "$scratch/TestOffscreen.o" -o "$scratch/NativeStyleChecks"
"$scratch/NativeStyleChecks"
