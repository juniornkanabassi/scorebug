// Shared name resolution for setup-match and the supported CLI.
export const fold = (s) => (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, "").trim();
const WORD_NOISE = new Set(["fc", "cf", "afc", "sc", "ac", "as", "ss", "us", "club", "de", "the", "1", "05", "04", "08", "09"]);
export const words = (s) => fold(s).split(/\s+/).filter((w) => w && !WORD_NOISE.has(w));

/** How well a library club matches what was typed. Higher is better; 0 means no. */
export function score(club, query) {
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

export function pickClub(clubs, query, competitionId) {
	const ranked = clubs
		.map((c) => ({ club: c, s: score(c, query) + (competitionId && (c.competitionIds ?? []).includes(competitionId) ? 15 : 0) }))
		.filter((r) => r.s > 0)
		.sort((a, b) => b.s - a.s);
	return { best: ranked[0]?.club, alternatives: ranked.slice(1, 4).map((r) => r.club.name), top: ranked[0]?.s ?? 0 };
}

export function pickCompetition(comps, query) {
	if (!query) return undefined;
	const q = fold(query);
	const alias = {
		ucl: "champions-league", cl: "champions-league", ecl: "conference-league", uel: "europa-league",
		el: "europa-league", pl: "premier-league", epl: "premier-league", laliga: "la-liga",
		ligue1: "ligue1", l1: "ligue1", seriea: "serie-a", bundesliga: "bundesliga", unl: "nations-league",
	}[q.replace(/\s+/g, "")];
	return comps.find((c) => c.id === (alias ?? q) || fold(c.id) === q) ??
		comps.find((c) => fold(c.name) === q || fold(c.shortName) === q) ??
		comps.find((c) => fold(c.name).includes(q));
}

export function teamEntry(club, competitionId) {
 return {clubId: club.id, name: club.name, shortName: club.shortName,
 code: (competitionId && club.codes?.[competitionId]) || club.defaultCode,
 primaryColour: club.primaryColour, secondaryColour: club.secondaryColour,
 textColour: club.textColour, crestFile: club.crestFile ?? null, squad: club.squad ?? null};
}
