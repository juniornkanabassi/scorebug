// One WebSocket to the Scorebug server, shared by every action. See ARCHITECTURE.md "Stream Deck plugin"
// and CommandRequest in Sources/ScorebugCore/MatchEngine.swift for the command JSON.
import streamDeck, { SingletonAction } from "@elgato/streamdeck";
import type { DidReceiveSettingsEvent, KeyAction, WillAppearEvent, WillDisappearEvent } from "@elgato/streamdeck";
import type { JsonValue } from "@elgato/utils";
// Node 20 (what the manifest pins the plugin to) has no global WebSocket; `ws` is already a dependency
// of @elgato/streamdeck, so this just imports it directly instead of relying on a global that isn't there.
import WebSocket, { type MessageEvent } from "ws";

export type Side = "home" | "away";

interface TeamEntry {
	code: string;
	name: string;
	shortName: string;
}
interface ClockState {
	periodBaseSeconds: number;
	periodStart: number | null;
	accumulated: number;
	running: boolean;
}
interface Kick {
	side: Side;
	result: "pending" | "scored" | "missed";
}
interface ShootoutState {
	kicks: Kick[];
	firstKicker: Side;
}
export interface MatchState {
	slot: number;
	competitionId: string;
	home: TeamEntry;
	away: TeamEntry;
	phase: string;
	clock: ClockState;
	addedMinutes: number | null;
	homeScore: number;
	awayScore: number;
	visible: boolean;
	showScorers: boolean;
	shootout?: ShootoutState;
}
export interface CompetitionInfo {
	id: string;
	name: string;
	shortName: string;
}
interface Snapshot {
	serverTime: number;
	matches: MatchState[];
	competitions: CompetitionInfo[];
}

const HOST = "127.0.0.1";
const PORT = 8600;

type StateListener = (online: boolean) => void;

class ServerClient {
	#snapshot: Snapshot | null = null;
	#listeners = new Set<StateListener>();
	#backoff = 1000;
	#reconnectTimer: ReturnType<typeof setTimeout> | null = null;

	constructor() {
		this.#connect();
	}

	#connect(): void {
		let ws: WebSocket;
		try {
			ws = new WebSocket(`ws://${HOST}:${PORT}/ws`);
		} catch {
			this.#scheduleReconnect();
			return;
		}
		ws.addEventListener("open", () => {
			this.#backoff = 1000;
		});
		ws.addEventListener("message", (ev: MessageEvent) => {
			try {
				this.#snapshot = JSON.parse(String(ev.data));
				this.#notify();
			} catch (err) {
				streamDeck.logger.warn("scorebug: bad state payload", err);
			}
		});
		ws.addEventListener("close", () => this.#scheduleReconnect());
		ws.addEventListener("error", () => {
			try {
				ws.close();
			} catch {
				// already closing
			}
		});
	}

	#scheduleReconnect(): void {
		const wasOnline = this.#snapshot !== null;
		this.#snapshot = null;
		if (wasOnline) this.#notify();
		if (this.#reconnectTimer) return;
		this.#reconnectTimer = setTimeout(() => {
			this.#reconnectTimer = null;
			this.#backoff = Math.min(this.#backoff * 2, 30_000);
			this.#connect();
		}, this.#backoff);
	}

	#notify(): void {
		const online = this.#snapshot !== null;
		for (const listener of this.#listeners) listener(online);
	}

	/** Fires on every online/offline transition and every state broadcast; fires once immediately. */
	onState(listener: StateListener): () => void {
		this.#listeners.add(listener);
		listener(this.#snapshot !== null);
		return () => {
			this.#listeners.delete(listener);
		};
	}

	match(slot: number): MatchState | undefined {
		return this.#snapshot?.matches.find((m) => m.slot === slot);
	}

	competitions(): CompetitionInfo[] {
		return this.#snapshot?.competitions ?? [];
	}

	get online(): boolean {
		return this.#snapshot !== null;
	}

	async send(slot: number, command: string, body: Record<string, unknown> = {}): Promise<void> {
		try {
			const res = await fetch(`http://${HOST}:${PORT}/api/match/${slot}/command`, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify({ command, ...body })
			});
			if (!res.ok) streamDeck.logger.warn(`scorebug: ${command} rejected (${res.status})`);
		} catch (err) {
			streamDeck.logger.warn(`scorebug: ${command} failed, server unreachable`, err);
		}
	}
}

/** The plugin's one connection to the server; every action imports this same instance. */
export const server = new ServerClient();

/** Mirrors `Clock.elapsed(at:)` in ClockEngine.swift. `now` and `clock.periodStart` are ms since 1970. */
export function elapsedSeconds(clock: ClockState, now: number): number {
	let total = clock.periodBaseSeconds + clock.accumulated;
	if (clock.running && clock.periodStart !== null) total += Math.max(0, (now - clock.periodStart) / 1000);
	return total;
}

export function formatClock(totalSeconds: number): string {
	const s = Math.max(0, Math.floor(totalSeconds));
	return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, "0")}`;
}

/** Mirrors `Phase.stateLabel` in Models.swift, plus a short label for every live period. */
export const PHASE_LABEL: Record<string, string> = {
	preMatch: "KO",
	firstHalf: "1H",
	halfTime: "HT",
	secondHalf: "2H",
	fullTime: "FT",
	extraFirst: "ET1",
	extraBreak: "HT",
	extraSecond: "ET2",
	extraFullTime: "AET",
	shootout: "PENS",
	finished: "FT"
};

export interface BaseSettings {
	slot?: number;
	side?: string;
	[key: string]: JsonValue | undefined;
}

export function slotOf(settings: BaseSettings): number {
	return settings.slot === 2 ? 2 : 1;
}

export function sideOf(settings: BaseSettings, key = "side"): Side {
	return settings[key] === "away" ? "away" : "home";
}

/**
 * Path (no extension) to a key icon variant, for `KeyAction.setImage`. Every action's icons live at
 * `imgs/actions/<action>/<variant>-<slot>`; a boolean action passes the "on"/"off" variant name, a plain
 * one just `"key"`. Stream Deck resolves the matching `@2x` file itself, the same way it resolves `Icon`.
 */
export function iconPath(action: string, variant: string, slot: number): string {
	return `imgs/actions/${action}/${variant}-${slot}`;
}

/** A press held at least this long counts as a long press. */
export const LONG_PRESS_MS = 700;

/**
 * Base for every key action: caches each instance's settings, repaints on every server broadcast
 * (state change or connect/disconnect), and repaints a single key when it appears or its settings change.
 * Subclasses implement `paint` and whatever key-press handling they need.
 */
export abstract class StatefulAction<S extends BaseSettings = BaseSettings> extends SingletonAction<S> {
	#settings = new Map<string, S>();

	constructor() {
		super();
		server.onState(() => this.repaintAll());
	}

	override onWillAppear(ev: WillAppearEvent<S>): Promise<void> | void {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) return this.paint(ev.action, ev.payload.settings);
	}

	override onDidReceiveSettings(ev: DidReceiveSettingsEvent<S>): Promise<void> | void {
		this.#settings.set(ev.action.id, ev.payload.settings);
		if (ev.action.isKey()) return this.paint(ev.action, ev.payload.settings);
	}

	override onWillDisappear(ev: WillDisappearEvent<S>): void {
		this.#settings.delete(ev.action.id);
	}

	protected repaintAll(): void {
		for (const a of this.actions) {
			if (!a.isKey()) continue;
			const settings = this.#settings.get(a.id);
			if (settings) void this.paint(a, settings);
		}
	}

	protected abstract paint(action: KeyAction<S>, settings: S): Promise<void> | void;
}
