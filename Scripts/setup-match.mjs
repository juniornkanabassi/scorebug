#!/usr/bin/env node
// Sets a slot up for a match from plain team names, so a stream can be prepared from a chat message
// instead of the window. Talks to a running Scorebug over its HTTP API; builds nothing, installs nothing.
//
//   node setup-match.mjs --home "Real Madrid" --away Inter --competition ucl
//   node setup-match.mjs --home Arsenal --away Chelsea --competition premier-league --slot 2 --show
//   node setup-match.mjs --home "Real Madrid" --away Inter --competition ucl --first-leg 2-1
//   node setup-match.mjs --list "real"        # what the library knows, no changes
//
// Flags: --home --away --competition --slot (1) --first-leg H-A --show --hide
//        --keep-score (skip the reset) --port (8600) --dry-run --list <query>
import { parseArgs } from "node:util";

const { values } = parseArgs({
	options: {
		home: { type: "string" }, away: { type: "string" }, competition: { type: "string" },
		fixture: { type: "string" }, pick: { type: "string" }, force: { type: "boolean" },
		slot: { type: "string", default: "1" }, "first-leg": { type: "string" },
		show: { type: "boolean" }, hide: { type: "boolean" }, "keep-score": { type: "boolean" },
		port: { type: "string", default: "8600" }, "dry-run": { type: "boolean" }, list: { type: "string" },
	},
});
const BASE = `http://127.0.0.1:${values.port}`;
const slot = values.slot === "2" ? 2 : 1;

import { score, pickClub, pickCompetition, teamEntry } from "./match-lib.mjs";

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

if (values.fixture) {
	const now = new Date();
	const date = values.fixture === "today" ? `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}` : values.fixture;
	if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("--fixture wants today or YYYY-MM-DD");
	const query = new URLSearchParams({ date });
	if (values.competition) query.set("competition", pickCompetition(library.competitions, values.competition)?.id ?? values.competition);
	const response = await fetch(`${BASE}/api/fixtures?${query}`);
	if (!response.ok) throw new Error(`Fixture request failed: ${response.status} ${await response.text()}`);
	const fixtures = await response.json();
	for (const [i, f] of fixtures.entries()) console.log(`${i + 1}. ${new Date(f.kickoff).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}  ${f.home.name} v ${f.away.name}  ${f.competitionCode}`);
	if (values.pick !== undefined) {
		const index = Number.parseInt(values.pick, 10) - 1;
		if (!Number.isInteger(index) || !fixtures[index]) throw new Error(`--pick must be between 1 and ${fixtures.length}`);
		const chosen = { ...fixtures[index], ...(values.force ? { force: true } : {}) };
		if (values["dry-run"]) { console.log(`  would load fixture ${index + 1} into slot ${slot}`); process.exit(0); }
		const result = await fetch(`${BASE}/api/match/${slot}/loadFixture`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(chosen) });
		if (!result.ok) throw new Error(`Fixture load failed: ${result.status} ${await result.text()}`);
		console.log(`Loaded fixture ${index + 1} into slot ${slot}.`);
	}
	process.exit(0);
}

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
let weak = false;
for (const side of ["home", "away"]) {
	const query = values[side];
	const { best, alternatives, top } = pickClub(library.clubs, query, compId);
	if (!best) throw new Error(`No club matching "${query}". Try --list "${query}".`);
	picks[side] = best;
	const note = top < 60 ? `  (weak match${alternatives.length ? `, also considered ${alternatives.join(", ")}` : ""}, check this)` : "";
	console.log(`${side.padEnd(4)} ${query} -> ${best.name}${note}`);
	if (note) weak = true;
}
// A weak match stops unless --force: a wrong crest on air is worse than a stopped script (28 Sep, Burnley became Arsenal).
if (weak && !values.force && !values["dry-run"]) { console.error("Stopped: a club matched weakly. Check with --list, or rerun with --force."); process.exit(3); }

// Competition first: codes follow it, and the engine clears an aggregate when the competition has no knockouts.
if (compId) { console.log(`comp ${compId}`); await send("setCompetition", { competitionId: compId }); }
for (const side of ["home", "away"]) {
	const club = picks[side];
	await send("setTeam", {
		side,
		team: teamEntry(club, compId),
	});
}
if (!values["keep-score"]) await send("reset");
if (values["first-leg"]) {
	const [h, a] = values["first-leg"].split(/[-:]/).map((n) => Number.parseInt(n, 10));
	if (!Number.isInteger(h) || !Number.isInteger(a)) throw new Error(`--first-leg wants a score like 2-1`);
	await send("setAggregate", { home: h, away: a });
	console.log(`first leg ${h}-${a}`);
}
if (values.show || values.hide) await send("setVisible", { visible: !!values.show });

if (!values["dry-run"]) {
	const state = await fetch(`${BASE}/api/state`).then((r) => r.json());
	const m = state.matches.find((x) => x.slot === slot);
	console.log(`\nslot ${slot}: ${m.home.name} (${m.home.code}) v ${m.away.name} (${m.away.code}), ${m.competitionId}, ${m.phase}, ${m.visible ? "on air" : "hidden"}${m.aggregate ? `, first leg ${m.aggregate.firstLegHome}-${m.aggregate.firstLegAway}` : ""}`);
}
