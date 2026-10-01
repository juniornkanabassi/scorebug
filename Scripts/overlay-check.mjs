// Execute the production overlay script with a minimal DOM; no browser, app or network is launched.
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
let checks = 0;
const eq = (actual, expected) => { assert.equal(actual, expected); checks++; };
async function overlay(orientation, slot) {
 const nodes = new Map();
 function node(id) {
  if (nodes.has(id)) return nodes.get(id);
  const classes = new Set(), styles = new Map();
  const n = {dataset:{},textContent:'',style:{setProperty:(k,v)=>styles.set(k,v),getPropertyValue:k=>styles.get(k)},classList:{add:(...xs)=>xs.forEach(x=>classes.add(x)),remove:(...xs)=>xs.forEach(x=>classes.delete(x)),contains:x=>classes.has(x),toggle:(x,v)=>v?classes.add(x):classes.delete(x)},append(){},appendChild(){},before(){},querySelector:s=>node(s),offsetWidth:100};
  nodes.set(id,n); return n;
 }
 const body = node('body'); body.dataset = {orientation,slot:String(slot)};
 const themes = new Map([['ligue1',{id:'ligue1',clockStyle:'runOn',geometry:{v:{top:260,top2:400,scale:2},h:{top:80,scale:1}}}],['stealth',{id:'stealth',clockStyle:'runOn',geometry:{v:{top:260,top2:400,scale:1.56},h:{top:80,scale:1}}}]]);
 let socket, reloads = 0;
 const context = vm.createContext({document:{body,getElementById:node,createElement:()=>node(Symbol()),getAnimations:()=>[]},location:{search:'',protocol:'http:',host:'127.0.0.1:8680',reload:()=>reloads++},URLSearchParams,Date,console,Image:class{},WebSocket:class{constructor(){socket=this;}},setTimeout:()=>1,clearTimeout(){},setInterval(){},requestAnimationFrame(){},fetch:async u=>({ok:true,json:async()=>themes.get(u.split('/')[2])})});
 vm.runInContext(readFileSync(new URL('../Resources/Overlays/overlay.js',import.meta.url),'utf8'),context);
 const team = {name:'Team',shortName:'Team',code:'TMP',primaryColour:'#000000',secondaryColour:'#ffffff',textColour:'#ffffff'};
 const state = {serverTime:Date.now(),overlay:{portraitTop:100,themeOverrides:true},competitions:[{id:'ligue1',shortName:'L1',themeId:'ligue1'}],matches:[{slot,competitionId:'ligue1',revision:1,home:team,away:team,clock:{running:false,periodBaseSeconds:0,accumulated:0},phase:'preMatch',homeScore:0,awayScore:0,visible:true,goals:[]}]};
 async function send() { socket.onmessage({data:JSON.stringify(state)}); await new Promise(r=>setImmediate(r)); }
 await send(); eq(node('bug').style.getPropertyValue('--bug-top'),orientation==='v' ? (slot===2?'240px':'100px') : '80px');
 state.overlay.portraitTop=300; await send();
 eq(node('bug').style.getPropertyValue('--bug-top'),orientation==='v' ? (slot===2?'440px':'300px') : '80px');
 state.competitions[0].shortName='EDITED'; state.competitions[0].themeId='stealth'; state.competitions[0].logoFile='competition-ligue1.png'; await send();
 eq(node('.comp .label').textContent,'EDITED'); eq(body.dataset.theme,'stealth'); eq(node('bug').style.getPropertyValue('--comp-logo'),'url(/crests/competition-ligue1.png?v=1)');
 // A manual theme override still wins when competition design changes.
 state.matches[0].themeId='ligue1'; state.matches[0].revision++; await send();
 eq(node('bug').style.getPropertyValue('--comp-logo'),'url(/crests/competition-ligue1.png?v=2)');
 state.competitions[0].shortName='SECOND'; state.competitions[0].themeId='stealth'; await send();
 eq(body.dataset.theme,'ligue1'); eq(node('.comp .label').textContent,'SECOND');
 // An old app's snapshot has no override flag and must not start a reload loop.
 delete state.overlay.themeOverrides; await send(); eq(reloads,0);
 state.overlay.themeOverrides=false; await send(); eq(reloads,1);
}
for (const [orientation,slot] of [['v',1],['v',2],['h',1]]) await overlay(orientation,slot);
console.log(`${checks} overlay checks passed`);
