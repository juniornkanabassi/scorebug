// play-pause action: icon follows clock.running, title is the live clock. Settings: slot.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, elapsedSeconds, formatClock, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

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
		await server.send(slotOf(ev.payload.settings), "playPause");
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		if (!match) {
			await a.setImage(iconPath("play-pause", "play", slot));
			await a.setTitle("OFFLINE");
			return;
		}
		await a.setImage(iconPath("play-pause", match.clock.running ? "pause" : "play", slot));
		await a.setTitle(formatClock(elapsedSeconds(match.clock, Date.now())));
	}
}
