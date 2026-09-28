// reset-match action: only a 1 second hold resets, to avoid accidents. Settings: slot.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyUpEvent, KeyAction, WillDisappearEvent } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

const HOLD_MS = 1000;

@action({ UUID: "com.juniornkanabassi.scorebug.reset-match" })
export class ResetMatch extends StatefulAction {
	#pressedAt = new Map<string, number>();
	override onWillDisappear(ev: WillDisappearEvent<BaseSettings>): void { this.#pressedAt.delete(ev.action.id); super.onWillDisappear(ev); }

	override onKeyDown(ev: KeyDownEvent<BaseSettings>): void {
		this.#pressedAt.set(ev.action.id, Date.now());
	}

	override async onKeyUp(ev: KeyUpEvent<BaseSettings>): Promise<void> {
		const start = this.#pressedAt.get(ev.action.id) ?? Date.now();
		this.#pressedAt.delete(ev.action.id);
		if (Date.now() - start >= HOLD_MS) {
			await server.send(slotOf(ev.payload.settings), "reset", {}, () => ev.action.showAlert());
		} else {
			await ev.action.showAlert();
		}
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		await a.setImage(iconPath("reset-match", "key", slot));
		await a.setTitle(server.match(slot) ? undefined : server.offlineTitle);
	}
}
