// goal action: short press scores, long press undoes the last goal for that side. Settings: slot, side.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyUpEvent, KeyAction } from "@elgato/streamdeck";
import { LONG_PRESS_MS, StatefulAction, iconPath, server, sideOf, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.goal" })
export class Goal extends StatefulAction {
	#pressedAt = new Map<string, number>();

	override onKeyDown(ev: KeyDownEvent<BaseSettings>): void {
		this.#pressedAt.set(ev.action.id, Date.now());
	}

	override async onKeyUp(ev: KeyUpEvent<BaseSettings>): Promise<void> {
		const start = this.#pressedAt.get(ev.action.id) ?? Date.now();
		this.#pressedAt.delete(ev.action.id);
		const longPress = Date.now() - start >= LONG_PRESS_MS;
		const settings = ev.payload.settings;
		const side = sideOf(settings);
		await server.send(slotOf(settings), "goal", longPress ? { side, delta: -1 } : { side });
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const side = sideOf(settings);
		const match = server.match(slot);
		await a.setImage(iconPath("goal", side, slot));
		await a.setTitle(match ? `${match[side === "home" ? "homeScore" : "awayScore"]}` : "OFFLINE");
	}
}
