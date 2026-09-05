# Scorebug source

Read `../AGENTS.md` and `../00 Project State/ARCHITECTURE-ESSENTIALS.md` first.

Build and check:

```sh
swift build --scratch-path /private/tmp/scorebug-build
swift run --scratch-path /private/tmp/scorebug-build CoreChecks
zsh build.sh
```

`build.sh` writes `../Outputs/Scorebug <version>.zip` and refuses to overwrite. Version in `Resources/Info.plist`, tagged `v<version>` here.

Run without installing, on a disposable data folder:

```sh
/private/tmp/scorebug-build/debug/Scorebug --data-directory /private/tmp/scorebug-data --port 8600
```

Then open `http://localhost:8600/` for the source list, `/overlay/h/1` or `/overlay/v/1` for the pages, and post commands to `/api/match/1/command` as JSON (`{"command":"goal","side":"home"}`).

Overlays are in `Resources/Overlays/`; during development the app finds them from the source tree, and `build.sh` copies them into the bundle.
