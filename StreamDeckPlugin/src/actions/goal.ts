// goal action: short press applies settings.delta (+1 by default), long press applies the opposite, so a
// page can carry a dedicated minus key beside a plus key. Settings: slot, side, delta.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyUpEvent, KeyAction, WillDisappearEvent } from "@elgato/streamdeck";
import { LONG_PRESS_MS, StatefulAction, iconPath, server, sideOf, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

@action({ UUID: "com.juniornkanabassi.scorebug.goal" })
export class Goal extends StatefulAction {
	#pressedAt = new Map<string, number>();
	override onWillDisappear(ev: WillDisappearEvent<BaseSettings>): void { this.#pressedAt.delete(ev.action.id); super.onWillDisappear(ev); }

	override onKeyDown(ev: KeyDownEvent<BaseSettings>): void {
		this.#pressedAt.set(ev.action.id, Date.now());
	}

	override async onKeyUp(ev: KeyUpEvent<BaseSettings>): Promise<void> {
		const start = this.#pressedAt.get(ev.action.id) ?? Date.now();
		this.#pressedAt.delete(ev.action.id);
		const longPress = Date.now() - start >= LONG_PRESS_MS;
		const settings = ev.payload.settings;
		const side = sideOf(settings);
		const delta = settings.delta === -1 ? -1 : 1;
		await server.send(slotOf(settings), "goal", { side, delta: longPress ? -delta : delta });
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const side = sideOf(settings);
		const match = server.match(slot);
		await a.setImage(iconPath("goal", `${side}-${settings.delta === -1 ? "minus" : "plus"}`, slot));
		await a.setTitle(match ? `${match[side === "home" ? "homeScore" : "awayScore"]}` : "OFFLINE");
	}
}
