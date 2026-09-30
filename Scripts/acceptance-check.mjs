#!/usr/bin/env node
// Focused cumulative API/overlay checks; hardware, installation and real-input lines stay pending.
import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';
import { openDriver, captureOne } from './capture.mjs';
const port=Number(process.env.SCOREBUG_PORT), data=process.env.SCOREBUG_DATA, out=process.env.SCOREBUG_EVIDENCE;
assert(Number.isInteger(port)&&port>=1024&&port<=65535&&port!==8600&&data&&out,'Set disposable SCOREBUG_PORT, SCOREBUG_DATA, SCOREBUG_EVIDENCE');
const base=`http://127.0.0.1:${port}`;let checks=0;
const check=(condition,label)=>{assert(condition,label);checks++;console.log('PASS '+label);};
async function get(path){const r=await fetch(base+path);assert(r.ok,`${path}: ${r.status}`);return r.json();}
async function send(command,params={},slot=1){const r=await fetch(`${base}/api/match/${slot}/command`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({command,...params})});assert(r.ok,await r.clone().text());return (await r.json()).matches.find(m=>m.slot===slot);}
await mkdir(out,{recursive:true});
await send('setAutoUpdateLiveData',{showScorers:false});await send('reset');
let m=await send('startPeriod',{period:'secondHalf'});check(m.clock.periodBaseSeconds===2700,'second half starts at 45:00');
m=await send('startPeriod',{period:'firstHalf'});check(m.clock.periodBaseSeconds===0,'can return to first half');
await send('setClock',{seconds:754});await send('pause');m=await get('/api/state');check(Math.floor(m.matches[0].clock.accumulated)>=754&&!m.matches[0].clock.running,'clock pause retains local elapsed');
await send('play');await send('playPause');m=await send('adjustClock',{deltaSeconds:-5});check(!m.clock.running&&m.clock.accumulated>=749,'manual clock nudge preserves pause');
await send('setAddedMinutes',{minutes:3});m=await send('adjustAddedMinutes',{delta:-1});check(m.addedMinutes===2,'added time adjusts');m=await send('setAddedMinutes',{minutes:null});check(m.addedMinutes===undefined||m.addedMinutes===null,'added time can hide');
m=await send('goal',{side:'home'});const goal=m.lastGoal.goalId;
await send('setScorer',{goalId:goal,scorer:'Test Player',ownGoal:true,penalty:true});m=await send('setGoalMinute',{goalId:goal,minute:45,plus:2});check(m.goals[0].minuteLabel==="45+2'"&&m.goals[0].ownGoal&&m.goals[0].penalty,'goals keep scorer flags and editable minute');
m=await send('setShowScorers',{showScorers:true});check(m.showScorers,'scorer strap is manual');m=await send('removeGoal',{goalId:goal});check(m.homeScore===0&&m.goals.length===0,'goal removal updates score');
await send('setCompetition',{competitionId:'champions-league'});await send('setAggregate',{home:2,away:1});m=await send('swapTeams');check(m.aggregate.firstLegHome===1&&m.aggregate.firstLegAway===2,'swapping teams swaps first leg');m=await send('reset');check(m.aggregate.firstLegHome===1,'reset retains aggregate');
await send('startPeriod',{period:'firstHalf'});m=await send('startShootout',{side:'home'});check(m.phase==='shootout'&&!m.clock.running,'shootout freezes clock');m=await send('goal',{side:'home'});check(m.homeScore===0,'shootout cannot change match score');
await send('recordKick',{side:'home',result:'scored'});await send('recordKick',{side:'away',result:'missed'});m=await send('setKick',{side:'home',index:0,result:'missed'});check(m.shootout.kicks.every(k=>k.result==='missed'),'kick editing changes tally');m=await send('removeKick',{side:'away',index:0});check(m.shootout.kicks.length===1,'kick removal');m=await send('undoKick');check(m.shootout.kicks.length===0,'undo kick');
m=await send('setCompetition',{competitionId:'ligue1'});check(!m.aggregate,'league clears aggregate');
check((await fetch(base+'/api/test/key',{method:'POST',headers:{'content-type':'application/json'},body:'{}'})).status===404,'test key route absent in production');
// Connect after prior commands: initial WS snapshot must resynchronise.
const ws=new WebSocket(`ws://127.0.0.1:${port}/ws`);
const initial=await new Promise((resolve,reject)=>{ws.onmessage=e=>resolve(JSON.parse(e.data));ws.onerror=reject;});
check(initial.matches[0].competitionId==='ligue1','WebSocket resync on connect');
const broadcast=new Promise((resolve,reject)=>{ws.onmessage=async e=>{try{const state=JSON.parse(e.data);const saved=JSON.parse(await readFile(data+'/state.json','utf8'));assert.equal(saved.matches[0].revision,state.matches[0].revision);resolve();}catch(e){reject(e);}};});
await send('setVisible',{visible:false});await broadcast;check(true,'state is saved before broadcast');ws.close();
await send('reset');await send('setVisible',{visible:true});
const themes=await get('/api/themes');
for(const orientation of ['h','v']) {
 const driver=await openDriver({width:orientation==='h'?1920:1080,height:orientation==='h'?1080:1920,scale:1});
 try {
  for(const theme of themes){
   await send('setTheme',{themeId:theme.id});
   await captureOne(driver,{port,orientation,slot:'1',demo:'show:900',outPath:`${out}/${theme.id}-${orientation}.png`,full:false});
   const dims=await driver.evaluate(()=>{const b=document.getElementById('bug');const r=b.getBoundingClientRect();return {width:r.width,theme:document.body.dataset.theme,phase:b.dataset.phase};});
   check(!!dims.phase&&dims.width>0&&(orientation!=='v'||dims.width<800),`${theme.id} ${orientation} paints within bounds`);
  }
 }finally{await driver.close();}
}
await send('setCompetition',{competitionId:'nations-league'});await send('setTheme',{themeId:'nations-league'});
await send('setTeam',{side:'home',team:{name:'England',shortName:'England',code:'ENG',primaryColour:'#FFFFFF',secondaryColour:'#FFFFFF',textColour:'#000000'}});
const driver=await openDriver({width:1920,height:1080,scale:1});
try{
 await captureOne(driver,{port,orientation:'h',slot:'1',demo:'goal:home:500',outPath:out+'/unl-white-goal.png',full:false});
 await driver.goto(`${base}/overlay/h/1`);
 await driver.waitForFunction(()=>!!document.getElementById('bug')?.dataset.phase,{timeout:10000});
 await send('goal',{side:'home'});
 await driver.waitForFunction(()=>document.getElementById('bug').classList.contains('goal-home'),{timeout:3000});
 await driver.waitForFunction(()=>!document.getElementById('bug').classList.contains('goal-home'),{timeout:7000});check(true,'real goal animation clears after display');
}finally{await driver.close();}
await send('setTheme',{themeId:''});await send('reset');
console.log(`${checks} cumulative runtime checks passed`);
