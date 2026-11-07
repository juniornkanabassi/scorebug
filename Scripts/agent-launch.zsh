# Sourced by the native checks that launch a SwiftPM build of the app. Gives each run a disposable folder under the
# app's safe root and a uniquely named link to the binary, so its preferences land in a throwaway defaults domain
# (CFFIXED_USER_HOME does not move UserDefaults) that is deleted on exit. Every launch has a deadline.
safe=/private/tmp/bama/build-scorebug   # must match NativeSnapshots.scratch

# agent_setup <binary> <name>: sets $run, $domain and $app (the link to launch). Callers then run
# `trap agent_cleanup EXIT` themselves: in zsh a trap set inside a function fires when that function returns.
agent_setup() {
    local binary=$1
    [[ -x $binary ]] || { print -u2 "FAIL: build Scorebug first at $binary"; exit 1; }
    # Inside a bundle the link would still use the bundle's (real) preferences domain.
    [[ ${binary:A} != *.app/* ]] || { print -u2 "FAIL: use a SwiftPM build, not an app bundle: $binary"; exit 1; }
    mkdir -p "$safe"
    run=$(mktemp -d "$safe/$2.XXXXXX")
    domain="Scorebug-$2-${run:e}"
    app="$run/$domain"
    ln -s "${binary:A}" "$app"
    mkdir -p "$run/home" "$run/data"
}

agent_cleanup() {
    if [[ -n ${domain:-} ]]; then
        defaults delete "$domain" >/dev/null 2>&1 || true
        rm -f "$HOME/Library/Preferences/$domain.plist"
    fi
    rm -rf "$run/home" "$run/data" "$app"
    if [[ ${agent_keep_run:-0} != 1 ]]; then rm -rf "$run"; fi
}

# deadline <seconds> <command...>: the process is killed by SIGALRM if it outlives the deadline.
deadline() { perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$@"; }
