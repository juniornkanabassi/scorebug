// One WebSocket to the Scorebug server, shared by every action. See ARCHITECTURE.md "Stream Deck plugin"
// and CommandRequest in Sources/ScorebugCore/MatchEngine.swift for the command JSON.
import streamDeck, { SingletonAction } from "@elgato/streamdeck";
import type { DidReceiveSettingsEvent, KeyAction, WillAppearEvent, WillDisappearEvent } from "@elgato/streamdeck";
import type { JsonValue } from "@elgato/utils";
// Node 20 (what the manifest pins the plugin to) has no global WebSocket; `ws` is already a dependency
// of @elgato/streamdeck, so this just imports it directly instead of relying on a global that isn't there.
import WebSocket, { type MessageEvent } from "ws";
import { launchAndWait } from "./launch.js";

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
interface Snapshot {
	serverTime: number;
	matches: MatchState[];
}

const HOST = "127.0.0.1";
const PORT = 8600;

type StateListener = (online: boolean, starting: boolean) => void;

class ServerClient {
	#snapshot: Snapshot | null = null;
	#listeners = new Set<StateListener>();
	#backoff = 1000;
	#reconnectTimer: ReturnType<typeof setTimeout> | null = null;
	#starting = 0;

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

	#reconnectNow(): void {
		// Only while waiting out a backoff; with no timer a socket is already connecting.
		if (!this.#reconnectTimer) return;
		clearTimeout(this.#reconnectTimer);
		this.#reconnectTimer = null;
		this.#backoff = 1000;
		this.#connect();
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
		for (const listener of this.#listeners) listener(online, this.#starting > 0);
	}

	/** Fires on every online/offline transition, startup transition and state broadcast; fires once immediately. */
	onState(listener: StateListener): () => void {
		this.#listeners.add(listener);
		listener(this.#snapshot !== null, this.#starting > 0);
		return () => {
			this.#listeners.delete(listener);
		};
	}

	match(slot: number): MatchState | undefined {
		return this.#snapshot?.matches.find((m) => m.slot === slot);
	}

	get online(): boolean {
		return this.#snapshot !== null;
	}

	get offlineTitle(): string {
		return this.#starting > 0 ? "OFFLINE\nSTARTING" : "OFFLINE";
	}

	async send(slot: number, command: string, body: Record<string, unknown> = {}, onUnavailable?: () => Promise<unknown>): Promise<void> {
		// "refused" means the request never reached a server (the app isn't running), so it is safe to launch and
		// resend. Any other failure (timeout, reset) may have been applied already: never resend it, or a goal
		// could count twice on air (review of 28 Sep).
		// "rejected" and "unsaved" reached the app, so they alert but never resend (Codex review, 1 Oct).
		const sendCommand = async (): Promise<"sent" | "rejected" | "unsaved" | "refused" | "unknown"> => {
			try {
				const res = await fetch(`http://${HOST}:${PORT}/api/match/${slot}/command`, {
					method: "POST",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ command, ...body }),
					signal: AbortSignal.timeout(3000)
				});
				if (!res.ok) {
					streamDeck.logger.warn(`scorebug: ${command} rejected (${res.status})`);
					return "rejected";
				}
				if (res.headers.get("X-Scorebug-Save-Failed")) {
					streamDeck.logger.warn(`scorebug: ${command} applied but not saved`);
					return "unsaved";
				}
				return "sent";
			} catch (err) {
				const code = (err as { cause?: { code?: string } })?.cause?.code;
				streamDeck.logger.warn(`scorebug: ${command} failed (${code ?? "unknown"})`, err);
				return code === "ECONNREFUSED" ? "refused" : "unknown";
			}
		};

		// Always try first: the app may be up while the socket is still waiting out its backoff.
		let result = await sendCommand();
		if (result === "refused") {
			this.#starting++;
			this.#notify();
			try {
				if (await launchAndWait(PORT)) result = await sendCommand();
			} finally {
				this.#starting--;
				this.#notify();
			}
		}
		// A command got through, so the app is up: reconnect now rather than after the backoff, or the key keeps
		// showing OFFLINE and invites a second press (review of 28 Sep).
		const reachedApp = result !== "refused" && result !== "unknown";
		if (reachedApp && !this.online) this.#reconnectNow();
		if (result !== "sent") await onUnavailable?.();
	}
}

/** The plugin's one connection to the server; every action imports this same instance. */
export const server = new ServerClient();

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
