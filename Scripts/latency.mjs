#!/usr/bin/env node
// Latency table for a disposable Scorebug instance: command round trip, GET /api/state round trip, and
// WebSocket message to next painted frame measured inside the real overlay page.
import { parseArgs } from "node:util";
import { pathToFileURL } from "node:url";
import { openDriver } from "./capture.mjs";

function percentile(sorted, p) {
  const idx = Math.max(0, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.min(sorted.length - 1, idx)];
}
function stats(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  return { p50: percentile(sorted, 50), p95: percentile(sorted, 95) };
}

async function timeFetch(url, opts) {
  const t0 = performance.now();
  const res = await fetch(url, opts);
  await res.arrayBuffer(); // drain the body so timing covers the full response, not just the headers
  const t1 = performance.now();
  if (!res.ok) throw new Error(`${url} -> HTTP ${res.status}`);
  return t1 - t0;
}

// Every message on /ws corresponds to one revision, so the wrapped onmessage below sees exactly one call per
// command sent. It measures message receipt to the next requestAnimationFrame, i.e. message to painted frame.
function patchWebSocketTiming() {
  window.__lat = [];
  const desc = Object.getOwnPropertyDescriptor(WebSocket.prototype, "onmessage");
  Object.defineProperty(WebSocket.prototype, "onmessage", {
    configurable: true,
    get() { return desc.get.call(this); },
    set(handler) {
      desc.set.call(this, function (ev) {
        const t0 = performance.now();
        handler.call(this, ev);
        requestAnimationFrame(() => window.__lat.push(performance.now() - t0));
      });
    },
  });
}

async function measurePaintLatency(base, samples) {
  const driver = await openDriver({ width: 1920, height: 1080, scale: 2 });
  try {
    await driver.addInitScript(patchWebSocketTiming);
    await driver.goto(`${base}/overlay/h/1`);
    await driver.waitForFunction(() => !!document.getElementById("bug")?.dataset.phase, { timeout: 10000 });
    await driver.evaluate(() => { window.__lat.length = 0; return true; });
    for (let i = 0; i < samples; i++) {
      const before = await driver.evaluate(() => window.__lat.length);
      await fetch(`${base}/api/match/1/command`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ command: "goal", side: "home", delta: i % 2 === 0 ? 1 : -1 }),
      });
      const start = Date.now();
      while (Date.now() - start < 2000) {
        if ((await driver.evaluate(() => window.__lat.length)) > before) break;
        await driver.waitForTimeout(20);
      }
    }
    return { backend: driver.backend, samples: await driver.evaluate(() => window.__lat.slice()) };
  } finally {
    await driver.close();
  }
}

function printTable(rows) {
  const widths = [28, 6, 10, 10];
  const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join("");
  console.log(line(["metric", "n", "p50 ms", "p95 ms"]));
  for (const row of rows) console.log(line(row));
}

async function main() {
  const { values } = parseArgs({ options: { port: { type: "string" }, samples: { type: "string", default: "100" } } });
  if (!values.port) throw new Error("--port is required");
  const base = `http://127.0.0.1:${Number(values.port)}`;
  const samples = Number(values.samples);
  const paintSamples = Math.min(samples, 30); // the brief's fixed goal-alternation probe

  const commandSamples = [];
  for (let i = 0; i < samples; i++) {
    commandSamples.push(await timeFetch(`${base}/api/match/1/command`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ command: "setAddedMinutes", minutes: null }),
    }));
  }
  const stateSamples = [];
  for (let i = 0; i < samples; i++) stateSamples.push(await timeFetch(`${base}/api/state`));

  const paint = await measurePaintLatency(base, paintSamples);

  console.log(`backend: ${paint.backend}`);
  const commandStats = stats(commandSamples);
  const stateStats = stats(stateSamples);
  const paintStats = stats(paint.samples);
  printTable([
    ["POST /command", samples, commandStats.p50.toFixed(2), commandStats.p95.toFixed(2)],
    ["WS message to paint", paint.samples.length, paintStats.p50.toFixed(2), paintStats.p95.toFixed(2)],
    ["GET /api/state", samples, stateStats.p50.toFixed(2), stateStats.p95.toFixed(2)],
  ]);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((err) => { console.error(err); process.exit(1); });
}
