#!/usr/bin/env node
// Sets a slot up for a match from plain team names, so a stream can be prepared from a chat message
// instead of the window. Talks to a running Scorebug over its HTTP API; builds nothing, installs nothing.
//
//   node setup-match.mjs --home "Real Madrid" --away Inter --competition ucl
//   node setup-match.mjs --home Arsenal --away Chelsea --competition premier-league --slot 2 --show
//   node setup-match.mjs --home "Real Madrid" --away Inter --competition ucl --first-leg 2-1
//   node setup-match.mjs --list "real"        # what the library knows, no changes
//
// Flags: --home --away --competition --slot (1) --first-leg H-A --kickoff HH:MM --show --hide
//        --keep-score (skip the reset) --port (8600) --dry-run --list <query>
import { parseArgs } from "node:util";

const { values } = parseArgs({
	options: {
		home: { type: "string" }, away: { type: "string" }, competition: { type: "string" },
		slot: { type: "string", default: "1" }, "first-leg": { type: "string" }, kickoff: { type: "string" },
		show: { type: "boolean" }, hide: { type: "boolean" }, "keep-score": { type: "boolean" },
		port: { type: "string", default: "8600" }, "dry-run": { type: "boolean" }, list: { type: "string" },
	},
});
const BASE = `http://127.0.0.1:${values.port}`;
const slot = values.slot === "2" ? 2 : 1;

const fold = (s) => (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, "").trim();
const WORD_NOISE = new Set(["fc", "cf", "afc", "sc", "ac", "as", "ss", "us", "club", "de", "the", "1", "05", "04", "08", "09"]);
const words = (s) => fold(s).split(/\s+/).filter((w) => w && !WORD_NOISE.has(w));

/** How well a library club matches what was typed. Higher is better; 0 means no. */
function score(club, query) {
	const q = fold(query), qw = words(query);
	const names = [club.name, club.shortName, club.defaultCode, ...Object.values(club.codes ?? {})];
	for (const n of names) if (fold(n) === q) return 100;
	for (const n of [club.name, club.shortName]) {
		const f = fold(n);
		if (f.startsWith(q) || q.startsWith(f)) return 80;
		if (f.includes(q)) return 70;
	}
	const nw = new Set([...words(club.name), ...words(club.shortName)]);
	const hits = qw.filter((w) => nw.has(w)).length;
	if (hits && hits === qw.length) return 60 + hits;
	if (hits) return 30 + hits;
	return 0;
}

function pickClub(clubs, query, competitionId) {
	const ranked = clubs
		.map((c) => ({ club: c, s: score(c, query) + (competitionId && (c.competitionIds ?? []).includes(competitionId) ? 15 : 0) }))
		.filter((r) => r.s > 0)
		.sort((a, b) => b.s - a.s);
	return { best: ranked[0]?.club, alternatives: ranked.slice(1, 4).map((r) => r.club.name), top: ranked[0]?.s ?? 0 };
}

function pickCompetition(comps, query) {
	if (!query) return undefined;
	const q = fold(query);
	const alias = {
		ucl: "champions-league", cl: "champions-league", ecl: "conference-league", uel: "europa-league",
		el: "europa-league", pl: "premier-league", epl: "premier-league", laliga: "la-liga",
		ligue1: "ligue1", l1: "ligue1", seriea: "serie-a", bundesliga: "bundesliga",
	}[q.replace(/\s+/g, "")];
	return comps.find((c) => c.id === (alias ?? q)) ??
		comps.find((c) => fold(c.name) === q || fold(c.shortName) === q) ??
		comps.find((c) => fold(c.name).includes(q));
}

async function send(command, body = {}) {
	if (values["dry-run"]) { console.log(`  would send ${command} ${JSON.stringify(body)}`); return; }
	const res = await fetch(`${BASE}/api/match/${slot}/command`, {
		method: "POST", headers: { "content-type": "application/json" },
		body: JSON.stringify({ command, ...body }),
	});
	if (!res.ok) throw new Error(`${command} failed: ${res.status} ${await res.text()}`);
}

