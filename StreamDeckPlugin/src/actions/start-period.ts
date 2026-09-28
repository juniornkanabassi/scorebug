// start-period action: press starts the configured period; the key art names it. Settings: slot, period.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.start-period" })
export class StartPeriod extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const period = typeof settings.period === "string" ? settings.period : "firstHalf";
		await server.send(slotOf(settings), "startPeriod", { period }, () => ev.action.showAlert());
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		const period = typeof settings.period === "string" ? settings.period : "firstHalf";
		const known = period === "secondHalf" || period === "extraFirst" || period === "extraSecond" ? period : "firstHalf";
		await a.setImage(iconPath("start-period", known, slot));
		await a.setTitle(match ? undefined : server.offlineTitle);
	}
}
