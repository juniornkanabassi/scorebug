#!/bin/sh
# Exercise the real AppModel and OverlayServer, with canned provider responses and disposable data.
set -eu
cd "$(dirname "$0")/.."
TASK_ROOT="${SCOREBUG_CHECK_ROOT:-$(mktemp -d /private/tmp/fix-scorebug-model.XXXXXX)}"
BUILD_ROOT="${SCOREBUG_BUILD_ROOT:-$TASK_ROOT/build}"
mkdir -p "$TASK_ROOT/home" "$TASK_ROOT/tmp"
export TMPDIR="$TASK_ROOT/tmp" CFFIXED_USER_HOME="$TASK_ROOT/home"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-cache"
swift build --scratch-path "$BUILD_ROOT" --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --product Scorebug
BIN_PATH=$(swift build --scratch-path "$BUILD_ROOT" --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --show-bin-path)
# Compile the actual squad getters so changing their side selection breaks the own-goal regression.
python3 - "$TASK_ROOT/GoalPromptProbe.swift" <<'PY'
import pathlib, re, sys
source = pathlib.Path('Sources/Scorebug/Views/GoalPrompt.swift').read_text()
properties = re.findall(r'^    private var (?:match|linkedLineup|scoringSquad|otherSquad):.*$', source, re.M)
assert len(properties) >= 3
pathlib.Path(sys.argv[1]).write_text('import ScorebugCore\n@MainActor struct GoalPromptProbe { let model: AppModel; let goal: Goal; let slot: Int\n' + '\n'.join(x.replace('private var', 'var', 1) for x in properties) + '\n}\n')
PY
swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD_ROOT/swift-cache" -I "$BIN_PATH" \
  "$BIN_PATH/ScorebugCore.o" "$BIN_PATH/FlyingFox.o" "$BIN_PATH/FlyingSocks.o" \
  Sources/Scorebug/AppModel.swift Sources/Scorebug/OverlayServer.swift Scripts/ModelChecks/Stubs.swift \
  "$TASK_ROOT/GoalPromptProbe.swift" Scripts/ModelChecks/main.swift -o "$TASK_ROOT/ModelChecks"
export SCOREBUG_CHECK_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
"$TASK_ROOT/ModelChecks"
