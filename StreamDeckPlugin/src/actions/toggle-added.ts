// toggle-added action: press hides the announced added time, storing it as "remembered"; press again
// restores the remembered value (default 1). Settings: slot, remembered.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.toggle-added" })
export class ToggleAdded extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const slot = slotOf(settings);
		const current = server.match(slot)?.addedMinutes ?? 0;
		if (current !== 0) {
			await ev.action.setSettings({ ...settings, remembered: current });
			await server.send(slot, "setAddedMinutes", { minutes: null }, () => ev.action.showAlert());
		} else {
			const remembered = typeof settings.remembered === "number" ? settings.remembered : 1;
			await server.send(slot, "setAddedMinutes", { minutes: remembered }, () => ev.action.showAlert());
		}
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		await a.setImage(iconPath("toggle-added", match?.addedMinutes ? "on" : "off", slot));
		await a.setTitle(match ? undefined : server.offlineTitle);
	}
}
