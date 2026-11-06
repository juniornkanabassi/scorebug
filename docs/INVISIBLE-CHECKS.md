# Invisible test and launch validation

Validated 6 November 2026 on macOS, on `no-windows-guard` based on `02f80d9`.
The committed source includes the exact, byte-for-byte TestOffscreen .m, .h and proof test from Video Prompter `a28a30c`.

The test bundle and both standalone AppKit check executables link TestOffscreen. Real app checks pass `--agent-screen`; a conditional constructor applies the same pre-order/alpha/activation hooks before SwiftUI starts, with the original didUpdate observer as a backstop. Hosted XCTest and native snapshot launches also enable the guard automatically. The installer leaves the app closed. No version change or production data migration.

## Checks

All PASS against the final implementation, using disposable homes/data, spare ports and an ad-hoc signed packaged app:

| Check | Result |
| --- | --- |
| `swift test` | 2 tests, 0 failures |
| `swift run CoreChecks` | 247 checks |
| `zsh Scripts/model-check.sh` | 84 checks |
| `zsh Scripts/native-style-check.sh` | 51 assertions |
| `node Scripts/overlay-check.mjs` | 156 checks |
| `node Scripts/plugin-command-check.mjs` | 21 checks |
| Plugin build and `node Scripts/plugin-check.mjs` | 14 checks |
| `node Scripts/scorebug-check.mjs` | 266 checks |
| `zsh tools/grid-lint.sh` | PASS |
| `zsh install.sh` with disposable install/build roots | Build, signing, strict signature verification and installation PASS |
| `python3 Scripts/native-snapshot-safety-check.py <binary>` | 4 unsafe-path cases refused, no fixture files written |
| `zsh Scripts/native-snapshots.sh <binary>` | 22 PNGs and layout checks PASS |
| `node Scripts/security-check.mjs` | 54 checks |
| `node Scripts/bundled-check.mjs` | 20 packaged CLI checks |
| `node Scripts/mcp-check.mjs` | 15 checks |
| `node Scripts/acceptance-check.mjs` | 37 runtime/overlay checks |

## Window and focus evidence

`Scripts/window-sampler.swift` sampled CGWindowListCopyWindowInfo and NSWorkspace.frontmostApplication every 0.2 seconds. It records on-screen windows with alpha > 0 for the supplied executable path prefixes and XCTest. A missing window list fails rather than passing silently. Its arguments are stop-file, JSON report, and one or more executable path prefixes; create the stop-file to finish.

Final check reports: 629 samples across 22 separately monitored runs; **0 visible test/app windows**. The complete app-startup-to-shutdown interval also recorded **0 visible windows**. Normal main-window startup, `--background`, the legacy `--screen` flag, hosted-test environment startup, the guard test, the standalone model executable and the full native snapshot check each had **0 changes to the frontmost app** in their final validation intervals.

Longer intervals also recorded changes between unrelated applications while the Mac was in use. These are retained as a limitation: the frontmost application was not globally constant throughout every long check. No Scorebug or test process became frontmost. The sampler does not filter unrelated focus changes out of its report or success status. A command passing its functional assertions is separate from a completely unchanged global-focus interval.

## Review and cleanup

Independent read-only review used Claude Opus 5.5 (`claude-opus-5-5`). The early-window guard and installer behaviour were corrected after review; the production documentation correction was then verified. Remaining findings: 0.

Generated plugin output, dependencies, disposable homes/data, binaries, packaged copies, snapshot output and build scratch are removed after validation. The source guard and sampler stay in the repository. No visible Simulator, computer-use interaction or `open` app launch was used. Live OBS/Stream Deck hardware and notarisation are outside this tooling change and were not run. Reverting this guard commit requires no data recovery.
