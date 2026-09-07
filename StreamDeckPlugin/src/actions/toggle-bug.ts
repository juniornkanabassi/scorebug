// toggle-bug action: icon follows visible. Settings: slot.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.toggle-bug" })
export class ToggleBug extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		await server.send(slotOf(ev.payload.settings), "toggleVisible");
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		await a.setImage(iconPath("toggle-bug", match?.visible ? "on" : "off", slot));
		await a.setTitle(match ? undefined : "OFFLINE");
	}
}
