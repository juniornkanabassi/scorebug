// toggle-scorers action: icon follows showScorers. Settings: slot.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.toggle-scorers" })
export class ToggleScorers extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		await server.send(slotOf(ev.payload.settings), "toggleScorers");
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		await a.setImage(iconPath("toggle-scorers", match?.showScorers ? "on" : "off", slot));
		await a.setTitle(match ? undefined : "OFFLINE");
	}
}
