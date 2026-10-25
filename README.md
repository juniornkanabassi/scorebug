# Scorebug source

In the canonical `Scorebug/Source` checkout, read `../AGENTS.md` and `../00 Project State/ARCHITECTURE-ESSENTIALS.md` first. In a worktree, read those files in the Scorebug project folder; the worktree's parent may belong to another app.

Build and check:

```sh
swift build --scratch-path /private/tmp/scorebug-build
swift run --scratch-path /private/tmp/scorebug-build CoreChecks
zsh install.sh    # builds, signs (Developer ID when available, otherwise ad hoc) and installs at "/Applications/JuniorOS Apps/Scorebug.app", then opens it
zsh build.sh      # writes ../Outputs/Scorebug <version>.zip, for handing the app to someone else
```

`install.sh` is the everyday path: it refuses a running app, preserves the previous copy until staging succeeds, then replaces `/Applications/JuniorOS Apps/Scorebug.app` and opens the fresh build, no zip step, no application data touched. `build.sh` writes `../Outputs/Scorebug <version>.zip` and refuses to overwrite; it does not install anything. When the Developer ID certificate (SHA-1 `C297CD17…9400`) is in the keychain it signs with the hardened runtime, notarises with the `JuniorOS` notarytool profile, staples the app and also writes a notarised `../Outputs/Scorebug <version>.dmg` for the website; `SCOREBUG_NOTARISE=0` skips notarisation. Version in `Resources/Info.plist`, tagged `v<version>` here. `CFBundleVersion` is a whole build number that goes up with every release (4 for 1.0.3), as Sparkle requires.

The bundle identifier is `com.juniornkanabassi.Scorebug`, chosen before the first public release. Earlier builds were `local.scorebug.mac`: the first launch of the renamed app copies that domain's preferences across once, and the keychain item for the football-data key keeps the old service name so it is not lost.

Run without installing, on a disposable data folder:

```sh
/private/tmp/scorebug-build/debug/Scorebug --data-directory /private/tmp/scorebug-data --port 8680 --screen "Prompter XL"
```

Launch flags: `--data-directory <folder>` (a disposable copy instead of `~/Library/Application Support/Scorebug/`), `--overlays-directory <folder>` (points at an Overlays folder explicitly; otherwise the app locates the bundled `Resources/Overlays` itself), `--port <n>` (defaults to `8600`), `--import-crests <folder>` (a one-off import of a crest folder at launch, filling in only the crests still missing; the default import only ever runs on a first run).
- `--screen "<display name>"` opens the window on that display once, at launch, and never takes focus; a later drag to another display sticks. Agents' test instances and `install.sh` pass `--screen "Prompter XL"`.
- `SCOREBUG_TEST_KEYS=1` in the environment enables `POST /api/test/key` (`{"keyCode":125,"characters":"","modifiers":[]}`), which posts a key down and up into the key window so tests can drive the arrow-key navigation and zoom without touching the keyboard. Absent the variable the route is a 404.

Then open `http://127.0.0.1:8680/` for the source list, `/overlay/h/1` or `/overlay/v/1` for the pages, and post commands to `/api/match/1/command` as JSON (`{"command":"goal","side":"home"}`).

Overlays are in `Resources/Overlays/`; during development the app finds them from the source tree, and `build.sh` copies them into the bundle.

The 1.0.1 candidate refreshes replaced crests and competition logos without reloading them on every score update. Live goals use ESPN's event IDs when available, so removing a goal still works after its minute is corrected. Re-linking a swapped fixture restores its orientation when the feed's team names match.

1.0.2 lets an open overlay page recover its theme. If theme.json or theme.css fails, the page retries on its 30-second state poll or its next socket reconnect, with no reload and no new match revision. Start Scorebug before OBS. If OBS opens a browser source while the server is down, it shows a navigation error page that runs no overlay script and cannot recover. Use Refresh on that source once Scorebug is serving. This repairs one proven cause of blank OBS sources, not every recorded one.

1.0.3 never shows an overlay a change that was not saved. If writing `state.json` fails (a full disk, say), the command is undone, nothing is broadcast, the window shows "Could not save state" and API responses carry `X-Scorebug-Save-Failed: true`; retry once the disk is fixed. Overlay snapshots read settings and competitions as last saved, so an unsaved setting or competition edit stays in the window until a save succeeds.

If ESPN omits a goal ID or supplies ambiguous details, matching falls back to the minute. A previously removed goal can then reappear. Keep automatic updates off when this happens and use the manual controls. Unrecognised team names keep the saved orientation.

## AI control

Accepted localhost-only limitation (review 6): FlyingFox 0.27.1 decodes request lines and headers without a size cap or decoding deadline; the handler timeout starts afterwards. Only local processes can grow or stall headers indefinitely. Revisit if the listener binds beyond loopback or upstream adds limits; do not vendor or fork FlyingFox.

Scorebug 1.0.0 ships `scorebug`, a Node CLI over the existing localhost HTTP API, and a thin MCP stdio adapter. They call the same app actions as the window; changes update the running GUI. Node 24 or later is required. `scorebug --help` and per-command help list flags, effects and examples. The installer links the bundled script into `~/.local/bin/scorebug`; without installing, use `node Scripts/scorebug.mjs` or the bundled `Contents/Resources/Scripts/scorebug.mjs`.