const library = await fetch(`${BASE}/api/library`).then((r) => {
	if (!r.ok) throw new Error(`Scorebug is not answering on ${BASE}. Open the app first.`);
	return r.json();
});

if (values.list !== undefined) {
	const q = values.list;
	const rows = library.clubs
		.map((c) => ({ c, s: q ? score(c, q) : 1 }))
		.filter((r) => r.s > 0).sort((a, b) => b.s - a.s).slice(0, 15);
	for (const { c } of rows) console.log(`${c.name}  (${c.shortName}, ${c.defaultCode})  ${(c.competitionIds ?? []).join(", ")}`);
	console.log(`\nCompetitions: ${library.competitions.map((c) => c.id).join(", ")}`);
	process.exit(0);
}
if (!values.home || !values.away) {
	console.error("Need --home and --away. Use --list <query> to see what the library holds.");
	process.exit(2);
}

const competition = pickCompetition(library.competitions, values.competition);
if (values.competition && !competition) throw new Error(`No competition matching "${values.competition}". Known: ${library.competitions.map((c) => c.id).join(", ")}`);
const compId = competition?.id;

const picks = {};
for (const side of ["home", "away"]) {
	const query = values[side];
	const { best, alternatives, top } = pickClub(library.clubs, query, compId);
	if (!best) throw new Error(`No club matching "${query}". Try --list "${query}".`);
	picks[side] = best;
	const note = top < 60 ? `  (weak match${alternatives.length ? `, also considered ${alternatives.join(", ")}` : ""}, check this)` : "";
	console.log(`${side.padEnd(4)} ${query} -> ${best.name}${note}`);
}

// Competition first: codes follow it, and the engine clears an aggregate when the competition has no knockouts.
if (compId) { console.log(`comp ${compId}`); await send("setCompetition", { competitionId: compId }); }
for (const side of ["home", "away"]) {
	const club = picks[side];
	await send("setTeam", {
		side,
		team: {
			clubId: club.id, name: club.name, shortName: club.shortName,
			code: (compId && club.codes?.[compId]) || club.defaultCode,
			primaryColour: club.primaryColour, secondaryColour: club.secondaryColour,
			textColour: club.textColour, crestFile: club.crestFile ?? null, squad: club.squad ?? null,
		},
	});
}
if (!values["keep-score"]) await send("reset");
if (values["first-leg"]) {
	const [h, a] = values["first-leg"].split(/[-:]/).map((n) => Number.parseInt(n, 10));
	if (!Number.isInteger(h) || !Number.isInteger(a)) throw new Error(`--first-leg wants a score like 2-1`);
	await send("setAggregate", { home: h, away: a });
	console.log(`first leg ${h}-${a}`);
}
if (values.kickoff) {
	const [hh, mm] = values.kickoff.split(":").map((n) => Number.parseInt(n, 10));
	const when = new Date(); when.setHours(hh, mm ?? 0, 0, 0);
	if (when.getTime() < Date.now() - 6 * 3600e3) when.setDate(when.getDate() + 1);
	await send("setKickoff", { kickoff: when.toISOString() });
	console.log(`kick-off ${when.toLocaleString("en-GB")}`);
}
if (values.show || values.hide) await send("setVisible", { visible: !!values.show });

if (!values["dry-run"]) {
	const state = await fetch(`${BASE}/api/state`).then((r) => r.json());
	const m = state.matches.find((x) => x.slot === slot);
	console.log(`\nslot ${slot}: ${m.home.name} (${m.home.code}) v ${m.away.name} (${m.away.code}), ${m.competitionId}, ${m.phase}, ${m.visible ? "on air" : "hidden"}${m.aggregate ? `, first leg ${m.aggregate.firstLegHome}-${m.aggregate.firstLegAway}` : ""}`);
}
