#!/usr/bin/env node
// Screenshot harness for the overlay pages. Waits for the WebSocket state, applies the ?demo= freeze,
// then screenshots the bug at device scale 2 with a transparent background.
import { parseArgs } from "node:util";
import { pathToFileURL, fileURLToPath } from "node:url";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { setTimeout as sleep } from "node:timers/promises";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const execFileP = promisify(execFile);
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// ---- Driver: Playwright when it is installed anywhere usable, else Chrome DevTools Protocol over WebSocket. ----
// Both backends expose the same small surface so the rest of this file, and latency.mjs, never branch on which one is live.

async function findPlaywright() {
  try { return await import("playwright"); } catch {}
  try {
    const { stdout } = await execFileP("npm", ["root", "-g"]);
    const root = stdout.trim();
    for (const rel of ["playwright/index.mjs", "@playwright/cli/node_modules/playwright/index.mjs"]) {
      const file = path.join(root, rel);
      try { await fs.access(file); return await import(pathToFileURL(file).href); } catch {}
    }
  } catch {}
  return null;
}

async function openPlaywright(pw, { width, height, scale }) {
  const browser = await pw.chromium.launch({ channel: "chrome", headless: true });
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: scale });
  const page = await context.newPage();
  return {
    backend: "playwright",
    addInitScript: (fn) => page.addInitScript(fn),
    goto: (url) => page.goto(url, { waitUntil: "load" }),
    evaluate: (fn) => page.evaluate(fn),
    waitForFunction: (fn, opts) => page.waitForFunction(fn, undefined, opts),
    waitForTimeout: (ms) => page.waitForTimeout(ms),
    screenshot: (opts) => page.screenshot({ omitBackground: true, type: "png", ...opts }),
    close: () => browser.close(),
  };
}

async function openCDP({ width, height, scale }) {
  const userDataDir = await fs.mkdtemp(path.join(os.tmpdir(), "scorebug-cdp-"));
  const proc = spawn(CHROME, [
    "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${userDataDir}`,
    "--disable-gpu", "--hide-scrollbars", `--force-device-scale-factor=${scale}`,
    `--window-size=${width},${height}`, "--no-first-run", "--no-default-browser-check",
  ], { stdio: "ignore" });

  const portFile = path.join(userDataDir, "DevToolsActivePort");
  let cdpPort;
  for (let i = 0; i < 100; i++) {
    try { cdpPort = Number((await fs.readFile(portFile, "utf8")).split("\n")[0]); break; }
    catch { await sleep(100); }
  }
  if (!cdpPort) throw new Error("Chrome DevTools endpoint did not come up");

  const target = await (await fetch(`http://127.0.0.1:${cdpPort}/json/new?about:blank`, { method: "PUT" })).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });

  let nextId = 0;
  const pending = new Map();
  const events = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id != null && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    } else if (msg.method) {
      events.get(msg.method)?.forEach((fn) => fn(msg.params));
    }
  };
  const on = (method, fn) => { if (!events.has(method)) events.set(method, new Set()); events.get(method).add(fn); };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++nextId; pending.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params }));
  });

  await send("Page.enable");
  await send("Runtime.enable");
  await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: scale, mobile: false });
  await send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });

  const evaluate = async (fn) => {
    const expression = `(${fn})()`;
    const result = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
    return result.result.value;
  };

  return {
    backend: "cdp",
    addInitScript: (fn) => send("Page.addScriptToEvaluateOnNewDocument", { source: `(${fn})();` }),
    goto: (url) => new Promise((resolve) => { on("Page.loadEventFired", function once() { events.get("Page.loadEventFired").delete(once); resolve(); }); send("Page.navigate", { url }); }),
    evaluate,
    waitForFunction: async (fn, { timeout = 10000, polling = 100 } = {}) => {
      const start = Date.now();
      while (Date.now() - start < timeout) {
        if (await evaluate(fn)) return;
        await sleep(polling);
      }
      throw new Error("waitForFunction timed out");
    },
    waitForTimeout: (ms) => sleep(ms),
    screenshot: async ({ clip, path: outPath }) => {
      const params = { format: "png", captureBeyondViewport: true };
      if (clip) params.clip = { x: clip.x, y: clip.y, width: clip.width, height: clip.height, scale: 1 };
      const { data } = await send("Page.captureScreenshot", params);
      const buf = Buffer.from(data, "base64");
      if (outPath) await fs.writeFile(outPath, buf);
      return buf;
    },
    close: async () => { ws.close(); proc.kill(); await fs.rm(userDataDir, { recursive: true, force: true }); },
  };
}

