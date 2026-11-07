#!/bin/zsh
# Real launches of the app, invisible, with a disposable home, data folder, defaults domain and spare port: pick a
# sidebar page, quit, relaunch and check the new window opens on that page. Builds nothing; no window shows, no
# network fixture load, no open, no real preferences.
set -euo pipefail
source "${0:A:h}/agent-launch.zsh"
agent_setup "${1:-${SCOREBUG_SCRATCH:-$safe}/release/Scorebug}" sidebar-restore
trap agent_cleanup EXIT
plist="$HOME/Library/Preferences/$domain.plist"
real_before=$(for d in Scorebug com.juniornkanabassi.Scorebug; do defaults read "$d" lastSidebarSection 2>/dev/null || print none; done)
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
launches=0

# One launch with a 60 s deadline; checks the page the new window opened on, as the app's probe reported it.
expect() {
    launches=$((launches + 1))
    local log="$run/launch-$launches.log"
    if ! SCOREBUG_SIDEBAR_PROBE=$1 CFFIXED_USER_HOME="$run/home" deadline 60 "$app" --data-directory "$run/data" --port "$port" --agent-screen >"$log" 2>&1; then
        print -u2 "FAIL: launch $launches ($1) did not quit cleanly"; cat "$log" >&2; exit 1
    fi
    local line=$(grep '^SIDEBAR_PROBE ' "$log" | tail -1)
    [[ -n $line ]] || { print -u2 "FAIL: launch $launches ($1) never showed the main window"; cat "$log" >&2; exit 1; }
    [[ ${line##*shown=} == "$2" ]] || { print -u2 "FAIL: launch $launches ($1) showed ${line##*shown=}, expected $2"; exit 1; }
    print "PASS: launch $launches ($1) showed $2"
}

expect report primary                 # first launch, nothing remembered
expect select:library library
expect report library                 # the regression: restoration is off, the page must still come back
expect select:secondary secondary
expect report secondary
[[ $(defaults read "$domain" lastSidebarSection) == secondary && -f $plist ]] \
    || { print -u2 "FAIL: remembered page not in the throwaway domain $domain"; exit 1; }
print "PASS: remembered page stored in the throwaway domain only"

defaults write "$domain" lastSidebarSection not-a-page   # a stored value the app does not know opens Primary
expect report primary

real_after=$(for d in Scorebug com.juniornkanabassi.Scorebug; do defaults read "$d" lastSidebarSection 2>/dev/null || print none; done)
[[ $real_before == "$real_after" ]] || { print -u2 "FAIL: a real preferences domain changed"; exit 1; }
print "PASS: sidebar page restored across $launches invisible launches; real preferences untouched"
