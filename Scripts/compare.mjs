#!/usr/bin/env node
// Manifest-driven comparison. Reference rectangles are manually measured with measure-reference.py;
// live rectangles come from the rendered DOM; pixel sampling/composites use the installed PIL.
import { parseArgs } from "node:util";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { openDriver, captureOne } from "./capture.mjs";

const execFileP = promisify(execFile);
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const outRoot = process.env.SCOREBUG_PIXEL_OUT || path.resolve(repoRoot, "../pixel-out");
const { values } = parseArgs({ options: {
  port: { type: "string", default: "8640" }, slot: { type: "string", default: "1" },
  only: { type: "string" }, theme: { type: "string" }, kind: { type: "string" }, "out-dir": { type: "string" },
} });
const port = Number(values.port), slot = values.slot === "2" ? 2 : 1;
const base = `http://127.0.0.1:${port}`;
const reportDir = path.resolve(values["out-dir"] || path.join(outRoot, "report"));
const captureDir = path.join(outRoot, "captures");
await fs.mkdir(reportDir, { recursive: true });
await fs.mkdir(captureDir, { recursive: true });
const manifest = JSON.parse(await fs.readFile(path.join(scriptDir, "references.json"), "utf8"));
const libraryPath = path.resolve(repoRoot, "../pixel-out/data/library.json");
const library = JSON.parse(await fs.readFile(libraryPath, "utf8"));
const clubsByCode = new Map();
for (const club of library.clubs || []) for (const code of new Set([club.defaultCode, ...Object.values(club.codes || {})])) {
  if (!clubsByCode.has(code)) clubsByCode.set(code, []);
  clubsByCode.get(code).push(club);
}
let entries = manifest.filter((e) => (!values.only || e.id === values.only) && (!values.theme || e.theme === values.theme) && (!values.kind || e.kind === values.kind));
if (!entries.length) throw new Error("No reference entries match the filters");

async function command(name, body = {}) {
  const res = await fetch(`${base}/api/match/${slot}/command`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ command: name, ...body }) });
  if (!res.ok) throw new Error(`${name} failed (${res.status}): ${await res.text()}`);
}

function referenceTeam(team, competitionId, side) {
  const matches = clubsByCode.get(team.code) || [];
  const club = matches.find((c) => c.codes?.[competitionId] === team.code) || matches.find((c) => c.defaultCode === team.code);
  if (club) return { clubId: club.id, name: club.name, shortName: club.shortName,
    code: club.codes?.[competitionId] || club.defaultCode, primaryColour: club.primaryColour,
    secondaryColour: club.secondaryColour, textColour: club.textColour, crestFile: null };
  return { name: team.code || side.toUpperCase(), shortName: team.code || side.toUpperCase(),
    code: team.code || (side === "home" ? "HOM" : "AWY"), primaryColour: team.primary || "#222222",
    secondaryColour: team.secondary || "#FFFFFF", textColour: team.text || "#FFFFFF", crestFile: null };
}
function periodFor(s) {
  if (s.period) return s.period;
  const n = s.clockSeconds ?? 0;
  return n < 2700 ? "firstHalf" : n < 5400 ? "secondHalf" : n < 6300 ? "extraFirst" : "extraSecond";
}
async function setState(s, { forHide = false } = {}) {
  await command("reset");
  await command("setCompetition", { competitionId: s.competitionId || "premier-league" });
  for (const side of ["home", "away"]) await command("setTeam", { side, team: referenceTeam(s[side] || {}, s.competitionId || "premier-league", side) });
  await command("setVisible", { visible: forHide || s.visible !== false });
  if (s.aggregate) await command("setAggregate", { home: s.aggregate.home, away: s.aggregate.away });
  if (s.phase === "shootout" || s.shootout) {
    await command("startPeriod", { period: "secondHalf" });
    await command("setClock", { seconds: Math.max(0, (s.clockSeconds ?? 5400) - 2700) });
    await command("startShootout", { side: s.shootout?.firstKicker || "home" });
    for (const k of s.shootout?.kicks || []) await command("recordKick", { side: k.side, result: k.result || "scored" });
  } else if (s.phase !== "preMatch") {
    const period = periodFor(s), baseSeconds = { firstHalf: 0, secondHalf: 2700, extraFirst: 5400, extraSecond: 6300 }[period];
    await command("startPeriod", { period });
    await command("setClock", { seconds: Math.max(0, (s.clockSeconds ?? baseSeconds) - baseSeconds) });
  }
  if (s.addedMinutes) await command("setAddedMinutes", { minutes: s.addedMinutes });
  for (const side of ["home", "away"]) for (let n = 0; n < (s[`${side}Score`] || 0); n++) await command("goal", { side });
  const seeded = await fetch(`${base}/api/state`).then((r) => r.json());
  const match = seeded.matches.find((m) => m.slot === slot);
  for (const goal of s.scorers || []) {
    const next = match.goals.filter((g) => g.side === goal.side).at(-1);
    if (next) await command("setScorer", { goalId: next.id, scorer: goal.scorer, ownGoal: !!goal.ownGoal, penalty: !!goal.penalty });
  }
  if (s.scorers?.length || s.showScorers) await command("setShowScorers", { showScorers: true });
  if (s.phase && s.phase !== "preMatch" && s.phase !== "shootout" && !s.shootout) {
    const period = periodFor(s), baseSeconds = { firstHalf: 0, secondHalf: 2700, extraFirst: 5400, extraSecond: 6300 }[period];
    await command("setClock", { seconds: Math.max(0, (s.clockSeconds ?? baseSeconds) - baseSeconds) });
    await command("pause");
  }
}

