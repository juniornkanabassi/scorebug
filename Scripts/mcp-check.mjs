#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
const port=Number(process.env.SCOREBUG_PORT);assert(Number.isInteger(port)&&port>=1024&&port<=65535&&port!==8600,'Set a disposable SCOREBUG_PORT');
const cli=process.env.SCOREBUG_CLI??new URL('./scorebug.mjs',import.meta.url).pathname;
const shim=process.env.SCOREBUG_MCP??new URL('../mcp/scorebug-mcp.mjs',import.meta.url).pathname;
const child=spawn(process.execPath,[shim],{env:{...process.env,SCOREBUG_CLI:cli}});
const pending=new Map();let seq=0,checks=0;
child.stderr.on('data',d=>process.stderr.write(d));
createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);const p=pending.get(r.id);assert(p,'unexpected response '+line);pending.delete(r.id);p(r);});
const timer=setTimeout(()=>{child.kill();throw new Error('MCP check timed out');},30000);
const call=(method,params)=>new Promise(r=>{const id=++seq;pending.set(id,r);child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');});
try {
 const init=await call('initialize',{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'check',version:'1'}});assert.equal(init.result.protocolVersion,'2025-06-18');checks++;
 child.stdin.write(JSON.stringify({jsonrpc:'2.0',method:'notifications/initialized'})+'\n');
 const list=await call('tools/list');assert.equal(list.result.tools.length,14);checks++;
 const tool=(name,args={})=>call('tools/call',{name,arguments:args});
 const status=await tool('status');assert(JSON.parse(status.result.content[0].text).result.running);checks++;
 await tool('reset',{yes:true});
 for(let i=0;i<2;i++){
  const goal=await tool('goal_add',{side:'home',scorer:'Test',minute:23,requestId:'mcp-g1'});assert.equal(JSON.parse(goal.result.content[0].text).result.score[0],1);checks++;
 }
 const missing=await tool('reset');assert.equal(missing.result.isError,true);checks++;
 assert.equal((await tool('unknown')).error.code,-32602);checks++;
 assert.equal((await tool('goal_add',{side:'home',port:8600})).error.code,-32602);checks++;
 assert.equal((await tool('clock_adjust',{by:'oops'})).error.code,-32602);checks++;
 assert.deepEqual((await call('ping')).result,{});checks++;
 assert.equal((await call('unknown')).error.code,-32601);checks++;
 child.stdin.end();console.log(`${checks} MCP checks passed`);
}finally{clearTimeout(timer);child.kill();}
