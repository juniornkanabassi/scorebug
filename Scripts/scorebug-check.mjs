#!/usr/bin/env node
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const library = JSON.parse(readFileSync(new URL('../Resources/seed-library.json', import.meta.url)));
let posts = [], fail = false, ignore = false;
const match = {slot:1, home:{name:'Home',code:'HOM'},away:{name:'Away',code:'AWY'},homeScore:0,awayScore:0,phase:'preMatch',clock:{periodBaseSeconds:0,accumulated:0,running:false},visible:true,goals:[],competitionId:'champions-league'};
const state = {matches:[match,{...match,slot:2}],serverTime:Date.now(),competitions:library.competitions};
const fixture = {home:{name:'Real Madrid',shortName:'Real',code:'RMA'},away:{name:'Inter',shortName:'Inter',code:'INT'},kickoff:'2026-09-30T19:00:00Z',competitionCode:'uefa.champions'};
const responses = new Map();
const server = http.createServer(async(req,res)=>{
 let body=''; for await(const b of req) body+=b;
 res.setHeader('content-type','application/json');
 if(req.method==='POST') {
  const p=JSON.parse(body); posts.push(p);
  if(fail) {res.writeHead(400);res.end('fake refusal');return;}
  const key=p.requestId&&`${req.url}|${p.requestId}`;
  if(key&&responses.has(key)){res.end(responses.get(key));return;}
  const before=JSON.stringify(match);
  if(p.strict&&p.command==='startShootout'&&match.shootout){res.writeHead(409);res.end('A shootout is already under way; use shootout undo/edit/remove');return;}
  if(!ignore) {
   if(p.command==='endPeriod')match.phase={firstHalf:'halfTime',secondHalf:'fullTime',extraFirst:'extraHalfTime',extraSecond:'fullTime'}[match.phase]??match.phase;
   if(p.command==='startPeriod'){match.phase=p.period;match.clock.running=true;}
   const goal=match.goals?.find(g=>g.id===p.goalId);if(goal&&p.command==='setScorer')goal.scorer=p.scorer;if(goal&&p.command==='setGoalMinute')goal.minuteLabel=`${p.minute}'`;
   if(p.command==='pause')match.clock.running=false;
   if(p.command==='setAggregate')match.aggregate={firstLegHome:p.home,firstLegAway:p.away};
   if(p.command==='clearAggregate')delete match.aggregate;
   if(p.command==='goal') {match.homeScore++;match.lastGoal={goalId:'00000000-0000-0000-0000-000000000001'};}
   if(p.command==='startShootout'&&match.phase!=='preMatch')match.shootout={firstKicker:p.side,kicks:[]};
   if(p.command==='recordKick'&&match.shootout)match.shootout.kicks.push({side:p.side??'home',result:p.result});
   if(p.command==='undoKick'&&match.shootout)match.shootout.kicks.pop();
   if(p.command==='setKick')match.shootout.kicks.filter(k=>k.side===p.side)[p.index].result=p.result;
   if(p.command==='removeKick')match.shootout.kicks.splice(match.shootout.kicks.findIndex(k=>k===match.shootout.kicks.filter(k=>k.side===p.side)[p.index]),1);
  }
  if(p.strict&&JSON.stringify(match)===before){res.writeHead(409);res.end('The command did not change the match');return;}
  const response=JSON.stringify(state);
  if(key)responses.set(key,response);
  res.end(response); return;
 }
 const path=req.url.split('?')[0];
 const value={'/api/library':library,'/api/state':state,'/api/status':{version:'1.0.0',port:server.address().port},'/api/themes':[{id:'stealth',name:'Stealth',family:'stealth'}],'/api/fixtures':[fixture]}[path];
 if(value===undefined)res.writeHead(404);res.end(JSON.stringify(value??{}));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const port=server.address().port;
async function run(file,args,override=port){
 return await new Promise((resolve,reject)=>{const child=spawn(process.execPath,[file,...args],{env:{...process.env,SCOREBUG_PORT:String(override)}});let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);child.on('error',reject);child.on('exit',code=>resolve({code,stdout,stderr}));});
}
const referenceArgs=[['--home','Real Madrid','--away','Inter','--competition','ucl','--dry-run'],['--list','real']];
if(process.argv.includes('--save-reference')) {
 const reference=[];for(const args of referenceArgs) reference.push((await run('Scripts/setup-match.mjs',[...args,'--port',String(port)])).stdout);
 writeFileSync('/private/tmp/ship/setup-match-reference.json',JSON.stringify(reference));server.close();process.exit(0);
}
let checks=0;
function ok(value,label){assert(value,label);checks++;}
async function cli(args,expected=0,override=port){const r=await run('Scripts/scorebug.mjs',[...args,'--json'],override);assert.equal(r.code,expected,r.stderr+r.stdout);checks++;return JSON.parse(r.stdout);}
try {
 const manifest=await cli(['mcp-manifest']);ok(manifest.tools.length===32 && manifest.tools.every(t=>t.inputSchema.type==='object'),'manifest');
 for(const t of manifest.tools.slice(14))assert.deepEqual(t.inputSchema.properties.requestId,manifest.tools.find(t=>t.name==='goal_add').inputSchema.properties.requestId);checks++;
 for(const t of manifest.tools) {const r=await run('Scripts/scorebug.mjs',[...t.name.split('_'),'--help']);ok(r.code===0 && r.stdout.includes('Example:'),`help ${t.name}`);}
 await cli(['goal','add'],2);await cli(['reset'],2);
 posts=[];await cli(['goal','add','--side','home','--minute','23','--scorer','X','--own-goal','--request-id','r1']);
 assert.deepEqual(posts.map(p=>p.command),['goal','setScorer','setGoalMinute']);assert.equal(posts[0].requestId,'r1');assert.equal(posts[1].goalId,match.lastGoal.goalId);assert.equal(posts[1].requestId,'r1:scorer');assert.equal(posts[2].requestId,'r1:minute');checks++;
 posts=[];await cli(['match','set','--home','Real Madrid','--away','Inter','--competition','ucl']);
 assert.deepEqual(posts.map(p=>p.command),['setCompetition','setTeam','setTeam','reset','clearAggregate']);assert.equal(posts[0].competitionId,'champions-league');checks++;
 match.phase='secondHalf';match.aggregate={firstLegHome:2,firstLegAway:1};
 posts=[];await cli(['match','set','--home','Real Madrid','--away','Inter','--keep-score','--force']);
 assert.deepEqual(posts.map(p=>p.command),['setTeam','setTeam']);
 ok(match.aggregate.firstLegHome===2 && match.aggregate.firstLegAway===1,'keep-score retains a live aggregate');
 posts=[];await cli(['match','set','--home','Real Madrid','--away','Inter','--keep-score','--force','--first-leg','3-2']);
 assert.deepEqual(posts.map(p=>p.command),['setTeam','setTeam','setAggregate']);
 ok(match.aggregate.firstLegHome===3 && match.aggregate.firstLegAway===2,'explicit first leg replaces retained aggregate');
 match.phase='preMatch';
 posts=[];await cli(['match','set','--competition','ucl']);ok(posts.length===1,'competition alone');
 posts=[];await cli(['match','set','--home','Real Madrid','--away','Inter','--competition','ucl','--dry-run']);ok(posts.length===0,'dry-run');
 posts=[];await cli(['match','set','--home','Real Madrid','--away','Inter','--first-leg','junk'],2);ok(posts.length===0,'validate before mutations');
 for(const args of [['show'],['hide'],['reset','--yes'],['goal','remove','--side','home'],['clock','start','--period','firstHalf'],['clock','stop'],['clock','adjust','--by','-5'],['fixture','list','--date','today'],['fixture','load','--pick','1','--force'],['theme','list'],['theme','set','--id','default'],['status']])await cli(args);
 // The match controls beyond the original 14: each sends exactly the API command the window and Stream Deck use.
 const sent=async(args,expected)=>{posts=[];await cli(args);assert.deepEqual(posts.at(-1),expected,args.join(' '));checks++;};
 await sent(['added','set','--minutes','4'],{command:'setAddedMinutes',minutes:4});
 await sent(['added','adjust','--by','-1'],{command:'adjustAddedMinutes',delta:-1});
 await sent(['teams','swap'],{command:'swapTeams'});
 await sent(['scorers','hide'],{command:'setShowScorers',showScorers:false});
 await sent(['scorers','show'],{command:'setShowScorers',showScorers:true});
 await sent(['aggregate','set','--first-leg','2-1'],{command:'setAggregate',home:2,away:1});
 await sent(['aggregate','clear'],{command:'clearAggregate'});
 await sent(['live','link','--event-id','704512','--league','uefa.champions'],{command:'linkESPN',eventId:'704512',competitionId:'uefa.champions'});
 await sent(['live','unlink'],{command:'unlinkESPN'});
 await sent(['live','auto','--state','off'],{command:'setAutoUpdateLiveData',showScorers:false});
 await sent(['live','delay','--minutes','2'],{command:'setLiveDataDelay',minutes:2});
 match.goals=[{id:'00000000-0000-0000-0000-000000000001',side:'home',minuteLabel:"45+2'",scorer:'X'}];
 await sent(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000001','--minute','45','--plus','2'],{command:'setGoalMinute',goalId:'00000000-0000-0000-0000-000000000001',minute:45,plus:2});
 await sent(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000001','--no-own-goal'],{command:'setScorer',goalId:'00000000-0000-0000-0000-000000000001',scorer:'X',ownGoal:false});
 await sent(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000001','--minute','30'],{command:'setGoalMinute',goalId:'00000000-0000-0000-0000-000000000001',minute:30});
 ok((await cli(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000009','--minute','3'],1)).error.code==='no_such_goal','goal edit unknown id');
 match.goals=[{id:'00000000-0000-0000-0000-000000000001',side:'home',scorer:'X',minuteLabel:"23'"}];posts=[];
 await cli(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000001','--scorer','X','--minute','24','--request-id','same-scorer']);
 ok(posts.length===2&&posts.every(p=>!p.strict)&&match.goals[0].minuteLabel==="24'",'unchanged scorer does not block the minute edit');
 posts=[];const gone=await cli(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000009','--minute','3','--request-id','gone'],1);
 ok(gone.error.code==='not_applied'&&posts.length===1&&posts[0].strict===true&&posts[0].requestId==='gone:minute','goal edit with a retry id lets the app decide (strict)');
 await cli(['goal','edit','--goal-id','00000000-0000-0000-0000-000000000001'],2);
 await cli(['goal','edit','--goal-id','x','--minute','3'],2);
 await cli(['aggregate','set','--first-leg','x'],2);await cli(['live','link','--event-id','abc','--league','x'],2);
 await cli(['added','set','--minutes','31'],2);await cli(['live','auto','--state','maybe'],2);
 match.goals=[];
 ok((await cli(['shootout','kick','--result','scored'],1)).error.code==='not_applied','kick needs a shootout');
 match.phase='preMatch';ok((await cli(['period','end'],1)).error.code==='not_applied','period end needs a live period');
 ok((await cli(['shootout','start'],1)).error.code==='not_applied','shootout needs kick-off');
 match.phase='secondHalf';
 await sent(['period','end'],{strict:true,command:'endPeriod'});
 await sent(['shootout','start','--first','away'],{strict:true,command:'startShootout',side:'away'});
 await sent(['shootout','kick','--result','scored'],{strict:true,command:'recordKick',result:'scored'});
 await sent(['shootout','kick','--result','missed','--side','away'],{strict:true,command:'recordKick',result:'missed',side:'away'});
 posts=[];const already=await cli(['shootout','start'],1);
 ok(already.error.code==='not_applied'&&already.error.message==='A shootout is already under way; use shootout undo/edit/remove'&&posts.length===0&&match.shootout.kicks.length===2,'starting an existing shootout is refused without a POST');
 const shoot=await cli(['status']);ok(shoot.result.matches[0].shootout.score[0]===1&&shoot.result.matches[0].shootout.kicks.length===2,'status reports the shootout');
 await sent(['shootout','edit','--side','home','--kick','1','--result','missed'],{strict:true,command:'setKick',side:'home',index:0,result:'missed'});
 ok((await cli(['shootout','remove','--side','home','--kick','2'],1)).error.code==='not_applied','remove a kick not taken');
 await sent(['shootout','remove','--side','away','--kick','1'],{strict:true,command:'removeKick',side:'away',index:0});
 await sent(['shootout','kick','--result','scored','--side','home'],{strict:true,command:'recordKick',result:'scored',side:'home'});
 await sent(['shootout','undo'],{strict:true,command:'undoKick'});
 await sent(['shootout','undo'],{strict:true,command:'undoKick'});
 ok((await cli(['shootout','undo'],1)).error.code==='not_applied','undo with no kicks');
 // Strict refusals are not cached; successful request ids replay before preflight.
 const races=[['period','end'],['shootout','start'],['shootout','kick','--result','scored'],['shootout','undo'],['shootout','edit','--side','home','--kick','1','--result','missed'],['shootout','remove','--side','home','--kick','1']];
 const prepare=args=>{
  match.phase='secondHalf';
  match.shootout={firstKicker:'home',kicks:[{side:'home',result:'scored'},{side:'away',result:'missed'}]};
  if(args[1]==='start')delete match.shootout;
 };
 for(const [i,args] of races.entries()) {
  ignore=true;prepare(args);posts=[];
  ok((await cli(args,1)).error.code==='not_applied'&&posts.length===1,`ignored ${args.join(' ')} is not applied`);
  const id=`retry-${i}`;
  const refused=await cli([...args,'--request-id',id],1);
  ok(refused.error.code==='not_applied'&&refused.error.message==='The command did not change the match',`fresh id for ignored ${args.join(' ')} is refused`);
  ignore=false;prepare(args);
  const success=await cli([...args,'--request-id',id]);
  match.phase='preMatch';delete match.shootout;posts=[];
  const replay=await cli([...args,'--request-id',id]);
  ok(JSON.stringify(replay)===JSON.stringify(success)&&posts.length===1,`${args.join(' ')} replays despite changed state`);
 }
 prepare(['shootout','edit']);posts=[];
 await cli(['shootout','edit','--side','home','--kick','1','--result','scored']);
 ok(posts.length===0,'unchanged kick edit succeeds without a POST');
 prepare(['shootout','edit']);posts=[];
 await cli(['shootout','edit','--side','home','--kick','1','--result','scored','--request-id','same-kick']);
 ok(posts.length===0,'unchanged kick edit with a retry id succeeds without a POST');
 const retryCommands=[
  ['goal','edit','--goal-id','00000000-0000-0000-0000-000000000001','--scorer','Y','--minute','46'],
  ...races,
  ['added','set','--minutes','4'],['added','adjust','--by','1'],['teams','swap'],
  ['scorers','show'],['scorers','hide'],['aggregate','set','--first-leg','2-1'],['aggregate','clear'],
  ['live','link','--event-id','704512','--league','uefa.champions'],['live','unlink'],['live','auto','--state','on'],['live','delay','--minutes','1']
 ];
 match.goals=[{id:'00000000-0000-0000-0000-000000000001',side:'home',scorer:'X'}];
 for(const args of retryCommands) {
  responses.clear();prepare(args);posts=[];
  await cli([...args,'--request-id','r'.repeat(121)]);
  assert.deepEqual(posts.map(p=>p.requestId),args[0]==='goal'?['r'.repeat(121)+':scorer','r'.repeat(121)+':minute']:['r'.repeat(121)]);checks++;
  posts=[];await cli([...args,'--request-id','r'.repeat(122)],2);ok(posts.length===0,'overlong retry id rejected before POST');
 }
 ignore=false;
 delete match.shootout;match.phase='preMatch';match.clock.running=false;
 fail=true;const bad=await cli(['show'],1);ok(bad.error.code==='bad_request'&&bad.error.message==='fake refusal','400 error');fail=false;
 const reference=JSON.parse(readFileSync(new URL('./setup-match-reference.json',import.meta.url)));
 for(const [i,args] of referenceArgs.entries())assert.equal((await run('Scripts/setup-match.mjs',[...args,'--port',String(port)])).stdout,reference[i]);checks+=2;
 await new Promise(r=>server.close(r));
 const status=await cli(['status'],0,port);ok(status.ok===true && status.result.running===false,'offline JSON status');
 const plain=await run('Scripts/scorebug.mjs',['status'],port);
 ok(plain.code===0 && plain.stdout.includes('not running') && !plain.stderr,'offline human status');
 const offline=await cli(['show'],1,port);ok(offline.error.code==='not_running','spare port does not launch');
 console.log(`${checks} CLI checks passed`);
} finally {server.close();}
