#!/usr/bin/env node
// Run only against disposable data on a spare port.
import assert from 'node:assert/strict';
import { request as http } from 'node:http';
const port = Number(process.env.SCOREBUG_PORT);
assert(Number.isInteger(port) && port >= 1024 && port <= 65535 && port !== 8600, 'Set SCOREBUG_PORT to a disposable port');
const base = `http://127.0.0.1:${port}`;
let checks = 0;
async function request(path, expected, options = {}) {
  const r = await fetch(base + path, options); assert.equal(r.status, expected, `${path} ${JSON.stringify(options)}: ${await r.clone().text()}`); checks++; return r;
}
const post = (body, expected = 200) => request('/api/match/1/command', expected, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }).then(r => r.status === 200 ? r.json() : r.text());
await request('/api/state', 403, { headers: { origin: 'https://evil.test' } });
await request('/ws', 403, { headers: { origin: 'null', upgrade: 'websocket' } }).catch(async e => { // fetch forbids Upgrade; a normal GET must be guarded too.
  if (e instanceof TypeError) await request('/ws', 403, { headers: { origin: 'null' } }); else throw e;
});
await new Promise((resolve, reject) => { const r = http(`${base}/api/state`, { headers: { Host: `evil.test:${port}` } }, res => { try { assert.equal(res.statusCode, 403); checks++; res.resume(); resolve(); } catch(e) { reject(e); } }); r.on('error', reject); r.end(); });
await request('/api/match/1/command', 415, { method: 'POST', headers: { 'content-type': 'text/plain' }, body: '{"command":"reset"}' });
await request('/api/state', 200, { headers: { origin: `http://localhost:${port}` } });
await request('/api/state', 200);
await request('/api/match/1/command', 413, { method: 'POST', headers: { 'content-type': 'application/json' }, body: ' '.repeat(65537) });
await post({ command: 'reset' });
await post({ command: 'recordKick', result: 'scored', strict: true }, 409);
await post({ command: 'startPeriod', period: 'secondHalf' });
const shootout = await post({ command: 'startShootout', strict: true, requestId: 'security-shootout' });
await post({ command: 'recordKick', result: 'scored', strict: true });
await post({ command: 'startShootout', strict: true }, 409);
const kept = await (await request('/api/state', 200)).json(); assert.equal(kept.matches[0].shootout.kicks.length, 1); checks++;
await post({ command: 'setKick', side: 'home', index: 0, result: 'scored', strict: true, requestId: 'security-edit' }, 409);
await post({ command: 'setKick', side: 'home', index: 0, result: 'missed' });
const edited = await post({ command: 'setKick', side: 'home', index: 0, result: 'scored', strict: true, requestId: 'security-edit' });
assert.equal(edited.matches[0].shootout.kicks[0].result, 'scored'); checks++;
await post({ command: 'reset' });
assert.deepEqual(await post({ command: 'startShootout', strict: true, requestId: 'security-shootout' }), shootout); checks++;
const once = await post({ command: 'goal', side: 'home', requestId: 'security-goal' });
const twice = await post({ command: 'goal', side: 'home', requestId: 'security-goal' });
assert.deepEqual(twice, once); assert.equal(twice.matches[0].homeScore, 1); checks++;
await post({ command: 'goal', side: 'home' });
const noId = await post({ command: 'goal', side: 'home' }); assert.equal(noId.matches[0].homeScore, 3); checks++;
await post({ command: 'setTheme', themeId: '../bad' }, 400);
await post({ command: 'setCompetition', competitionId: 'bad' }, 400);
await post({ command: 'goal', side: 'home', requestId: '' }, 400);
await post({ command: 'linkESPN', eventId: '../bad', competitionId: 'eng.1' }, 400);
const themes = await (await request('/api/themes', 200)).json(); assert.equal(themes.length, 8); checks++;
await request('/api/status', 200);
const library = await (await request('/api/library', 200)).json();
const club = library.clubs.find(c => Object.entries(c.codes ?? {}).some(([id, code]) => code !== c.defaultCode && library.competitions.some(x => x.id === id)));
assert(club, 'fixture must include a per-competition club code');
const [id, code] = Object.entries(club.codes).find(([id, code]) => code !== club.defaultCode && library.competitions.some(x => x.id === id));
await post({ command: 'setTeam', side: 'home', team: { ...club, clubId: club.id, code: club.defaultCode } });
const changed = await post({ command: 'setCompetition', competitionId: id }); assert.equal(changed.matches[0].home.code, code); checks++;
for (const [origin, expected] of [['https://evil.test', 403], [`http://127.0.0.1:${port}`, 101]]) {
  await new Promise((resolve, reject) => {
    const r = http(`${base}/ws`, { headers: { Origin: origin, Upgrade: 'websocket', Connection: 'Upgrade', 'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==', 'Sec-WebSocket-Version': '13' } });
    const done = (res, socket) => { try { assert.equal(res.statusCode, expected); checks++; socket?.destroy(); res.destroy(); resolve(); } catch(e) { reject(e); } };
    r.on('response', res => done(res)); r.on('upgrade', (res, socket) => done(res, socket)); r.on('error', reject); r.end();
  });
}
// Review 6 is accepted only while the listener is loopback-only; keep observing it.
await new Promise((resolve, reject) => {
  const r = http(`${base}/api/status`, { headers: { 'X-Oversized': 'x'.repeat(65537) }, timeout: 3000 }, res => {
    console.log(`accepted limitation (Review 6): 65,537-byte header returns HTTP ${res.statusCode}; FlyingFox has no decoder size cap/deadline`);
    res.resume(); res.on('end', resolve);
  });
  r.on('timeout', () => r.destroy(new Error('header observation timed out')));
  r.on('error', reject); r.end();
});
console.log(`${checks} security runtime checks passed`);
