// Lead's OBS check over obs-websocket 5 (port 4455). Node 22: built-in WebSocket and fetch.
// usage: OBS_PASSWORD=… node obs-check.mjs <outdir> [goalSide]
import { createHash } from "node:crypto"; import { writeFileSync, mkdirSync } from "node:fs";
const pw = process.env.OBS_PASSWORD ?? ""; const [out, goalSide] = process.argv.slice(2); mkdirSync(out, { recursive: true });
const ws = new WebSocket("ws://127.0.0.1:4455"); let n = 0; const pending = new Map();
const req = (requestType, requestData = {}) => new Promise((res, rej) => { const requestId = String(++n); pending.set(requestId, { res, rej }); ws.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } })); });
const ready = new Promise(res => { ws.onmessage = e => { const { op, d } = JSON.parse(e.data);
  if (op === 0) { let auth; if (d.authentication) { const { challenge, salt } = d.authentication; const secret = createHash("sha256").update(pw + salt).digest("base64"); auth = createHash("sha256").update(secret + challenge).digest("base64"); }
    ws.send(JSON.stringify({ op: 1, d: { rpcVersion: 1, authentication: auth } })); }
  if (op === 2) res(); if (op === 7) { const p = pending.get(d.requestId); pending.delete(d.requestId); d.requestStatus.result ? p.res(d.responseData ?? {}) : p.rej(new Error(`${d.requestType}: ${d.requestStatus.comment}`)); } }; });
await ready;
const stats = async label => { const s = await req("GetStats"); console.log(label, JSON.stringify({ cpu: +s.cpuUsage.toFixed(1), fps: +s.activeFps.toFixed(1), renderSkipped: s.renderSkippedFrames, renderTotal: s.renderTotalFrames, outputSkipped: s.outputSkippedFrames, avgRenderMs: +s.averageFrameRenderTime.toFixed(2) })); return s; };
console.log("profile", (await req("GetProfileList")).currentProfileName); console.log("collection", (await req("GetSceneCollectionList")).currentSceneCollectionName);
const inputs = (await req("GetInputList")).inputs.filter(i => /scorebug/i.test(i.inputName)); console.log("scorebug inputs", inputs.map(i => i.inputName));
for (const i of inputs) { const s = await req("GetInputSettings", { inputName: i.inputName }); console.log(" ", i.inputName, s.inputSettings.url, s.inputSettings.width + "x" + s.inputSettings.height, "fps", s.inputSettings.fps_custom ? s.inputSettings.fps : "canvas"); }
const shot = async (i, tag) => { const r = await req("GetSourceScreenshot", { sourceName: i.inputName, imageFormat: "png" }); writeFileSync(`${out}/${i.inputName.replace(/[^\w]+/g, "_")}-${tag}.png`, Buffer.from(r.imageData.split(",")[1], "base64")); };
for (const i of inputs) await shot(i, "steady");
await stats("before");
if (goalSide) { await fetch("http://127.0.0.1:8600/api/match/1/command", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ command: "goal", side: goalSide }) });
  await new Promise(r => setTimeout(r, 600)); for (const i of inputs) await shot(i, "goal"); await stats("during"); await new Promise(r => setTimeout(r, 4000)); await stats("after");
  await fetch("http://127.0.0.1:8600/api/match/1/command", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ command: "goal", side: goalSide, delta: -1 }) }); }
ws.close();