| Command | Example |
|---|---|
| status | `scorebug status --json` |
| match set | `scorebug match set --home "Real Madrid" --away Inter --competition ucl --first-leg 2-1` |
| show | `scorebug show --slot 1` |
| hide | `scorebug hide --slot 1` |
| reset | `scorebug reset --yes` |
| goal add | `scorebug goal add --side home --minute 23 --scorer "Test" --request-id g1` |
| goal remove | `scorebug goal remove --side home` |
| clock start | `scorebug clock start --period firstHalf` |
| clock stop | `scorebug clock stop` |
| clock adjust | `scorebug clock adjust --by -5` (or `--to 44:30`) |
| fixture list | `scorebug fixture list --date today --competition ucl` |
| fixture load | `scorebug fixture load --date today --competition ucl --pick 1` |
| theme list | `scorebug theme list` |
| theme set | `scorebug theme set --id nations-league` (or `--id default`) |
| mcp-manifest | `scorebug mcp-manifest` |

Use `--port <n>` or `SCOREBUG_PORT` for disposable instances, `--slot 1|2` for match actions, and `--json` for `{ok,result}` or `{ok:false,error:{code,message}}`. Exit 0 means success, 1 action error, 2 usage. `status` never launches and returns `running:false` with exit 0 offline (plain output says "not running"); older apps report version `unknown`. Other commands launch the installed app in the background only when port 8600 refuses the connection, unless `--no-launch`. Timeouts and resets are never retried. `--show` explicitly opens the installed window and takes focus; it only works on port 8600.

`match set --dry-run` resolves without changing anything, `--force` accepts a weak match or replaces a live slot, and `--keep-score` retains play. A competition alone changes only the competition. `reset` requires `--yes`. Goal retry ids are scoped to slot and the last 500 successful responses of this app session; keep ids unique across actions. Goal CLI ids allow 121 characters so scorer/minute suffixes fit the API's 128-character bound. `goal remove --goal-id <UUID>` removes a specific goal. Clock `--to` is cumulative time, including the period base. Fixtures need provider access; no network is needed for other commands.

The manifest's 14 tool schemas come from the CLI command table. MCP supports protocol `2025-06-18` with initialize, notifications/initialized, tools/list, tools/call and ping. Configure Claude with the absolute Node path printed by the installer:

```sh
claude mcp add scorebug -- /absolute/path/to/node "/Applications/JuniorOS Apps/Scorebug.app/Contents/Resources/mcp/scorebug-mcp.mjs"
```

For `~/.codex/config.toml`:

```toml
[mcp_servers.scorebug]
command = "/absolute/path/to/node"
args = ["/Applications/JuniorOS Apps/Scorebug.app/Contents/Resources/mcp/scorebug-mcp.mjs"]
```

The adapter uses only Node built-ins and forwards tools to the CLI; this small shim may be copied to other JuniorOS apps with its CLI path changed. The supported CLI and app versions are 1.0.0 or later, apart from older-app status. Scorebug keeps HTTP on 127.0.0.1, with no Unix socket. Host, Origin and JSON content type are checked for every request. Added time, shootout, live-data linking, library edits and settings remain on the API, window and Stream Deck. No token savings have been measured.

Disposable checks: `node Scripts/scorebug-check.mjs`, `SCOREBUG_PORT=8680 node Scripts/security-check.mjs`, `SCOREBUG_PORT=8680 node Scripts/mcp-check.mjs`, and `node Scripts/plugin-check.mjs` after building the plugin. `SCOREBUG_INSTALL_ROOT` makes installation inert: no launch, registration, production quit or CLI symlink.

Review regressions: `sh Scripts/model-check.sh` compiles the actual model and server with canned provider responses and disposable data; `node Scripts/overlay-check.mjs` and `node Scripts/plugin-command-check.mjs` exercise the actual overlay and shared plugin client without a browser or Stream Deck. The model check needs Python 3 and can reuse a scratch build via `SCOREBUG_BUILD_ROOT`; all its default paths are under `/private/tmp/fix-scorebug-*`.

## Local verification [2026-10-01]

Fix round 2 on `release-2026-09-30`: debug/release builds and ad hoc signing pass; 206 CoreChecks, 53 CLI, 27 security runtime, 11 bundled MCP, 20 bundled CLI and 14 plugin checks pass (331 total). Plugin build and Elgato validation pass. The header decoder observation reports the accepted limitation above.

`git log -p --all` was scanned for API/token key prefixes, long hex strings and private-key markers: no secrets detected. The only two long-hex candidates are SwiftPM `originHash` and FlyingFox revision fields in `Package.resolved`. Ignore rules cover local media, data/library/crest stores, logs, `.env` and zip archives. The signed test archive is under `/private/tmp/scorebug-fix2`, not Outputs. Runtime checks use a disposable data directory and isolated `CFFIXED_USER_HOME`; test PID was stopped. Native UI/hardware acceptance was not rerun in this shell-only round.