const selectorMap = { main: ".main", comp: ".comp", sep: ".sep span", home: ".team.home", away: ".team.away", scoreHome: ".score.home", scoreAway: ".score.away", clock: ".clock", added: ".added", agg: ".agg", scorers: ".scorers", shootout: ".shootout" };
const selectors = Object.entries(selectorMap);
const results = [];
let driver, driverOrientation;
async function useDriver(orientation) {
  if (driver && driverOrientation === orientation) return driver;
  if (driver) await driver.close();
  driverOrientation = orientation;
  driver = await openDriver({ width: orientation === "v" ? 1080 : 1920, height: orientation === "v" ? 1920 : 1080, scale: 2 });
  return driver;
}
try {
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    process.stdout.write(`[${i + 1}/${entries.length}] ${e.id}\n`);
    await setState(e.state, { forHide: e.demo?.startsWith("hide:") });
    const orientation = e.orientation || "h";
    await useDriver(orientation);
    const canvas = orientation === "v" ? [1080, 1920] : [1920, 1080];
    const settledScore = (e.state.homeScore || 0) + (e.state.awayScore || 0) > 0 && !e.demo?.startsWith("goal:");
    if (settledScore) await driver.waitForTimeout(4350);
    const capture = path.join(captureDir, `${e.id}.png`);
    await captureOne(driver, { port, orientation, slot, demo: e.demo || "show:900", outPath: capture, full: true });
    const captureBoxes = await driver.evaluate(() => {
      const selectors = { main: ".main", comp: ".comp", sep: ".sep span", home: ".team.home", away: ".team.away", scoreHome: ".score.home", scoreAway: ".score.away", clock: ".clock", added: ".added", agg: ".agg", scorers: ".scorers", shootout: ".shootout" };
      const boxes = Object.fromEntries(Object.entries(selectors).map(([k, s]) => { const n = document.querySelector(s), r = n?.getBoundingClientRect(); return [k, r && r.width && r.height ? [r.x, r.y, r.width, r.height] : null]; }));
      if (document.body.dataset.family === "uefa" && boxes.home && boxes.away) {
        const a = boxes.home, z = boxes.away;
        boxes.bar = [a[0], a[1], z[0] + z[2] - a[0], a[3]];
      }
      return boxes;
    });
    const hidden = e.state.visible === false || e.demo?.startsWith("hide:");
    if (e.expectedVisible === false) captureBoxes.bug = null;
    const specPath = path.join(captureDir, `${e.id}.json`);
    const preview = path.join(reportDir, `${e.id}.png`);
    const isGoalFrame = e.demo?.startsWith("goal:");
    const thresholds = structuredClone(e.thresholds || { default: { geometryPx: 2, deltaE: 6, maskedRMSE: 24 } });
    if (["premier-league", "champions-league"].includes(e.theme)) for (const name of ["home", "away", "scoreHome", "scoreAway"]) thresholds[name] = { ...(thresholds[name] || {}), scoreRMSE: false };
    const scoreElements = isGoalFrame ? (e.goalElements || {}) : (e.elements || {});
    const anchor = e.anchor || (e.elements?.comp ? "comp" : e.theme === "premier-league" ? "sep" : null);
    const spec = { id: e.id, reference: e.file, capture, preview, canvas, bugBox: e.bugBox, anchor, anchorBox: e.anchorBox || e.elements?.[anchor], expectedVisible: e.expectedVisible !== false, elements: scoreElements, expectedColours: e.expectedColours || {}, captureBoxes, thresholds };
    await fs.writeFile(specPath, JSON.stringify(spec));
    const { stdout } = await execFileP("python3", [path.join(scriptDir, "compare-image.py"), specPath], { maxBuffer: 2 * 1024 * 1024 });
    const measurement = JSON.parse(stdout.trim());
    const checks = Object.values(measurement.elements);
    const frameMs = e.goalFrameMs ?? (isGoalFrame ? Number(e.demo.split(":")[2]) : null);
    const captureMs = isGoalFrame ? Number(e.demo.split(":")[2]) : null;
    const item = { id: e.id, theme: e.theme, kind: e.kind, source: e.source, timestamp: e.timestamp, demo: e.demo || "show:900", goalFrameMs: frameMs, timingErrorMs: isGoalFrame ? captureMs - frameMs : null, expectedVisible: e.expectedVisible !== false, measured: measurement, portraitPaintedWidth: orientation === "v" ? captureBoxes.main?.[2] ?? null : null, masked: e.masked || ["club crest artwork", "player names", "video behind the graphic"], timing: e.goalTiming || null };
    item.status = isGoalFrame && !Object.keys(scoreElements).length ? "FAIL (goal-state targets missing)" : Math.max(Math.abs(measurement.offset[0]), Math.abs(measurement.offset[1])) > 100 ? "FAIL (harness alignment)" : checks.length ? (checks.every((m) => m.status === "PASS") ? "PASS" : "FAIL") : (measurement.visible === (e.expectedVisible !== false) ? "PASS" : "FAIL");
    item.result = e.kind === "broadcast" ? item.status : "advisory";
    results.push(item);
  }

  // The demo goal hook deliberately leaves .goal set. Prove the 4.2 s clear with an actual API goal
  // for each broadcast sequence, after the page has subscribed to the disposable instance.
  const clearChecks = [];
  for (const e of entries.filter((x) => x.goalClearCheck)) {
    await useDriver(e.orientation || "h");
    await setState(e.state);
    await captureOne(driver, { port, orientation: e.orientation || "h", slot, demo: "show:900", outPath: path.join(captureDir, `${e.id}-clear-start.png`), full: true });
    await driver.evaluate(async () => { const r = await fetch(`/api/match/${document.body.dataset.slot || 1}/command`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ command: "goal", side: "home" }) }); return r.ok; });
    await driver.waitForTimeout(4350);
    const cleared = await driver.evaluate(() => !document.getElementById("bug").classList.contains("goal"));
    await driver.screenshot({ path: path.join(reportDir, `${e.id}-real-goal-clear.png`) });
    clearChecks.push({ id: e.id, waitMs: 4350, cleared, status: cleared ? "PASS" : "FAIL" });
  }

  const buckets = new Map();
  for (const r of results.filter((x) => x.kind === "broadcast" && !x.demo.startsWith("goal:"))) for (const [name, m] of Object.entries(r.measured.elements)) {
    const key = `${r.theme} / ${name}`;
    const b = buckets.get(key) || { pass: 0, fail: 0, worstGeometryPx: 0, worstDeltaE: 0, worstRMSE: 0 };
    if (m.status === "PASS") b.pass++; else b.fail++;
    if (m.edgeOffsets) b.worstGeometryPx = Math.max(b.worstGeometryPx, ...Object.values(m.edgeOffsets).map(Math.abs));
    b.worstDeltaE = Math.max(b.worstDeltaE, m.deltaE76 || 0); b.worstRMSE = Math.max(b.worstRMSE, m.maskedRMSE || 0);
    buckets.set(key, b);
  }
  const summary = [...buckets].map(([element, b]) => ({ element, ...b }));
  const final = { run: { port, slot, selected: entries.length, timestamp: new Date().toISOString() }, entries: results, goalClearChecks: clearChecks, summary };
  await fs.writeFile(path.join(reportDir, "report.json"), JSON.stringify(final, null, 2));
  const lines = ["# Scorebug overlay comparison", "", `Run: ${final.run.timestamp}; disposable API port ${port}; ${results.length} reference entries.`, "", "## Summary", "", "| Theme | Element | PASS | FAIL | Worst edge offset (px) | Worst ΔE76 | Worst masked RMSE |", "|---|---|---:|---:|---:|---:|---:|"];
  for (const s of summary) lines.push(`| ${s.element.split(" / ")[0]} | ${s.element.split(" / ")[1]} | ${s.pass} | ${s.fail} | ${s.worstGeometryPx.toFixed(2)} | ${s.worstDeltaE.toFixed(2)} | ${s.worstRMSE.toFixed(2)} |`);
  lines.push("", "## Goal clear checks", "", "| Sequence | Wait | Result |", "|---|---:|---|");
  for (const c of clearChecks) lines.push(`| ${c.id} | ${c.waitMs} ms | ${c.status} |`);
  lines.push("", "## Per-reference findings", "");
  for (const r of results) {
    lines.push(`### ${r.id} — ${r.result === "advisory" ? "advisory" : r.status}`, "", `- Source: ${r.source || r.kind}${r.timestamp ? `, ${r.timestamp}` : ""}; ${r.kind}; theme ${r.theme}; capture ${r.demo}.`, `- Alignment: scale ${r.measured.scale}; offset (${r.measured.offset.join(", ")}) px; anchor ${JSON.stringify(r.measured.anchor)}; target ${JSON.stringify(r.measured.targetBox)}; source alpha box ${JSON.stringify(r.measured.sourceBox)}.`, `- Masked: ${r.masked.join(", ")}.`);
    if (r.timing) lines.push(`- Broadcast timing: ${r.timing.map((t) => `${t.label} ${t.ms} ms`).join("; ")}; captures freeze at the same offsets (±40 ms target).`);
    if (r.demo.startsWith("goal:")) lines.push(`- Goal-frame timing sample: reference ${r.goalFrameMs} ms; capture ${r.goalFrameMs + r.timingErrorMs} ms; sampling error ${r.timingErrorMs} ms. ${Object.keys(r.measured.elements).length ? "Goal-state element targets were measured." : "FAIL: wipe band, wordmark box and settled-score targets are not annotated in references.json, so no visual timing verdict is claimed."}`);
    lines.push("", "| Element | Result | Edges L/T/R/B (px) | Size W×H ratio | ΔE76 | masked RMSE |", "|---|---|---|---|---:|---:|");
    for (const [name, m] of Object.entries(r.measured.elements)) lines.push(`| ${name} | ${m.status} | ${m.edgeOffsets ? Object.values(m.edgeOffsets).join(" / ") : "—"} | ${m.sizeRatio ? `${m.sizeRatio.width} × ${m.sizeRatio.height}` : "—"} | ${m.deltaE76 ?? "—"} | ${m.maskedRMSE ?? "—"} |`);
    lines.push(`| image | [${r.id}.png](./${r.id}.png) | | | | |`, "");
  }
  lines.push("## Method", "", "Reference element and anchor rectangles are manually measured in source pixels. Scale and translation are solved from the fixed competition square or Premier League roundel, never from the alpha bounds. Offsets over 100 px fail the harness. Text glyphs, crests and video are masked from plate RMSE; team-coloured Premier League plates are colour-scored without RMSE. Goal captures freeze at the source frame's 25 fps offset and report sampling error; wipe/wordmark/settled-score visual timing remains unscored until those goal-state boxes are annotated. Scored states wait 4.35 s after seeding so the seed goal does not leave the UI in a goal animation. Portrait painted widths come from the transformed main DOM box; only `kind: broadcast` controls pass/fail, while template and regression items are advisory.", "");
  await fs.writeFile(path.join(reportDir, "report.md"), lines.join("\n"));
  console.log(`\n${summary.map((s) => `${s.element}\tPASS ${s.pass}\tFAIL ${s.fail}\tworst ${s.worstGeometryPx.toFixed(1)} px / ΔE ${s.worstDeltaE.toFixed(1)} / RMSE ${s.worstRMSE.toFixed(1)}`).join("\n")}`);
  console.log(`report: ${path.join(reportDir, "report.md")}`);
} finally { if (driver) await driver.close(); }
