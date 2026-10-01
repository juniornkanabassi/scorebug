// Test the actual shared client, replacing only SDK/transport imports; no Stream Deck or listener is touched.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {pathToFileURL} from 'node:url';
let checks=0;
const eq=(actual,expected)=>{assert.equal(actual,expected);checks++;};
const root=mkdtempSync('/private/tmp/fix-scorebug-plugin-');
try {
 const source=readFileSync(new URL('../StreamDeckPlugin/src/lib/scorebug.ts',import.meta.url),'utf8').replace(/^import .*;$/gm,'');
 const stubs='const streamDeck={logger:{warn(){}}}; const SingletonAction=class{}; const WebSocket=class{addEventListener(){}}; const launchAndWait=async()=>{globalThis.launches++;return true;};\n';
 writeFileSync(root+'/client.mjs',stubs+stripTypeScriptTypes(source));
 const {server}=await import(pathToFileURL(root+'/client.mjs'));
 for(const response of [{ok:false,status:400},{ok:false,status:500},{ok:true,status:200,saveFailed:true},{ok:true,status:200},{error:'ECONNRESET'},{error:'ETIMEDOUT'}]) {
  let sends=0,alerts=0;globalThis.launches=0;
  globalThis.fetch=async()=>{sends++;if(response.error)throw Object.assign(new Error('uncertain delivery'),{cause:{code:response.error}});return {...response,headers:new Headers(response.saveFailed?{'X-Scorebug-Save-Failed':'true'}:{})};};
  await server.send(1,'goal',{side:'home'},async()=>{alerts++;});
  eq(sends,1);eq(globalThis.launches,0);eq(alerts,response.ok&&!response.saveFailed?0:1);
 }
 let sends=0,alerts=0;globalThis.launches=0;
 globalThis.fetch=async()=>{if(++sends===1)throw Object.assign(new Error('not running'),{cause:{code:'ECONNREFUSED'}});return {ok:true,status:200,headers:new Headers()};};
 await server.send(1,'goal',{side:'home'},async()=>{alerts++;});
 eq(sends,2);eq(globalThis.launches,1);eq(alerts,0);
 console.log(`${checks} plugin command checks passed`);
}finally{rmSync(root,{recursive:true,force:true});}
