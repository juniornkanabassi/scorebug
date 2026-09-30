#!/usr/bin/env node
// Thin stdio adapter; the CLI's command table is the only tool catalogue.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
const cli = process.env.SCOREBUG_CLI || fileURLToPath(new URL('../Scripts/scorebug.mjs',import.meta.url));
const exec=promisify(execFile);
const manifest=JSON.parse((await exec(process.execPath,[cli,'mcp-manifest'],{timeout:10000})).stdout);
const reply=(id,result,error)=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',id,...(error?{error}:{result})})+'\n');
const flag=key=>'--'+key.replace(/[A-Z]/g,c=>'-'+c.toLowerCase());
async function handle(line) {
 let req;try{req=JSON.parse(line);}catch{reply(null,null,{code:-32700,message:'Parse error'});return;}
 if(!req||req.jsonrpc!=='2.0'||typeof req.method!=='string'||(req.id!==undefined&&typeof req.id!=='string'&&typeof req.id!=='number'&&req.id!==null)){reply(req?.id??null,null,{code:-32600,message:'Invalid request'});return;}
 if(req.id===undefined)return;
 const {id,method,params}=req;
 if(method==='initialize'){reply(id,{protocolVersion:'2025-06-18',capabilities:{tools:{}},serverInfo:{name:manifest.name,version:manifest.version}});return;}
 if(method==='ping'){reply(id,{});return;}
 if(method==='tools/list'){reply(id,{tools:manifest.tools});return;}
 if(method!=='tools/call'){reply(id,null,{code:-32601,message:'Method not found'});return;}
 const tool=manifest.tools.find(t=>t.name===params?.name),args=params?.arguments??{};
 if(!tool||!args||typeof args!=='object'||Array.isArray(args)){reply(id,null,{code:-32602,message:'Unknown tool or invalid arguments'});return;}
 for(const [key,value] of Object.entries(args)) {
  const p=tool.inputSchema.properties[key];
  if(!p||typeof value!==(p.type==='integer'?'number':p.type)||(p.type==='integer'&&!Number.isSafeInteger(value))||(p.enum&&!p.enum.includes(value))||(p.minimum!==undefined&&value<p.minimum)||(p.maximum!==undefined&&value>p.maximum)){
   reply(id,null,{code:-32602,message:'Invalid argument '+key});return;
  }
 }
 const argv=[...tool.name.split('_'),'--json'];
 for(const [key,value] of Object.entries(args))if(value!==false)argv.push(value===true?flag(key):`${flag(key)}=${value}`);
 try {
  const {stdout}=await exec(process.execPath,[cli,...argv],{timeout:150000,env:process.env});
  reply(id,{content:[{type:'text',text:stdout.trim()}]});
 }catch(e){reply(id,{content:[{type:'text',text:e.stdout?.trim()||JSON.stringify({ok:false,error:{code:'timeout',message:e.killed?'CLI timed out':'CLI failed'}})}],isError:true});}
}
for await(const line of createInterface({input:process.stdin,crlfDelay:Infinity})) {
 try{await handle(line);}catch(e){console.error(e.message);reply(null,null,{code:-32603,message:'Internal error'});}
}
