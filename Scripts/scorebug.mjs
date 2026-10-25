#!/usr/bin/env node
// Supported CLI over the app's existing main-actor HTTP actions. Node built-ins only.
import { parseArgs } from 'node:util';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { pickClub, pickCompetition, teamEntry } from './match-lib.mjs';
const exec = promisify(execFile);
const str = (description, extra={}) => ({type:'string',description,...extra});
const num = (description, extra={}) => ({type:'integer',description,...extra});
const bool = description => ({type:'boolean',description});
const side = str('Scoring side',{enum:['home','away']});
const requestId = str('Retry id, at most 121 characters',{minLength:1,maxLength:121});
export const commands = [
 ['status','Report app version and both matches without launching.',{},[], 'scorebug status --json',false],
 ['match set','Resolve clubs and set up a match; resets score unless --keep-score.',{home:str('Home club name'),away:str('Away club name'),competition:str('Competition name or id'),firstLeg:str('First-leg score H-A'),keepScore:bool('Keep score and phase'),force:bool('Accept weak club matches or replace a live match'),dryRun:bool('Resolve without changing anything')},[], 'scorebug match set --home "Real Madrid" --away Inter --competition ucl',true],
 ['show','Put this slot on air.',{},[], 'scorebug show',true],
 ['hide','Take this slot off air.',{},[], 'scorebug hide',true],
 ['reset','Reset the match, retaining teams, competition and first leg.',{yes:bool('Required confirmation')},['yes'],'scorebug reset --yes',true],
 ['goal add','Add one goal, then attach its scorer and minute.',{side,minute:num('Goal minute',{minimum:1,maximum:130}),plus:num('Added minutes',{minimum:0,maximum:30}),scorer:str('Scorer name'),ownGoal:bool('Own goal'),penalty:bool('Penalty'),requestId},['side'],'scorebug goal add --side home --minute 23 --scorer "Test" --request-id g1',true],
 ['goal remove','Remove a goal by id or the latest on a side.',{goalId:str('Goal UUID'),side},[],'scorebug goal remove --side home',true],
 ['clock start','Start a period or resume the current live period.',{period:str('Period to start',{enum:['firstHalf','secondHalf','extraFirst','extraSecond']})},[],'scorebug clock start --period firstHalf',true],
 ['clock stop','Pause the master clock.',{},[],'scorebug clock stop',true],
 ['clock adjust','Adjust the master clock by seconds or to cumulative mm:ss.',{by:num('Signed seconds',{minimum:-10000,maximum:10000}),to:str('Cumulative mm:ss')},[],'scorebug clock adjust --by -5',true],
 ['fixture list','List fixtures for a date and optional competition.',{date:str('today or YYYY-MM-DD'),competition:str('Competition name or id')},[],'scorebug fixture list --date today --competition ucl',false],
 ['fixture load','Load a numbered fixture; refuses a live slot unless --force.',{date:str('today or YYYY-MM-DD'),competition:str('Competition name or id'),pick:num('1-based fixture number',{minimum:1}),force:bool('Replace a live match')},['pick'],'scorebug fixture load --date today --competition ucl --pick 1',true],
 ['theme list','List available themes and each slot’s effective theme.',{},[],'scorebug theme list',false],
 ['theme set','Set a theme override; default uses the competition’s theme.',{id:str('Theme id or default')},['id'],'scorebug theme set --id nations-league',true],
 ['goal edit','Correct an existing goal’s scorer, minute, own goal or penalty flag.',{goalId:str('Goal UUID from status'),minute:num('Goal minute',{minimum:1,maximum:130}),plus:num('Added minutes',{minimum:0,maximum:30}),scorer:str('Scorer name; empty clears it'),ownGoal:bool('Mark as an own goal'),noOwnGoal:bool('Clear the own goal mark'),penalty:bool('Mark as a penalty'),noPenalty:bool('Clear the penalty mark'),requestId},['goalId'],'scorebug goal edit --goal-id <UUID> --minute 45 --plus 2 --scorer "Mbappé"',true],
 ['period end','End the live period: half time, full time or the extra-time breaks.',{requestId},[],'scorebug period end',true],
 ['added set','Show the added time board; 0 hides it. A new period clears it.',{minutes:num('Added minutes',{minimum:0,maximum:30}),requestId},['minutes'],'scorebug added set --minutes 4',true],
 ['added adjust','Raise or lower the added time board by whole minutes.',{by:num('Signed minutes',{minimum:-30,maximum:30}),requestId},['by'],'scorebug added adjust --by 1',true],
 ['teams swap','Swap home and away, with their scores, goals, shootout kicks and first leg.',{requestId},[],'scorebug teams swap',true],
 ['scorers show','Show goal scorers under the score bug.',{requestId},[],'scorebug scorers show',true],
 ['scorers hide','Hide goal scorers under the score bug.',{requestId},[],'scorebug scorers hide',true],
 ['aggregate set','Set the first-leg score so the overlay shows the aggregate.',{firstLeg:str('First-leg score H-A, from this match’s home side'),requestId},['firstLeg'],'scorebug aggregate set --first-leg 2-1',true],
 ['aggregate clear','Remove the first-leg score and aggregate.',{requestId},[],'scorebug aggregate clear',true],
 ['shootout start','Freeze the clock and start a penalty shootout.',{first:str('Side taking the first kick (default home)',{enum:['home','away']}),requestId},[],'scorebug shootout start --first away',true],
 ['shootout kick','Record the next kick; the side defaults to whoever is due.',{result:str('Kick result',{enum:['scored','missed']}),side:str('Kicking side',{enum:['home','away']}),requestId},['result'],'scorebug shootout kick --result scored',true],
 ['shootout undo','Remove the last recorded kick.',{requestId},[],'scorebug shootout undo',true],
 ['shootout edit','Change one side’s numbered kick to scored or missed.',{side:str('Kicking side',{enum:['home','away']}),kick:num('That side’s kick number, from 1',{minimum:1,maximum:50}),result:str('Kick result',{enum:['scored','missed']}),requestId},['side','kick','result'],'scorebug shootout edit --side home --kick 2 --result missed',true],
 ['shootout remove','Delete one side’s numbered kick.',{side:str('Kicking side',{enum:['home','away']}),kick:num('That side’s kick number, from 1',{minimum:1,maximum:50}),requestId},['side','kick'],'scorebug shootout remove --side away --kick 3',true],
 ['live link','Link the slot to an ESPN event for live goals and scorers.',{eventId:str('ESPN event id, 1 to 12 digits'),league:str('ESPN league slug, for example uefa.champions'),requestId},['eventId','league'],'scorebug live link --event-id 704512 --league uefa.champions',true],
 ['live unlink','Stop following the linked ESPN event.',{requestId},[],'scorebug live unlink',true],
 ['live auto','Turn automatic goal and scorer updates from the linked event on or off.',{state:str('on or off',{enum:['on','off']}),requestId},['state'],'scorebug live auto --state on',true],
 ['live delay','Delay live updates to match your stream delay.',{minutes:num('Delay in minutes',{minimum:0,maximum:10}),requestId},['minutes'],'scorebug live delay --minutes 1',true],
].map(([command,description,properties,required,example,slot])=>({command,name:command.replaceAll(' ','_'),description,properties,required,example,slot}));
const flag = key => key.replace(/[A-Z]/g,c=>'-'+c.toLowerCase());
export function manifest() {
 let version='dev';
 for(const path of ['../../Info.plist','../Resources/Info.plist']) {
  try {version=readFileSync(new URL(path,import.meta.url),'utf8').match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1]??'dev';if(version!=='dev')break;}catch{}
 }
 return {name:'scorebug',version,tools:commands.map(c=>({name:c.name,description:c.description,inputSchema:{type:'object',properties:{...c.properties,...(c.slot?{slot:num('Match slot',{enum:[1,2]})}:{}),show:bool('Show the installed app window after success (takes focus)')},required:c.required,additionalProperties:false}}))};
}
class Failure extends Error {constructor(code,message,exit=1){super(message);this.code=code;this.exit=exit;}}
const usage = message => {throw new Failure('usage',message,2);};
function help(command) {
 const selected=command?[command]:commands;
 return ['scorebug — control Scorebug over localhost HTTP',...selected.flatMap(c=>[`${c.command}: ${c.description}`,...Object.entries(c.properties).map(([k,v])=>`  --${flag(k)}${v.type==='boolean'?'':` <${v.enum?.join('|')??v.type}>`}  ${v.description}${c.required.includes(k)?' (required)':''}`),`Example: ${c.example}`]),'mcp-manifest: print the command schemas (Example: scorebug mcp-manifest)','Global flags: --port <1024..65535> ($SCOREBUG_PORT or 8600), --slot <1|2> (1), --json, --show, --no-launch, --help/-h','Exit codes: 0 success, 1 action error, 2 usage. --show takes focus on port 8600 only.'].join('\n');
}
function summary(state,slot) {
 const matches=state.matches.filter(m=>!slot||m.slot===slot).map(m=>{
  const seconds=Math.max(0,Math.floor(m.clock.periodBaseSeconds+m.clock.accumulated+(m.clock.running?Math.max(0,(state.serverTime-m.clock.periodStart)/1000):0)));
  const kicks=m.shootout?.kicks??[],taken=side=>kicks.filter(k=>k.side===side&&k.result==='scored').length;
  return {slot:m.slot,home:{id:m.home.clubId,name:m.home.name,code:m.home.code},away:{id:m.away.clubId,name:m.away.name,code:m.away.code},score:[m.homeScore,m.awayScore],phase:m.phase,clock:`${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`,addedMinutes:m.addedMinutes??null,visible:m.visible,showScorers:m.showScorers??null,competitionId:m.competitionId,
   firstLeg:m.aggregate?[m.aggregate.firstLegHome,m.aggregate.firstLegAway]:null,
   shootout:m.shootout?{first:m.shootout.firstKicker,score:[taken('home'),taken('away')],kicks:kicks.map(k=>({side:k.side,result:k.result}))}:null,
   live:m.espnEventId?{eventId:m.espnEventId,league:m.espnLeague??null,auto:m.autoUpdateLiveData??null,delayMinutes:m.liveDataDelayMinutes??null,notice:m.liveDataNotice??null}:null,
   goals:m.goals.map(g=>({id:g.id,side:g.side,minute:g.minuteLabel,scorer:g.scorer,ownGoal:g.ownGoal,penalty:g.penalty}))};
 });
 return slot?matches[0]:matches;
}
// The installed production copy (install.sh's folder, then a DMG install), never a pre-rename copy left behind; a
// disposable copy shares the bundle id, so the id is the last resort.
const BUNDLE_ID='com.juniornkanabassi.Scorebug';
const isRenamed=app=>{try{return readFileSync(`${app}/Contents/Info.plist`,'utf8').includes(`<string>${BUNDLE_ID}</string>`);}catch{return false;}};
const installedApp=()=>{const app=['/Applications/JuniorOS Apps/Scorebug.app','/Applications/Scorebug.app'].find(isRenamed);return app?['-a',app]:['-b',BUNDLE_ID];};
export async function main(args=process.argv.slice(2)) {
 let json=args.includes('--json');
 try {
  const options={port:{type:'string'},slot:{type:'string'},json:{type:'boolean'},show:{type:'boolean'},'no-launch':{type:'boolean'},help:{type:'boolean',short:'h'}};
  for(const c of commands) for(const [key,p] of Object.entries(c.properties))options[flag(key)]={type:p.type==='boolean'?'boolean':'string'};
  // parseArgs treats a signed value as a flag unless supplied with '='.
  args=args.flatMap((v,i)=>/^-[0-9]+$/.test(args[i+1]??'')&&v.startsWith('--')?[`${v}=${args[i+1]}`]:/^-[0-9]+$/.test(v)&&args[i-1]?.startsWith('--')?[]:[v]);
  let parsed;try {parsed=parseArgs({args,options,allowPositionals:true});}catch(e){usage(e.message);}
  const {values,positionals}=parsed;json=!!values.json;
  const name=positionals.join(' '), command=commands.find(c=>c.command===name);
  if(values.help) {if(name && !command && name!=='mcp-manifest')usage('Unknown command '+name);console.log(help(command));return 0;}
  if(name==='mcp-manifest'){console.log(JSON.stringify(manifest()));return 0;}
  if(!command)usage('Choose a command; see scorebug --help');
  const allowed=new Set([...Object.keys(command.properties).map(flag),'port','json','show','no-launch','help',...(command.slot?['slot']:[])]);
  for(const k of Object.keys(values))if(!allowed.has(k))usage(`--${k} is not supported for ${name}`);
  const port=Number(values.port??process.env.SCOREBUG_PORT??8600),slot=Number(values.slot??1);
  if(!Number.isInteger(port)||port<1024||port>65535)usage('--port must be 1024..65535');
  if(![1,2].includes(slot))usage('--slot must be 1 or 2');
  if(values.show&&port!==8600)usage('--show targets the installed app on port 8600 only');
  for(const [key,schema] of Object.entries(command.properties)) {
   const k=flag(key),v=values[k];
   if(command.required.includes(key)&&(v===undefined||v===false||v===''))usage(`--${k} is required`);
   if(v===undefined)continue;
   if(schema.enum&&!schema.enum.includes(v))usage(`--${k} must be ${schema.enum.join('|')}`);
   if(schema.type==='integer'){const n=Number(v);if(v.trim()===''||!Number.isSafeInteger(n)||n<(schema.minimum??-Infinity)||n>(schema.maximum??Infinity))usage(`Invalid --${k}`);values[k]=n;}
   if(schema.type==='string'&&(v.length<(schema.minLength??0)||v.length>(schema.maxLength??Infinity)))usage(`Invalid --${k}`);
  }
  if(name==='match set') {
   if(!!values.home!==!!values.away)usage('--home and --away are required together');
   if(!values.home&&!values.competition)usage('Provide teams or --competition');
   if(values['first-leg']&&!/^\d{1,2}[-:]\d{1,2}$/.test(values['first-leg']))usage('--first-leg wants H-A (0..99)');
   if(!values.home&&(values['first-leg']||values['keep-score']))usage('First leg and keep score need teams');
  }
  if(name==='goal remove'&&((values.side!==undefined)===(values['goal-id']!==undefined)))usage('Choose exactly one of --goal-id or --side');
  if(name==='clock adjust'&&((values.by!==undefined)===(values.to!==undefined)))usage('Choose exactly one of --by or --to');
  if(values.to&&!/^\d{1,3}:[0-5]\d$/.test(values.to))usage('--to wants mm:ss');
  if(values.plus!==undefined&&values.minute===undefined)usage('--plus requires --minute');
  if(name==='aggregate set'&&!/^\d{1,2}[-:]\d{1,2}$/.test(values['first-leg']))usage('--first-leg wants H-A (0..99)');
  if(name==='live link'&&(!/^[0-9]{1,12}$/.test(values['event-id'])||!/^[a-z0-9._-]{1,40}$/.test(values.league)))usage('--event-id wants 1 to 12 digits and --league 1 to 40 lower-case letters, digits, dots, underscores or hyphens');
  if(name==='goal edit') {
   if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(values['goal-id']))usage('--goal-id wants a goal UUID from status');
   if(values['own-goal']&&values['no-own-goal']||values.penalty&&values['no-penalty'])usage('Choose one of each flag pair');
   if(values.minute===undefined&&values.scorer===undefined&&!['own-goal','no-own-goal','penalty','no-penalty'].some(k=>values[k]))usage('Give at least one change: --minute, --scorer or a flag');
  }
  const base=`http://127.0.0.1:${port}`;
  let launched=false;
  async function api(path,body) {
   let r;
   try {r=await fetch(base+path,{...(body?{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(path.startsWith('/api/fixtures')||path.endsWith('/loadFixture')?120000:3000)});}
   catch(e) {
    if(e.name==='TimeoutError'||e.name==='AbortError')throw new Failure('timeout','Request timed out; it was not retried');
    if(e.cause?.code==='ECONNREFUSED') {
     if(name!=='status'&&port===8600&&!values['no-launch']&&!launched){
      launched=true;await exec('/usr/bin/open',['-g',...installedApp(),'--args','--background']);
      const deadline=Date.now()+10000;
      while(Date.now()<deadline){try {await api('/api/state');return await api(path,body);}catch(error){if(error.code!=='not_running')throw error;}await sleep(250);}
      throw new Failure('timeout','Scorebug did not start within 10 seconds');
     }
     throw new Failure('not_running',`Scorebug is not answering on port ${port}`);
    }
    throw new Failure('not_running','Connection failed; an ambiguous command was not retried');
   }
   if(!r.ok)throw new Failure(({400:'bad_request',403:'forbidden',415:'unsupported_media_type',409:path.endsWith('/command')?'not_applied':'match_live',502:'fixture_service_failed'})[r.status]??`http_${r.status}`,await r.text());
   if(r.headers.get('x-scorebug-save-failed')==='true')throw new Failure('save_failed','Change was applied but could not be saved; check Scorebug before retrying');
   return r.json();
  }
  const send=(action,params={})=>api(`/api/match/${slot}/command`,{command:action,...(values['request-id']?{requestId:values['request-id']}:{}),...params});
  let result;
  if(name==='status') {
   try {const state=await api('/api/state');let status;try{status=await api('/api/status');}catch(e){if(e.code!=='http_404')throw e;status={version:'unknown',port};}result={running:true,...status,matches:summary(state)};}
   catch(e){if(e.code!=='not_running')throw e;result={running:false,port};}
  } else if(name==='match set') {
   const library=await api('/api/library');const comp=pickCompetition(library.competitions,values.competition);
   if(values.competition&&!comp)throw new Failure('no_competition',`No competition matching ${values.competition}`);
   const current=(await api('/api/state')).matches.find(m=>m.slot===slot);
   const compId=comp?.id??current.competitionId;
   const picks={};for(const side of ['home','away'])if(values[side]){
    const pick=pickClub(library.clubs,values[side],compId);
    if(!pick.best)throw new Failure('no_club',`No club matching ${values[side]}`);
    if(pick.top<60&&!values.force)throw new Failure('weak_match',`Weak match for ${values[side]}: ${pick.best.name}; use --force after checking`);
    picks[side]=pick.best;
   }
   if(values['dry-run'])result={dryRun:true,competitionId:compId,...Object.fromEntries(Object.entries(picks).map(([side,c])=>[side,{id:c.id,name:c.name,code:teamEntry(c,compId).code}]))};
   else {
    if(values.home&&current.phase!=='preMatch'&&!values.force)throw new Failure('match_live','Match is live; use --force to replace it');
    if(comp)await send('setCompetition',{competitionId:comp.id});
    for(const side of ['home','away'])if(picks[side])await send('setTeam',{side,team:teamEntry(picks[side],compId)});
    if(values.home&&!values['keep-score'])await send('reset');
    if(values.home){if(values['first-leg']){const [home,away]=values['first-leg'].split(/[-:]/).map(Number);await send('setAggregate',{home,away});}else if(!values['keep-score'])await send('clearAggregate');}
    result=summary(await api('/api/state'),slot);
   }
  } else if(name==='goal add') {
   const before=(await api('/api/state')).matches.find(m=>m.slot===slot);
   if(before.phase==='shootout')throw new Failure('not_applied','Goals are ignored during a shootout');
   let state=await send('goal',{side:values.side,delta:1,...(values['request-id']?{requestId:values['request-id']}:{})});
   const id=state.matches.find(m=>m.slot===slot).lastGoal?.goalId;
   if(!id)throw new Failure('not_applied','No goal was added');
   if(values.scorer!==undefined||values['own-goal']||values.penalty)state=await send('setScorer',{goalId:id,scorer:values.scorer,ownGoal:values['own-goal'],penalty:values.penalty,...(values['request-id']?{requestId:values['request-id']+':scorer'}:{})});
   if(values.minute!==undefined)state=await send('setGoalMinute',{goalId:id,minute:values.minute,plus:values.plus,...(values['request-id']?{requestId:values['request-id']+':minute'}:{})});
   result=summary(state,slot);
  } else if(name==='goal remove')result=summary(await send(values['goal-id']?'removeGoal':'goal',values['goal-id']?{goalId:values['goal-id']}:{side:values.side,delta:-1}),slot);
  else if(name.startsWith('clock ')) {
   const m=(await api('/api/state')).matches.find(m=>m.slot===slot);
   const live=['firstHalf','secondHalf','extraFirst','extraSecond'].includes(m.phase);
   if(!values.period&&!live)throw new Failure('not_applied','No live period; use clock start --period');
   let action,params={};
   if(name==='clock start'){action=values.period?'startPeriod':'play';params={period:values.period};}
   else if(name==='clock stop')action='pause';
   else if(values.by!==undefined){action='adjustClock';params={delta:values.by};}
   else {const [mm,ss]=values.to.split(':').map(Number);const seconds=mm*60+ss-m.clock.periodBaseSeconds;if(seconds<0||seconds>10000)throw new Failure('not_applied','Requested clock time is outside this period');action='setClock';params={seconds};}
   result=summary(await send(action,params),slot);
  } else if(name.startsWith('fixture ')) {
   const now=new Date(),date=values.date&&values.date!=='today'?values.date:`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
   if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date+'T00:00:00Z').toISOString().slice(0,10)!==date)usage('--date wants today or a valid YYYY-MM-DD');
   const query=new URLSearchParams({date});
   if(values.competition){const library=await api('/api/library');const c=pickCompetition(library.competitions,values.competition);if(!c)throw new Failure('no_competition','Unknown competition');query.set('competition',c.id);}
   const fixtures=await api('/api/fixtures?'+query);
   if(name==='fixture list')result={date,fixtures:fixtures.map((f,i)=>({pick:i+1,home:f.home.name,away:f.away.name,kickoff:f.kickoff,competition:f.competitionCode}))};
   else {const chosen=fixtures[values.pick-1];if(!chosen)throw new Failure('no_such_fixture','No fixture at that number');result=summary(await api(`/api/match/${slot}/loadFixture`,{...chosen,force:!!values.force}),slot);}
  } else if(name==='theme list') {
   const themes=await api('/api/themes'),state=await api('/api/state');result={themes,matches:state.matches.map(m=>({slot:m.slot,themeId:m.themeId??state.competitions.find(c=>c.id===m.competitionId)?.themeId}))};
  } else if(name==='theme set')result=summary(await send('setTheme',{themeId:values.id==='default'?'':values.id}),slot);
  else if(name==='goal edit') {
   const m=(await api('/api/state')).matches.find(m=>m.slot===slot);
   const goalId=values['goal-id'],goal=m.goals.find(g=>g.id.toLowerCase()===goalId.toLowerCase()),retry=values['request-id'];let state;
   // Goal edits still read the scorer fallback; a retry always reaches the app.
   if(!goal&&!retry)throw new Failure('no_such_goal','No goal with that id in this slot; see scorebug status --json');
   if(values.scorer!==undefined||['own-goal','no-own-goal','penalty','no-penalty'].some(k=>values[k])) {
    const flag=(on,off)=>values[on]?true:values[off]?false:undefined;
    state=await send('setScorer',{strict:true,goalId,scorer:values.scorer??goal?.scorer??undefined,ownGoal:flag('own-goal','no-own-goal'),penalty:flag('penalty','no-penalty'),...(retry?{requestId:retry+':scorer'}:{})});
   }
   if(values.minute!==undefined)state=await send('setGoalMinute',{strict:true,goalId,minute:values.minute,plus:values.plus,...(retry?{requestId:retry+':minute'}:{})});
   result=summary(state,slot);
  } else if(['period end','shootout start','shootout kick','shootout undo','shootout edit','shootout remove'].includes(name)) {
   let state;
   if(!values['request-id']) {
    state=await api('/api/state');
    const m=state.matches.find(m=>m.slot===slot);
    if(name==='period end'&&!['firstHalf','secondHalf','extraFirst','extraSecond'].includes(m.phase))throw new Failure('not_applied','No live period to end');
    if(name==='shootout start'&&m.shootout)throw new Failure('not_applied','A shootout is already under way; use shootout undo/edit/remove');
    if(name==='shootout start'&&m.phase==='preMatch')throw new Failure('not_applied','A shootout needs the match to have kicked off');
    if(name!=='period end'&&name!=='shootout start'&&!m.shootout)throw new Failure('not_applied','No shootout in this slot; use shootout start');
    if(name==='shootout undo'&&!m.shootout.kicks.length)throw new Failure('not_applied','No kicks to undo');
    if((name==='shootout edit'||name==='shootout remove')&&m.shootout.kicks.filter(k=>k.side===values.side).length<values.kick)throw new Failure('not_applied',`The ${values.side} side has not taken kick ${values.kick}`);
   }
   const [action,params]={'period end':['endPeriod',{}],'shootout start':['startShootout',{side:values.first??'home'}],'shootout kick':['recordKick',{result:values.result,...(values.side?{side:values.side}:{})}],'shootout undo':['undoKick',{}],'shootout edit':['setKick',{side:values.side,index:values.kick-1,result:values.result}],'shootout remove':['removeKick',{side:values.side,index:values.kick-1}]}[name];
   state=await send(action,{...params,strict:true});
   result=summary(state,slot);
  } else if(name==='added set')result=summary(await send('setAddedMinutes',{minutes:values.minutes}),slot);
  else if(name==='added adjust')result=summary(await send('adjustAddedMinutes',{delta:values.by}),slot);
  else if(name==='teams swap')result=summary(await send('swapTeams'),slot);
  else if(name.startsWith('scorers '))result=summary(await send('setShowScorers',{showScorers:name==='scorers show'}),slot);
  else if(name==='aggregate set'){const [home,away]=values['first-leg'].split(/[-:]/).map(Number);result=summary(await send('setAggregate',{home,away}),slot);}
  else if(name==='aggregate clear')result=summary(await send('clearAggregate'),slot);
  else if(name==='live link')result=summary(await send('linkESPN',{eventId:values['event-id'],competitionId:values.league}),slot);
  else if(name==='live unlink')result=summary(await send('unlinkESPN'),slot);
  // The API carries the on/off value for setAutoUpdateLiveData in showScorers (CommandRequest has no other bool).
  else if(name==='live auto')result=summary(await send('setAutoUpdateLiveData',{showScorers:values.state==='on'}),slot);
  else if(name==='live delay')result=summary(await send('setLiveDataDelay',{minutes:values.minutes}),slot);
  else result=summary(await send(name==='reset'?'reset':'setVisible',name==='reset'?{}:{visible:name==='show'}),slot);
  if(values.show)await exec('/usr/bin/open',installedApp());
  const offline = result.running === false;
  const output = offline ? `Scorebug is not running on port ${result.port}`
   : name === 'status' ? result.matches.map(m=>`Slot ${m.slot}: ${m.home.name} ${m.score[0]}–${m.score[1]} ${m.away.name} · ${m.phase} ${m.clock}`).join('\n')
   : JSON.stringify(result);
  console.log(json ? JSON.stringify({ok:true,result}) : output);
  return 0;
 } catch(e) {
  const error=e instanceof Failure?e:new Failure('usage',e.message,2);
  const output={ok:false,error:{code:error.code,message:error.message}};
  (json?console.log:console.error)(json?JSON.stringify(output):`${error.code}: ${error.message}`);return error.exit;
 }
}
if(import.meta.main)process.exitCode=await main();
