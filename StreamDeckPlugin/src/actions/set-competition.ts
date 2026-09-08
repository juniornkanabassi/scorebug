// set-competition action: the art bakes in the competition's short code and colour. Settings: slot, competitionId.
import { action } from "@elgato/streamdeck";
import type { KeyDownEvent, KeyAction } from "@elgato/streamdeck";
import { StatefulAction, iconPath, server, slotOf } from "../lib/scorebug.js";
import type { BaseSettings } from "../lib/scorebug.js";

/** The eight competitions with baked-in key art (see Outputs/Stream Deck/icons-src/render_icons.py); any other id falls back to "default". */
const ART_COMPETITIONS = new Set([
	"ligue1", "premier-league", "champions-league", "europa-league", "conference-league", "la-liga", "serie-a", "bundesliga"
]);

@action({ UUID: "com.juniornkanabassi.scorebug.set-competition" })
export class SetCompetition extends StatefulAction {
	override async onKeyDown(ev: KeyDownEvent<BaseSettings>): Promise<void> {
		const settings = ev.payload.settings;
		const competitionId = typeof settings.competitionId === "string" ? settings.competitionId : undefined;
		if (!competitionId) return;
		await server.send(slotOf(settings), "setCompetition", { competitionId });
	}

	protected override async paint(a: KeyAction<BaseSettings>, settings: BaseSettings): Promise<void> {
		const slot = slotOf(settings);
		const match = server.match(slot);
		const competitionId = typeof settings.competitionId === "string" ? settings.competitionId : undefined;
		const variant = competitionId && ART_COMPETITIONS.has(competitionId) ? competitionId : "default";
		await a.setImage(iconPath("set-competition", variant, slot));
		if (!match) {
			await a.setTitle("OFFLINE");
			return;
		}
		// The art already carries the code and full name; only the "default" tile needs a text fallback.
		if (variant !== "default") {
			await a.setTitle(undefined);
			return;
		}
		const known = server.competitions().find((c) => c.id === competitionId);
		await a.setTitle(undefined);
	}
}
