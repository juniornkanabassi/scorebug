// play-pause action: settings.mode picks a one-way play, a one-way pause, or a toggle that follows the clock. Settings: slot, mode.
// "play"/"pause" is a one-way key that always sends that command and shows a fixed icon.
// Settings: slot, mode (play | pause | toggle, default toggle).
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

function modeOf(settings: BaseSettings): "play" | "pause" | "toggle" {
	return settings.mode === "play" || settings.mode === "pause" ? settings.mode : "toggle";
}

@action({ UUID: "com.juniornkanabassi.scorebug.play-pause" })
export class PlayPause extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const mode = modeOf(settings);
		await server.send(slotOf(settings), mode === "toggle" ? "playPause" : mode, {}, () => ev.action.showAlert());
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		const mode = modeOf(settings);
		const variant = mode === "toggle" ? (match?.clock.running ? "pause" : "play") : mode;
		await a.setImage(iconPath("play-pause", variant, slot));
		await a.setTitle(match ? undefined : server.offlineTitle);
	}
}
