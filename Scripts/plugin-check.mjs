import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root=new URL('../StreamDeckPlugin/com.juniornkanabassi.scorebug.sdPlugin/',import.meta.url);
for(const slot of [1,2])for(const [suffix,size] of [['',72],['@2x',144]]){
 const png=readFileSync(new URL(`imgs/actions/set-competition/nations-league-${slot}${suffix}.png`,root));
 assert.equal(png.readUInt32BE(16),size);assert.equal(png.readUInt32BE(20),size);
}
assert(readFileSync(new URL('ui/set-competition.html',root),'utf8').includes('<option value="nations-league">Nations League</option>'));
assert(readFileSync(new URL('bin/plugin.js',root),'utf8').includes('nations-league'));
const manifest=JSON.parse(readFileSync(new URL('manifest.json',root)));
assert.equal(manifest.Version,'1.0.0.0');
const pkg=JSON.parse(readFileSync(new URL('../StreamDeckPlugin/package.json',import.meta.url)));
const lock=JSON.parse(readFileSync(new URL('../StreamDeckPlugin/package-lock.json',import.meta.url)));
assert.equal(pkg.version,'1.0.0');
assert.equal(lock.version,pkg.version);
assert.equal(lock.packages[''].version,pkg.version);
console.log('14 plugin checks passed');
