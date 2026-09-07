// play-pause action: mode "toggle" (default) plays/pauses and its icon follows clock.running; mode
// "play"/"pause" is a one-way key that always sends that command and shows a fixed icon.
// Settings: slot, mode (play | pause | toggle, default toggle).
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, elapsedSeconds, formatClock, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

function modeOf(settings: BaseSettings): "play" | "pause" | "toggle" {
	return settings.mode === "play" || settings.mode === "pause" ? settings.mode : "toggle";
}

@action({ UUID: "com.juniornkanabassi.scorebug.play-pause" })
export class PlayPause extends StatefulAction {
	constructor() {
		super();
		// The server never streams ticks (ARCHITECTURE-ESSENTIALS rule 3); the clock display is derived locally.
		// Only repaint while a clock is actually running, so an idle key isn't repainted once a second forever.
		setInterval(() => {
			if (server.match(1)?.clock.running || server.match(2)?.clock.running) this.repaintAll();
		}, 1000);
	}

	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const mode = modeOf(settings);
		await server.send(slotOf(settings), mode === "toggle" ? "playPause" : mode);
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		const mode = modeOf(settings);
		const variant = mode === "toggle" ? (match?.clock.running ? "pause" : "play") : mode;
		await a.setImage(iconPath("play-pause", variant, slot));
		await a.setTitle(match ? formatClock(elapsedSeconds(match.clock, Date.now())) : "OFFLINE");
	}
}
