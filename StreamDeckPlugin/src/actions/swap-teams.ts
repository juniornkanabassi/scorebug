// swap-teams action. Settings: slot.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.swap-teams" })
export class SwapTeams extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		await server.send(slotOf(ev.payload.settings), "swapTeams");
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		await a.setImage(iconPath("swap-teams", "key", slot));
		await a.setTitle(server.match(slot) ? undefined : "OFFLINE");
	}
}
