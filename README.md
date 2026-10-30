# Scorebug

Scorebug is a football score bug for OBS. It runs on your Mac and serves a broadcast-style overlay with the teams, the score, the clock and added time to an OBS browser source. You control it from its window, from a Stream Deck, from the command line or through an AI assistant.

I built it for my live match reactions, so the score, the clock and the added time are one press on the Stream Deck.

[Releases](https://github.com/juniornkanabassi/scorebug/releases) · [App page](https://juniornkanabassi.com/apps/scorebug/)

There is no public download yet. The first one will be signed with my Developer ID, notarised by Apple and posted on this repository's Releases page. Until then you can build it from source (see below).

## What it does

Scorebug keeps two match slots, so you can set up the next game while the current one is on air. For each match it handles the score and scorers, the clock and periods, added time, a first-leg aggregate and a penalty shootout. Each slot has a horizontal overlay for a normal stream and a vertical one for Shorts, TikTok and other portrait streams.

You can load a fixture by date and competition instead of typing the teams in. With live data switched on, Scorebug follows the real match and adds goals as they go in, and you can still correct anything by hand. Fixtures come from football-data.org when you add a free API key in Settings, and from ESPN's public scores otherwise. You can also turn on a FotMob goal check in Settings.

The overlay comes with a set of themes in the style of different competitions' broadcast graphics, and a plain one called Stealth. Club colours, short names and crests are kept in a library you can edit.

Scorebug is an independent fan project. It is not affiliated with or endorsed by any league, competition, club or broadcaster, and their names are used only to describe which match is on screen.

## What you need

- A Mac with Apple silicon. Intel Macs are not supported.
- macOS 15 or later. I test it on macOS 26.
- OBS Studio, with a browser source for each overlay.
- A Stream Deck if you want physical buttons. It is optional.
- Node.js 24 or later, but only for the `scorebug` command and the MCP server.

## Getting started

1. Open Scorebug before OBS. It serves the overlays on `http://127.0.0.1:8600/`.
2. In OBS, add a browser source pointing at `http://127.0.0.1:8600/overlay/h/1` at 1920×1080 for the horizontal overlay of slot 1, or `/overlay/v/1` at 1080×1920 for the vertical one. Slot 2 uses `/2` in place of `/1`. The page at `http://127.0.0.1:8600/` lists every source.
3. Set up the match in the Scorebug window, or load a fixture, then show the overlay.

If OBS opened a browser source while Scorebug was not running, it shows an error page that cannot recover by itself. Press Refresh on that source once Scorebug is up.

## Stream Deck

The plugin lives in `StreamDeckPlugin/` and talks to Scorebug on the same local port. To build it and add it to the Stream Deck app:

```sh
cd StreamDeckPlugin
npm install
npm run build
npx streamdeck link com.juniornkanabassi.scorebug.sdPlugin
```

## Privacy

Scorebug's server listens only on 127.0.0.1, so nothing on your network can reach it, and it checks each request's Host and Origin so web pages cannot drive it. It contacts football-data.org and ESPN to load fixtures, live scores and crests, and FotMob too if you turn on its goal check. It also checks juniornkanabassi.com for updates. Your football-data.org key is stored in the macOS keychain. Your clubs, settings and match state are kept in `~/Library/Application Support/Scorebug/`.

## Command line and AI assistants

The `scorebug` command and its MCP server cover every match control the window and the Stream Deck have, from the score and the clock to added time, the shootout, the first leg and live-data linking. Editing the club library and the app's settings stays in the window. Changes show in the running app and on the overlay straight away.

```sh
SCOREBUG="/Applications/Scorebug.app/Contents/Resources/Scripts/scorebug.mjs"
node "$SCOREBUG" --help
node "$SCOREBUG" match set --home "Real Madrid" --away Inter --competition ucl --first-leg 2-1
node "$SCOREBUG" show --slot 1
node "$SCOREBUG" goal add --side home --minute 23 --scorer "Vinícius"
node "$SCOREBUG" clock start --period firstHalf
```

To connect the MCP server to Claude Code, using the full path to Node (`command -v node` prints it):

```sh
claude mcp add scorebug -- /absolute/path/to/node "/Applications/Scorebug.app/Contents/Resources/mcp/scorebug-mcp.mjs"
```

For Codex, add this to `~/.codex/config.toml`:

```toml
[mcp_servers.scorebug]
command = "/absolute/path/to/node"
args = ["/Applications/Scorebug.app/Contents/Resources/mcp/scorebug-mcp.mjs"]
```

Every command, its options and the error codes are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#ai-control).

## Building from source

You need an Apple silicon Mac with Xcode or the Swift 6 command-line tools. The Swift dependencies are FlyingFox and Sparkle, which SwiftPM fetches.

```sh
swift build --scratch-path /private/tmp/scorebug-build
swift run --scratch-path /private/tmp/scorebug-build CoreChecks
zsh build.sh
```

`CoreChecks` is the test suite. `build.sh` writes the app in a zip to `../Outputs`, outside the clone, and `install.sh` builds and installs it on your own Mac. To try it without touching your real data, run the built app with `--data-directory` pointing at an empty temporary folder and `--port` set to something other than 8600. The launch flags, the local API and the check scripts are covered in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Licence

Copyright (C) 2026 Junior Nkanabassi. Licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later); see [LICENSE](LICENSE). The Scorebug name and icon are not covered by the licence.

In plain terms, you can use, change and share this code, but anything you distribute that is built on it has to stay open source under the same licence.

The overlay fonts (Archivo, Barlow, Inter, Montserrat and Oswald) are under the SIL Open Font License, FlyingFox, the web server inside the app, is under the MIT licence, and Sparkle, which installs updates, is under the MIT licence too.
