import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../web/instrument_web_soak.py', import.meta.url), 'utf8');
const script = source.split('<script id="r7-web-soak-probe">')[2].split('</script>')[0];
function probe(search = '?r7-soak=1') {
  let clock = 0, raf;
  const listeners = {}, samples = [];
  const document = {visibilityState:'visible', addEventListener:(name, fn)=>listeners[name]=fn};
  vm.runInNewContext(script, {document, location:{search}, URLSearchParams,
    performance:{now:()=>clock}, requestAnimationFrame:fn=>raf=fn,
    console:{log:line=>{if(line.startsWith('R7_RAF_SAMPLE ')) samples.push(JSON.parse(line.slice(14)));}}});
  return {samples, frame(time){clock=time; raf?.(time);}, visibility(value,time){clock=time; document.visibilityState=value; listeners.visibilitychange?.();}, hasRAF:()=>!!raf};
}
test('one-second and longer visible stalls are retained',()=>{
  const p=probe(); [16,32,1232,5232].forEach(t=>p.frame(t));
  assert.equal(p.samples[0].frozen_frames_ge_1000ms,2);
  assert.equal(p.samples[0].max_frame_ms,4000);
  assert.equal(p.samples[0].frames,4);
});
test('hidden-tab elapsed time does not become a gameplay freeze',()=>{
  const p=probe(); p.frame(16); p.visibility('hidden',32); p.frame(20000);
  p.visibility('visible',25000); p.frame(25016); p.visibility('hidden',25032);
  assert.equal(p.samples.at(-1).frames,1);
  assert.equal(p.samples.at(-1).max_frame_ms,16);
  assert.equal(p.samples.at(-1).frozen_frames_ge_1000ms,0);
});
test('probe is inactive without the explicit QA query',()=>assert.equal(probe('').hasRAF(),false));
