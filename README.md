# Scorebug source

Read `../AGENTS.md` and `../00 Project State/ARCHITECTURE-ESSENTIALS.md` first.

Build and check:

```sh
swift build --scratch-path /private/tmp/scorebug-build
swift run --scratch-path /private/tmp/scorebug-build CoreChecks
zsh install.sh    # builds, ad hoc signs and installs at /Applications/Scorebug.app, then opens it
zsh build.sh      # writes ../Outputs/Scorebug <version>.zip, for handing the app to someone else
```

`install.sh` is the everyday path: it replaces whatever is at `/Applications/Scorebug.app` and opens the fresh build, no zip step, no application data touched. `build.sh` writes `../Outputs/Scorebug <version>.zip` and refuses to overwrite; it does not install anything. Version in `Resources/Info.plist`, tagged `v<version>` here.

Run without installing, on a disposable data folder:

```sh
/private/tmp/scorebug-build/debug/Scorebug --data-directory /private/tmp/scorebug-data --port 8600
```

Launch flags: `--data-directory <folder>` (a disposable copy instead of `~/Library/Application Support/Scorebug/`), `--overlays-directory <folder>` (points at an Overlays folder explicitly; otherwise the app locates the bundled `Resources/Overlays` itself), `--port <n>` (defaults to `8600`), `--import-crests <folder>` (a one-off import of a crest folder at launch, filling in only the crests still missing; the default import only ever runs on a first run).
- `--screen "<display name>"` opens the window on that display once, at launch, and never takes focus; a later drag to another display sticks. Agents' test instances and `install.sh` pass `--screen "Prompter XL"`.
- `SCOREBUG_TEST_KEYS=1` in the environment enables `POST /api/test/key` (`{"keyCode":125,"characters":"","modifiers":[]}`), which posts a key down and up into the key window so tests can drive the arrow-key navigation and zoom without touching the keyboard. Absent the variable the route is a 404.

Then open `http://localhost:8600/` for the source list, `/overlay/h/1` or `/overlay/v/1` for the pages, and post commands to `/api/match/1/command` as JSON (`{"command":"goal","side":"home"}`).

Overlays are in `Resources/Overlays/`; during development the app finds them from the source tree, and `build.sh` copies them into the bundle.
