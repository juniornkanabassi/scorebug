// start-shootout action. Settings: slot, side (the first kicker; defaults to home).
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, sideOf, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.start-shootout" })
export class StartShootout extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		await server.send(slotOf(settings), "startShootout", { side: sideOf(settings) });
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		await a.setImage(iconPath("start-shootout", sideOf(settings), slot));
		await a.setTitle(match ? undefined : "OFFLINE");
	}
}
