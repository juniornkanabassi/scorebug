// clock-reset action: resets the match clock to 0:00. Settings: slot.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.clock-reset" })
export class ClockReset extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		await server.send(slotOf(ev.payload.settings), "setClock", { seconds: 0 }, () => ev.action.showAlert());
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		await a.setImage(iconPath("clock-reset", "key", slot));
		await a.setTitle(server.match(slot) ? undefined : server.offlineTitle);
	}
}
