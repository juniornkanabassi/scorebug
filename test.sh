#!/bin/zsh
# Every headless check in one run, locally and in CI. One debug build is reused by all steps. Nothing shows a
# window, takes focus, opens an app, plays sound, loads a network fixture or reads Junior's real data or preferences.
#   SCOREBUG_SCRATCH    build scratch (default /private/tmp/bama/build-scorebug)
#   SCOREBUG_SNAPSHOTS  where the 32 light and dark PNGs are copied (default: left in the run folder it prints)
# Not here: security-check, acceptance-check, mcp-check and bundled-check need a running app; plugin-check needs the
# built Stream Deck plugin (bin/plugin.js is not in git). See REVIEW.md.
set -euo pipefail
cd "${0:A:h}"
export SCOREBUG_SCRATCH=${SCOREBUG_SCRATCH:-/private/tmp/bama/build-scorebug}
build=(--scratch-path "$SCOREBUG_SCRATCH")
binary="$SCOREBUG_SCRATCH/debug/Scorebug"
passed=0

# step <seconds> <label> <command...>: runs in its own process group, killed whole if it outlives the deadline.
step() {
    local limit=$1 label=$2; shift 2
    print "== $label"
    perl -e 'my $t = shift; my $pid = fork // die "fork: $!\n";
        if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec: $!\n" }
        $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; die "FAIL: timed out after ${t}s\n" };
        $SIG{INT} = $SIG{TERM} = sub { kill "TERM", -$pid; exit 130 };
        alarm $t; waitpid($pid, 0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$limit" "$@"
    passed=$((passed + 1))
}

step 900 "Build" swift build "${build[@]}"
step 600 "Invisible test windows and launch flags (swift test)" swift test "${build[@]}"
step 300 "Core engine assertions (CoreChecks)" swift run "${build[@]}" CoreChecks
step 900 "Real AppModel and OverlayServer, canned providers (model-check)" \
    env SCOREBUG_BUILD_ROOT="$SCOREBUG_SCRATCH/model-check" zsh Scripts/model-check.sh
step 300 "Native style tokens and sidebar pages (native-style-check)" zsh Scripts/native-style-check.sh
step 60 "4 pt grid lint" zsh tools/grid-lint.sh
step 120 "Overlay script against a minimal DOM" node Scripts/overlay-check.mjs
step 120 "Stream Deck plugin client, transport stubbed" node Scripts/plugin-command-check.mjs
step 300 "CLI and MCP manifest against a fake server" node Scripts/scorebug-check.mjs
step 300 "Snapshot mode refuses unsafe paths" python3 Scripts/native-snapshot-safety-check.py "$binary"
step 300 "Light and dark snapshots of every native page, layout probes" zsh Scripts/native-snapshots.sh "$binary"
step 300 "Sidebar page survives quit and relaunch" zsh Scripts/sidebar-restore-check.sh "$binary"
print "PASS: all $passed steps"
