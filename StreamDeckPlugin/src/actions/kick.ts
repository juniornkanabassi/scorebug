// kick action: title shows that side's shootout tally while a shootout is on. Settings: slot, side, result.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, sideOf, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.kick" })
export class Kick extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const result = settings.result === "missed" ? "missed" : "scored";
		await server.send(slotOf(settings), "recordKick", { side: sideOf(settings), result });
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		const side = sideOf(settings);
		const result = settings.result === "missed" ? "missed" : "scored";
		await a.setImage(iconPath("kick", `${side}-${result}`, slot));
		if (!match) {
			await a.setTitle("OFFLINE");
			return;
		}
		const scored = match.shootout?.kicks.filter((k) => k.side === side && k.result === "scored").length ?? 0;
		await a.setTitle(match.phase === "shootout" ? `${scored}` : undefined);
	}
}
