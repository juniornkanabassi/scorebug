# Review guide

How to review changes to Scorebug. The shared rules (lanes, check results, finding format, the three-round checkpoint, approval of an exact revision) are in the owner's JuniorOS `03 Skills/Review workflow.md`. This file holds only what is specific here. Severity is Important, Nit (at most three, never blocking) or Pre-existing. Start the summary with the count. 0 findings is a valid result.

## Failure here means

- Unsaved or failed state reaches OBS (only successfully saved state may be broadcast).
- A change lands in the wrong match slot.
- A retry repeats a command's effect (a double goal, a double clock start).
- The overlay does not reconnect after the server restarts.
- The local server accepts requests from outside localhost or without the expected headers.

## Always High

The save-then-broadcast path, the overlay server, the Stream Deck plugin commands, `release.sh`, `install.sh`.

## Always check

- Disposable data and a spare port; never Junior's live OBS during a stream.

## Check results

Last results on 1 Nov 2026, revision `7924329`. `.github/workflows/fast-checks.yml` runs the first four on pull requests (macOS 15, read-only, no secrets); it has not run on GitHub yet. Report every check you run as PASS, FAIL, NOT RUN or NOT APPLICABLE with the revision.

| Command | Proves | 1 Nov |
|---|---|---|
| `swift run --scratch-path /private/tmp/scorebug-build CoreChecks` | the match engine and core rules | PASS, 247 |
| `zsh Scripts/model-check.sh` | the real AppModel and OverlayServer with canned providers | PASS, 73 |
| `node Scripts/overlay-check.mjs` | the production overlay script with a minimal DOM | PASS, 156 |
| `node Scripts/plugin-command-check.mjs` | the Stream Deck client without Stream Deck | PASS |
| `SCOREBUG_PORT=<spare port> node Scripts/security-check.mjs` | localhost and header rules against a running app (disposable data) | NOT RUN (needs a running app on a spare port) |
| `node Scripts/acceptance-check.mjs` | cumulative API and overlay lines | NOT RUN (needs a running app) |

## Skip

`Resources/` images and fonts, `StreamDeckPlugin/node_modules/` and `StreamDeckPlugin/logs/`, `docs/`.

## Known gaps

OBS and Stream Deck hardware checks need Junior's setup and are owed.

Tests and launch checks must never show windows or take focus: the TestOffscreen guard is a dependency of every test target, and real-app checks pass the invisible flag. Never use open, computer use or a visible Simulator in tests (6 Nov 2026).
