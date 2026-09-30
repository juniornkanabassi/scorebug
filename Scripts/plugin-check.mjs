import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root=new URL('../StreamDeckPlugin/com.juniornkanabassi.scorebug.sdPlugin/',import.meta.url);
for(const slot of [1,2])for(const [suffix,size] of [['',72],['@2x',144]]){
 const png=readFileSync(new URL(`imgs/actions/set-competition/nations-league-${slot}${suffix}.png`,root));
 assert.equal(png.readUInt32BE(16),size);assert.equal(png.readUInt32BE(20),size);
}
assert(readFileSync(new URL('ui/set-competition.html',root),'utf8').includes('<option value="nations-league">Nations League</option>'));
assert(readFileSync(new URL('bin/plugin.js',root),'utf8').includes('nations-league'));
console.log('10 Nations League plugin checks passed');
