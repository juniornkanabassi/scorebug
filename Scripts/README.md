# Scripts

Node ESM harness for the overlay pages: `capture.mjs` screenshots a bug (steady, a demo freeze, or a series
tiled into one sheet); `latency.mjs` measures command and paint latency. Both talk to a running Scorebug
instance over HTTP; neither builds or launches the app.

## Prerequisites

- Node 22 or later (uses the built-in `WebSocket`, `fetch` and `node:util` `parseArgs`).
- A browser backend, found automatically in this order:
  1. Playwright, if it resolves as a module (a local install, or the copy bundled inside the globally
     installed `@playwright/cli`). No downloaded Chromium is required: the launch uses
     `channel: "chrome"`, driving the Mac's own Google Chrome.
  2. Otherwise, `/Applications/Google Chrome.app` headless over the Chrome DevTools Protocol, using
     Node's built-in `WebSocket`. No extra dependency either way.
- `ffmpeg` on `PATH`, only for `--series --sheet` (tiles the frames with `hstack`).

Both scripts print which backend they used (`backend: playwright` or `backend: cdp`).

## Start a disposable instance first

Never point either script at the real data folder. Build and run a throwaway instance:

```sh
cd Source
swift build -c release --scratch-path /private/tmp/scorebug-build
/private/tmp/scorebug-build/release/Scorebug --data-directory <scratchpad>/data --port 8620 --screen "Agent Screen"
```

`--screen "Agent Screen"` may open a window on that virtual display if it exists; that is expected. Set
up a match before capturing:

```sh
curl -s -X POST http://127.0.0.1:8620/api/match/1/command -H 'content-type: application/json' \
  -d '{"command":"setCompetition","competitionId":"premier-league"}'
```

## capture.mjs

```
node capture.mjs --port 8620 --slot 1 --orientation h [--demo goal:home:600] --out x.png [--full]
node capture.mjs --port 8620 --demo show --series 0,300,600,900 --sheet sheet.png
```

- `--port` (required), `--slot` (`1` or `2`, default `1`), `--orientation` (`h` or `v`, default `h`).
- `--demo` matches the overlay's `?demo=` query hook, for example `goal:home:600` or `show:300`.
- `--out` the PNG path for a single capture.
- `--series a,b,c` with `--demo <kind>` (the millisecond, if you left one on the end, is stripped and
  replaced per point) loads the page once per millisecond in the list, freezes there, and writes
  `<out-without-.png>-<ms>.png` for each. Add `--sheet path.png` to tile them side by side with ffmpeg.
  Series frames always capture the full canvas (not `--full`ed per frame): the bug moves during show/hide,
  so a bounding-box crop would not line up across frames in one sheet.
- `--full` captures the whole 1920x1080 (or 1080x1920 for `v`) canvas instead of the default: the bug's
  `getBoundingClientRect()` expanded by 8px on every side.
- Every screenshot is at device scale factor 2 with a transparent background.

A fresh page always plays the 820 ms build-in, so a steady capture needs `--demo show:900` (or later); a bare capture lands mid-wipe.

Waits for the overlay's first WebSocket state (`#bug`'s `data-phase` set) and `document.fonts.ready`
before doing anything else. When `--demo` is given, also waits 1.3s past load: the `?demo=` hook fires
900ms after load and then pauses `document.getAnimations()` at the requested millisecond, so 1.3s clears
that with a small margin.

Prints the output path(s) to stdout.

## latency.mjs

```
node latency.mjs --port 8620 --samples 100
```

Prints a table:

| metric | what it measures |
|---|---|
| `POST /command` | round trip for `{"command":"setAddedMinutes","minutes":null}` on match 1, `--samples` times |
| `WS message to paint` | inside a real `/overlay/h/1` page, `WebSocket.prototype.onmessage` is wrapped to time message receipt to the next `requestAnimationFrame`; 30 `goal` commands (alternating `delta` 1 and -1, so the score and goal list return to where they started) are sent over HTTP to trigger it |
| `GET /api/state` | round trip, `--samples` times |

Each row reports n, p50 and p95 in milliseconds.

## Example run (6 September 2026, disposable instance on port 8620)

```
backend: playwright
metric                      n     p50 ms    p95 ms
POST /command               100   60.03     66.34
WS message to paint          30    6.90     13.60
GET /api/state              100    1.85      2.18
```

Command round trip is well above the plain state read, on an otherwise idle disposable instance with a
placeholder match; worth a look for whoever owns `OverlayServer.swift` and `AppModel.swift` this round
(not this agent, see the request below).

## Caveat

Both scripts assume the instance is already running (see above). Neither one starts, builds, stops, or
otherwise manages the Scorebug process.

## Request for agent CH (overlay.js)

`capture.mjs` freezes the build-out the same way it freezes `show` and `goal`, but `overlay.js` only has
`?demo=show:<ms>`, not a matching `hide`. Please add this beside the existing `show` branch in the `demo`
block:

```js
} else if (kind === "hide") {
  at = p1;
  if (buildTimer) { clearTimeout(buildTimer); buildTimer = null; }
  bug.classList.remove("hidden", "building-in");
  void bug.offsetWidth;
  bug.classList.add("building-out");
  visibleState = false;
```

Same reasoning as the existing `show` comment: no follow-up timer to swap in `.hidden`, since under a
headless capture with the animation paused mid-flight, a queued class swap could fire in the same tick and
wipe the frozen frame before `capture.mjs` reads it.
