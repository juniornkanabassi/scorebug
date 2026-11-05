#!/bin/zsh
set -euo pipefail
repo=${0:A:h:h}
scratch=/private/tmp/bama/build-scorebug/native-style-check
mkdir -p "$scratch/module-cache"
swiftc -module-cache-path "$scratch/module-cache" \
  "$repo/Sources/Scorebug/UI/Surfaces.swift" \
  "$repo/Sources/Scorebug/UI/SidebarSection.swift" \
  "$repo/Sources/Scorebug/UI/ErrorPresentation.swift" "$repo/Scripts/NativeStyleChecks/main.swift" \
  -o "$scratch/NativeStyleChecks"
"$scratch/NativeStyleChecks"