export async function openDriver({ width, height, scale = 2 }) {
  const pw = await findPlaywright();
  if (pw) { try { return await openPlaywright(pw, { width, height, scale }); } catch { /* fall through to CDP */ } }
  return openCDP({ width, height, scale });
}

// ---- Capture ----

// The overlay's WebSocket state has arrived once #bug carries a phase; document.fonts.ready covers custom faces.
async function waitReady(driver) {
  await driver.waitForFunction(() => !!document.getElementById("bug")?.dataset.phase, { timeout: 10000 });
  await driver.evaluate(async () => { await document.fonts.ready; return true; });
}

export async function captureOne(driver, { port, orientation, slot, demo, outPath, full }) {
  const url = `http://127.0.0.1:${port}/overlay/${orientation}/${slot}` + (demo ? `?demo=${encodeURIComponent(demo)}` : "");
  await driver.goto(url);
  await waitReady(driver);
  // The ?demo= hook fires 900ms after load, then pauses document.getAnimations() at the requested millisecond;
  // wait a little past that before reading the frozen frame.
  if (demo) await driver.waitForTimeout(1300);
  let clip;
  if (!full) {
    const box = await driver.evaluate(() => {
      const r = document.getElementById("bug").getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    });
    const pad = 8;
    clip = { x: Math.max(0, box.x - pad), y: Math.max(0, box.y - pad), width: box.width + pad * 2, height: box.height + pad * 2 };
  }
  await driver.screenshot({ path: outPath, clip });
  return outPath;
}

async function tileFrames(paths, sheetPath) {
  const inputs = paths.flatMap((p) => ["-i", p]);
  await execFileP("ffmpeg", ["-y", ...inputs, "-filter_complex", `hstack=inputs=${paths.length}`, sheetPath]);
}

async function main() {
  const { values } = parseArgs({
    options: {
      port: { type: "string" },
      slot: { type: "string", default: "1" },
      orientation: { type: "string", default: "h" },
      demo: { type: "string" },
      out: { type: "string" },
      series: { type: "string" },
      sheet: { type: "string" },
      full: { type: "boolean", default: false },
    },
  });
  if (!values.port) throw new Error("--port is required");
  const port = Number(values.port);
  const slot = values.slot;
  const orientation = values.orientation === "v" ? "v" : "h";
  const width = orientation === "v" ? 1080 : 1920;
  const height = orientation === "v" ? 1920 : 1080;

  const driver = await openDriver({ width, height, scale: 2 });
  try {
    if (values.series) {
      const points = values.series.split(",").map(Number);
      const base = (values.demo || "show").replace(/:\d+$/, "");
      const stem = (values.out || "/tmp/frame").replace(/\.png$/, "");
      const framePaths = [];
      for (const t of points) {
        // Series frames are always full-canvas so every frame in the sheet shares one size; the bug itself moves
        // during show/hide, so a bounding-box crop would not tile cleanly.
        const framePath = `${stem}-${t}.png`;
        await captureOne(driver, { port, orientation, slot, demo: `${base}:${t}`, outPath: framePath, full: true });
        framePaths.push(framePath);
      }
      if (values.sheet) { await tileFrames(framePaths, values.sheet); console.log(values.sheet); }
      framePaths.forEach((p) => console.log(p));
    } else {
      if (!values.out) throw new Error("--out is required (or use --series with --sheet)");
      await captureOne(driver, { port, orientation, slot, demo: values.demo, outPath: values.out, full: values.full });
      console.log(values.out);
    }
  } finally {
    await driver.close();
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((err) => { console.error(err); process.exit(1); });
}
