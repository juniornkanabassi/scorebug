#!/usr/bin/env node
// All CLI commands against the signed app; only the fixture-provider response is canned.
import assert from 'node:assert/strict';
import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const exec=promisify(execFile),port=Number(process.env.SCOREBUG_PORT),cli=process.env.SCOREBUG_CLI;
assert(port>=1024&&port<=65535&&port!==8600&&cli,'Set a disposable port and bundled SCOREBUG_CLI');
let count=0;
async function run(args,expected=0,p=port){
 let stdout,code=0;try{({stdout}=await exec(process.execPath,[cli,...args,'--json'],{env:{...process.env,SCOREBUG_PORT:String(p)}}));}catch(e){stdout=e.stdout;code=e.code;}
 assert.equal(code,expected,stdout);count++;return JSON.parse(stdout);
}
await run(['status']);await run(['match','set','--home','Real Madrid','--away','Inter','--competition','ucl','--force']);
await run(['show']);await run(['hide']);await run(['reset','--yes']);await run(['goal','add','--side','home','--minute','23','--scorer','Test','--request-id','bundle-g1']);
await run(['goal','remove','--side','home']);await run(['clock','start','--period','firstHalf']);await run(['clock','stop']);await run(['clock','adjust','--by','-5']);
await run(['clock','adjust','--to','44:30']);await run(['theme','list']);await run(['theme','set','--id','nations-league']);
// Isolate network variability while exercising the bundled CLI and the built loadFixture handler.
const fixture={home:{name:'Disposable Home',shortName:'Home',code:'TMP',crestURL:'file:///private/tmp/scorebug-canary-do-not-read'},away:{name:'Disposable Away',shortName:'Away',code:'AWY'},kickoff:'2026-09-30T19:00:00Z',competitionCode:'uefa.champions'};
const proxy=http.createServer(async(req,res)=>{
 if(req.url.startsWith('/api/fixtures')){res.setHeader('content-type','application/json');res.end(JSON.stringify([fixture]));return;}
 let body='';for await(const chunk of req)body+=chunk;
 try{const r=await fetch(`http://127.0.0.1:${port}${req.url}`,{method:req.method,...(req.method==='POST'?{headers:{'content-type':'application/json'},body}:{})});res.writeHead(r.status,{'content-type':r.headers.get('content-type')??'application/json'});res.end(await r.text());}catch(e){res.writeHead(502);res.end(e.message);}
});
await new Promise(r=>proxy.listen(0,'127.0.0.1',r));
try{
 const p=proxy.address().port;await run(['fixture','list','--date','today','--competition','ucl'],0,p);
 const refused=await run(['fixture','load','--pick','1'],1,p);assert.equal(refused.error.code,'match_live');
 const loaded=await run(['fixture','load','--pick','1','--force'],0,p);assert.equal(loaded.result.home.name,fixture.home.name);assert.equal(loaded.result.away.name,fixture.away.name);
}finally{proxy.close();}
await run(['mcp-manifest']);await run(['reset','--yes']);await run(['show']);
const goal=await run(['goal','add','--side','home','--scorer','GUI Proof','--request-id','gui-proof']);assert.equal(goal.result.score[0],1);
console.log(`${count} bundled CLI runtime checks passed`);
