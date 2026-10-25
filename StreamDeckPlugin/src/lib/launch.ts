import { execFile } from "node:child_process";

// By bundle identifier, so a DMG install in /Applications launches as well as /Applications/JuniorOS Apps.
const BUNDLE_ID = "com.juniornkanabassi.Scorebug";
const COOLDOWN_MS = 15_000;
const TIMEOUT_MS = 10_000;
const POLL_MS = 250;
let lastLaunch = Number.NEGATIVE_INFINITY;

function launchApp(): Promise<void> {
	return new Promise((resolve, reject) => {
		execFile("/usr/bin/open", ["-g", "-b", BUNDLE_ID, "--args", "--background"], (error) => {
			if (error) reject(error);
			else resolve();
		});
	});
}

/** Launch only on a key press, then wait for the server before allowing the caller to retry its command. */
export async function launchAndWait(
	port: number,
	launch: () => Promise<void> = launchApp
): Promise<boolean> {
	if (Date.now() - lastLaunch >= COOLDOWN_MS) {
		lastLaunch = Date.now();
		try {
			await launch();
		} catch {
			// Keep polling: another Scorebug process may already be starting.
		}
	}

	const url = `http://127.0.0.1:${port}/api/state`;
	const deadline = Date.now() + TIMEOUT_MS;
	do {
		const started = Date.now();
		try {
			const response = await fetch(url, { signal: AbortSignal.timeout(200) });
			if (response.ok) return true;
		} catch {
			// The server has not bound its port yet.
		}
		await new Promise((resolve) => setTimeout(resolve, Math.max(0, POLL_MS - (Date.now() - started))));
	} while (Date.now() < deadline);
	return false;
}
