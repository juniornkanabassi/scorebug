// added-time action: title shows the live "+N". Settings: slot, and either minutes (sets an exact value,
// 0 clears it) or delta (nudges by that many minutes, default +1) when minutes is absent.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.added-time" })
export class AddedTime extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const slot = slotOf(settings);
		if (typeof settings.minutes === "number") {
			await server.send(slot, "setAddedMinutes", { minutes: settings.minutes });
		} else {
			const delta = typeof settings.delta === "number" ? settings.delta : 1;
			await server.send(slot, "adjustAddedMinutes", { delta });
		}
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		const value = typeof settings.minutes === "number" ? settings.minutes : (typeof settings.delta === "number" ? settings.delta : 1);
		const variant = value === 0 ? "off" : value < 0 ? "minus" : "plus";
		await a.setImage(iconPath("added-time", variant, slot));
		await a.setTitle(match ? undefined : "OFFLINE");
	}
}
