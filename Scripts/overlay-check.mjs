// Execute the production overlay script with a minimal DOM; no browser, app or network is launched.
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
let checks = 0;
const eq = (actual, expected) => { assert.equal(actual, expected); checks++; };
const tick = () => new Promise(r=>setImmediate(r));
const themes = new Map([['ligue1',{id:'ligue1',clockStyle:'runOn',geometry:{v:{top:260,top2:400,scale:2},h:{top:80,scale:1}}}],['stealth',{id:'stealth',clockStyle:'runOn',geometry:{v:{top:260,top2:400,scale:1.56},h:{top:80,scale:1}}}]]);
const team = {name:'Team',shortName:'Team',code:'TMP',primaryColour:'#000000',secondaryColour:'#ffffff',textColour:'#ffffff'};
const snapshot = slot => ({serverTime:Date.now(),overlay:{portraitTop:100,themeOverrides:true},competitions:[{id:'ligue1',shortName:'L1',themeId:'ligue1'}],matches:[{slot,competitionId:'ligue1',revision:1,home:team,away:team,clock:{running:false,periodBaseSeconds:0,accumulated:0},phase:'preMatch',homeScore:0,awayScore:0,visible:true,goals:[]}]});
const topFor = (orientation, slot) => orientation==='v' ? (slot===2?'240px':'100px') : '80px';
function boot(orientation, slot, fetch) {
 const nodes = new Map();
 function node(id) {
  if (nodes.has(id)) return nodes.get(id);
  const classes = new Set(), styles = new Map();
  const n = {dataset:{},textContent:'',style:{setProperty:(k,v)=>styles.set(k,v),getPropertyValue:k=>styles.get(k)},classList:{add:(...xs)=>xs.forEach(x=>classes.add(x)),remove:(...xs)=>xs.forEach(x=>classes.delete(x)),contains:x=>classes.has(x),toggle:(x,v)=>v?classes.add(x):classes.delete(x)},append(){},appendChild(){},before(){},querySelector:s=>node(s),offsetWidth:100};
  nodes.set(id,n); return n;
 }
 const body = node('body'); body.dataset = {orientation,slot:String(slot)};
 // Every theme.css assignment is recorded, so a retry is visible even within the same millisecond.
 const cssLoads = []; Object.defineProperty(node('theme-css'),'href',{get:()=>cssLoads.at(-1),set:v=>cssLoads.push(v)});
 const env = {node, body, cssLoads, probes:[], timeouts:[], intervals:new Map(), reloads:0, socket:null};
 const context = vm.createContext({document:{body,getElementById:node,createElement:()=>node(Symbol()),getAnimations:()=>[]},location:{search:'',protocol:'http:',host:'127.0.0.1:8680',reload:()=>env.reloads++},URLSearchParams,Date,console,Image:class{constructor(){env.probes.push(this);}},WebSocket:class{constructor(){env.socket=this;}},setTimeout:f=>env.timeouts.push(f),clearTimeout(){},setInterval:(f,ms)=>env.intervals.set(ms,f),requestAnimationFrame(){},fetch});
 vm.runInContext(readFileSync(new URL('../Resources/Overlays/overlay.js',import.meta.url),'utf8'),context);
 return env;
}
async function overlay(orientation, slot) {
 const o = boot(orientation, slot, async u=>({ok:true,json:async()=>themes.get(u.split('/')[2])}));
 const {node, body, probes} = o;
 const state = snapshot(slot);
 async function send() { o.socket.onmessage({data:JSON.stringify(state)}); await tick(); }
 await send(); eq(node('bug').style.getPropertyValue('--bug-top'),topFor(orientation,slot));
 state.overlay.portraitTop=300; await send();
 eq(node('bug').style.getPropertyValue('--bug-top'),orientation==='v' ? (slot===2?'440px':'300px') : '80px');
 state.competitions[0].shortName='EDITED'; state.competitions[0].themeId='stealth'; state.competitions[0].logoFile='competition-ligue1.png'; await send();
 eq(node('.comp .label').textContent,'EDITED'); eq(body.dataset.theme,'stealth'); eq(node('bug').style.getPropertyValue('--comp-logo'),'url(/crests/competition-ligue1.png)');
 // A manual theme override still wins when competition design changes; a match revision leaves the logo URL alone.
 state.matches[0].themeId='ligue1'; state.matches[0].revision++; await send();
 eq(node('bug').style.getPropertyValue('--comp-logo'),'url(/crests/competition-ligue1.png)');
 // Replacing the logo under the same name bumps only its own version, which reaches the URL without a match revision.
 state.competitions[0].logoVersion=1; await send();
 eq(node('bug').style.getPropertyValue('--comp-logo'),'url(/crests/competition-ligue1.png?v=1)');
 // Crests: goals and live polls keep the URL and start no new probe; a same-name replacement loads once.
 const crest = node('.team.home .crest');
 state.matches[0].home = {...team, crestFile:'club.png'}; state.matches[0].revision++; await send();
 eq(crest.style.backgroundImage,'url(/crests/club.png)'); eq(node('bug').style.getPropertyValue('--home-crest'),'url(/crests/club.png)');
 const probesBefore = probes.length;
 state.matches[0].homeScore++; state.matches[0].revision++; await send(); state.matches[0].revision++; await send();
 eq(probes.length,probesBefore); eq(node('bug').style.getPropertyValue('--home-crest'),'url(/crests/club.png)');
 const stale = probes.at(-1);
 state.matches[0].home = {...team, crestFile:'club.png', crestVersion:2}; state.matches[0].revision++; await send();
 eq(probes.length,probesBefore+1); eq(crest.style.backgroundImage,'url(/crests/club.png?v=2)'); eq(node('bug').style.getPropertyValue('--home-crest'),'url(/crests/club.png?v=2)');
 // A late failure of the replaced image must not paint the monogram over the new crest; the new one's failure does.
 stale.onerror(); eq(crest.style.backgroundImage,'url(/crests/club.png?v=2)'); eq(crest.classList.contains('monogram'),false);
 probes.at(-1).onerror(); eq(crest.classList.contains('monogram'),true);
 state.matches[0].home = {...team, crestFile:'club.png', crestVersion:3}; state.matches[0].revision++; await send();
 eq(crest.style.backgroundImage,'url(/crests/club.png?v=3)'); eq(crest.classList.contains('monogram'),false);
 state.competitions[0].shortName='SECOND'; state.competitions[0].themeId='stealth'; await send();
 eq(body.dataset.theme,'ligue1'); eq(node('.comp .label').textContent,'SECOND');
 // An old app's snapshot has no override flag and must not start a reload loop.
 delete state.overlay.themeOverrides; await send(); eq(o.reloads,0);
 state.overlay.themeOverrides=false; await send(); eq(o.reloads,1);
}
// Theme recovery: the server answers each fetch only when the check says so, as a rejection, a 404 or a theme.
async function recovery(orientation, slot) {
 const pending = [];
 const o = boot(orientation, slot, u=>new Promise((resolve,reject)=>pending.push({u,resolve,reject})));
 const {node, body, cssLoads} = o, css = node('theme-css'), bug = node('bug');
 const state = snapshot(slot);
 const themeFetches = () => pending.filter(p=>p.u.startsWith('/themes/'));
 async function answer(u, outcome) {
  const p = pending.splice(pending.findIndex(x=>x.u===u),1)[0];
  if (outcome==='reject') p.reject(new TypeError('Load failed'));
  else if (outcome===404) p.resolve({ok:false,status:404,json:async()=>{ throw new SyntaxError('not JSON'); }});
  else p.resolve({ok:true,json:async()=>outcome});
  await tick(); await tick();
 }
 async function send() { o.socket.onmessage({data:JSON.stringify(state)}); await tick(); }
 async function poll() { o.intervals.get(30000)(); await answer('/api/state',JSON.parse(JSON.stringify(state))); }
 async function reconnect() { o.socket.onclose(); o.timeouts.at(-1)(); await send(); }
 // Server down while the page starts: theme.json rejects and theme.css errors, so no geometry is applied.
 await send(); eq(themeFetches().length,1); eq(cssLoads.length,1);
 await answer('/themes/ligue1/theme.json','reject'); css.onerror();
 eq(bug.style.getPropertyValue('--bug-top'),undefined);
 // Ordinary broadcasts never retry, so a persistently failing theme cannot loop per command.
 await send(); await send(); eq(themeFetches().length,0); eq(cssLoads.length,1);
 // The 30 s poll retries both with the same revision; a 404 is a failure too, and nothing fetches twice.
 await poll(); eq(themeFetches().length,1); eq(cssLoads.length,2);
 await send(); await poll(); eq(themeFetches().length,1); eq(cssLoads.length,2);
 await answer('/themes/ligue1/theme.json',404); css.onerror();
 eq(bug.style.getPropertyValue('--bug-top'),undefined); eq(body.dataset.family,'');
 // The first snapshot after a socket reconnect retries; later messages on that socket do not.
 await reconnect(); eq(themeFetches().length,1); eq(cssLoads.length,3);
 await send(); eq(themeFetches().length,1); eq(cssLoads.length,3);
 // Recovery paints the unchanged revision, and a recovered theme is never reloaded again.
 await answer('/themes/ligue1/theme.json',{...themes.get('ligue1'),family:'ligue1'}); css.onload();
 eq(bug.style.getPropertyValue('--bug-top'),topFor(orientation,slot)); eq(body.dataset.family,'ligue1'); eq(state.matches[0].revision,1);
 await poll(); await reconnect(); eq(themeFetches().length,0); eq(cssLoads.length,3);
 // A-B-A: stealth, ligue1, stealth. Late answers for the earlier stealth and ligue1 must not replace the current stealth.
 for (const id of ['stealth','ligue1','stealth']) { state.competitions[0].themeId=id; await send(); }
 eq(body.dataset.theme,'stealth'); eq(themeFetches().length,3);
 const late = {...themes.get('ligue1'),family:'stale',geometry:{v:{top:1,scale:9},h:{top:1,scale:9}}};
 await answer('/themes/stealth/theme.json',late);
 eq(body.dataset.family,'ligue1'); eq(bug.style.getPropertyValue('--bug-scale'),orientation==='v' ? '2' : '1');
 await answer('/themes/stealth/theme.json',{...themes.get('stealth'),family:'stealth'});
 eq(body.dataset.family,'stealth'); eq(bug.style.getPropertyValue('--bug-scale'),orientation==='v' ? '1.56' : '1');
 await answer('/themes/ligue1/theme.json','reject'); eq(body.dataset.family,'stealth');
 css.onload(); await poll(); eq(themeFetches().length,0); eq(cssLoads.length,6);
}
for (const [orientation,slot] of [['v',1],['v',2],['h',1]]) await overlay(orientation,slot);
for (const [orientation,slot] of [['v',1],['v',2],['h',1]]) await recovery(orientation,slot);
console.log(`${checks} overlay checks passed`);
