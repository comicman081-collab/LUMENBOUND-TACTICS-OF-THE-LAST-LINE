import {readFile,writeFile,readdir,stat} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
const root=process.cwd();
const normalized=p=>p.replaceAll('\\','/');
async function hashFile(relative){const filename=path.resolve(root,relative);const hash=createHash('sha256');for await(const chunk of createReadStream(filename))hash.update(chunk);return {path:normalized(relative),bytes:(await stat(filename)).size,sha256:hash.digest('hex')};}
async function listTree(relative){const result=[];for(const e of await readdir(path.join(root,relative),{withFileTypes:true})){const child=path.join(relative,e.name);if(e.isDirectory())result.push(...await listTree(child));else if(e.isFile())result.push(await hashFile(child));}return result;}
async function json(relative){return JSON.parse(await readFile(relative,'utf8'));}
const releaseDir='builds/web_r7_current_release';
const chunks=await json(`${releaseDir}/r7_current_a1be9b289386.pck.chunks.json`);
const total=createHash('sha256');let totalBytes=0;const checkedChunks=[];
for(const chunk of chunks.chunks){const file=await hashFile(`${releaseDir}/${chunk.file}`);if(file.sha256!==chunk.sha256||file.bytes!==chunk.size)throw Error('Baseline chunk changed: '+chunk.file);for await(const b of createReadStream(path.join(releaseDir,chunk.file))){total.update(b);totalBytes+=b.length;}checkedChunks.push(file);}
const releaseSha=total.digest('hex');if(releaseSha!==chunks.original.sha256||totalBytes!==chunks.original.size)throw Error('Baseline release content changed');
const protectedDiff=execFileSync('git',['diff','--name-only','--','.deploy','.github','.openai','dist',releaseDir],{encoding:'utf8'}).trim();
if(protectedDiff)throw Error('Protected deployment files differ: '+protectedDiff);
// Candidate 20 differs from 19 only by the event page counter's no-wrap rule.
// Repeat the shared briefing + elite/home boundary flows on 20 and retain the
// unchanged broad gameplay/terrain regressions from 19 with their exact IDs.
const runNames=['20260907_briefing20_audit','20260907_elite20_audit','20260907_final19_audit','20260907_map19_gallery','20260907_progression19_audit'];
const browserRuns=[];
for(const run of runNames){
  const dir=`reports/gameplay_qa/${run}`;
  const acceptance=await json(`${dir}/acceptance.json`), report=await json(`${dir}/gameplay_report.json`);
  if(!acceptance.checks.length||acceptance.checks.some(c=>!c.pass))throw Error('Required local runtime gate is not PASS: '+run);
  const phases={};
  for(const w of report.telemetry.windows){const p=phases[w.phase]??={frames:0,max_ms:0,over1000:0,full_window_p95_max_ms:0};p.frames+=w.count;p.max_ms=Math.max(p.max_ms,w.max);p.over1000+=w.over1000;if(w.count>=200)p.full_window_p95_max_ms=Math.max(p.full_window_p95_max_ms,w.p95);}
  browserRuns.push({run,acceptance,phases,network_or_js_failures:report.events.filter(e=>['Runtime.exceptionThrown','Network.loadingFailed','Network.responseReceived'].includes(e.method)),browser_log_entries:report.events.filter(e=>e.method==='Log.entryAdded').map(e=>e.params.entry),acceptance_hash:await hashFile(`${dir}/acceptance.json`)});
}
const files=[
  'builds/web_gameplay_qa_20260907_candidate20/development/index.pck',
  'builds/web_gameplay_qa_20260907_candidate20/development/index.wasm',
  'builds/web_gameplay_qa_20260907_candidate20/development/index.html',
  'godot/assets/art/chapter_map/R17/environment_polish.glb',
  'work/map_polish_20260907/candidate02/environment_polish.glb',
  'tools/blender/build_web_environment_polish.py',
  'godot/chapter_map/runtime/chapter_map_screen.gd',
  'godot/chapter_map/view/map_backdrop.gd',
  'godot/screens/app_shell.gd',
  'godot/ui/touch_progression_scroll.gd',
  'godot/ui/bounded_briefing.gd',
  'godot/qa/local_gameplay_probe.gd',
  'godot/data/runtime_texture_integrity.json',
  'reports/gameplay_qa/20260907_map_final20.log',
  'reports/gameplay_qa/20260907_general_final20.log',
  'reports/gameplay_qa/20260907_BRIEFING_CONTENT_INVENTORY.json',
  'tools/web_qa/mobile_briefing_audit.mjs',
];
for(const e of await readdir('godot/chapter_map/shaders'))if(e.endsWith('.gdshader'))files.push(`godot/chapter_map/shaders/${e}`);
const hashes=[];for(const f of files)hashes.push(await hashFile(f));
const source=hashes.find(f=>f.path.startsWith('work/')&&f.path.endsWith('.glb'));
const runtime=hashes.find(f=>f.path.startsWith('godot/assets/')&&f.path.endsWith('.glb'));
if(source.sha256!==runtime.sha256)throw Error('Source/runtime environment kit mismatch');
const quarantines=[
  {path:'work/gameplay_qa_quarantine_20260907/web_gameplay_qa_20260907_candidate05',reason:'Web script compile failure; stale inferred distance type.'},
  {path:'work/gameplay_qa_quarantine_20260907/web_gameplay_qa_20260907_candidate08',reason:'Active map construction incorrectly aborted by the old five-second watchdog.'},
  {path:'work/gameplay_qa_quarantine_20260907/web_gameplay_qa_20260907_candidate12',reason:'Visual FAIL: portrait button geometry retained after landscape rotation; automated state-only acceptance did not cover it.'},
  {path:'work/gameplay_qa_quarantine_20260907/web_gameplay_qa_20260907_candidate16',reason:'Briefing art wrapper runtime property error; tutorial next-page scroll offset retained.'},
  {path:'work/gameplay_qa_quarantine_20260907/web_gameplay_qa_20260907_candidate17',reason:'Inherited briefing art wrapper runtime property error. The separate page-2 short-copy scroll assertion was a test timing error.'},
  {path:'work/gameplay_qa_quarantine_20260907/web_gameplay_qa_20260907_candidate19',reason:'Gameplay regression passes retained, but visual review found a three-line event page counter. Superseded by the explicit no-wrap fix in candidate 20.'},
  {path:'work/gameplay_qa_quarantine_20260907/mobile_briefing_failure_evidence',reason:'Original N13 oversized modal, candidate runtime errors and classified test failures retained with review notes.'},
  {path:'work/map_polish_20260907/quarantine/candidate01_preview_failed',reason:'Blender preview failed with a missing world. Source, geometry, cache and log retained.'},
];
for(const q of quarantines)q.files=await listTree(q.path);
const quarantineManifest={status:'RETAIN_NO_DISPOSAL',reason:'Commercial visual acceptance and complete asset/promotion gates are not all PASS. No retirement or deletion is authorized by this report.',quarantines};
await writeFile('work/gameplay_qa_quarantine_20260907/quarantine_manifest.json',JSON.stringify(quarantineManifest,null,2));
const output={created_at:new Date().toISOString(),status:'LOCAL_VERIFICATION_ONLY_NOT_DEPLOYED',commercial_visual_acceptance:'HOLD: stylized map materially improved but contemporary high-end commercial-game parity is not established.',physical_phone_tested:false,external_chatgpt_review:'NOT_PERFORMED_IN_THIS_BATCH',baseline:{bytes:totalBytes,sha256:releaseSha,protected_diff:protectedDiff,chunks:checkedChunks},browser_runs:browserRuns,hashes,quarantine_manifest:'work/gameplay_qa_quarantine_20260907/quarantine_manifest.json',limitations:['Cold Web startup still exceeds the five-second target on this host.','HD actor/FX coverage is partial and approval remains LOCAL_QA_ONLY; movement/basic/normal and other enemies still use compact fallbacks.','Twenty-stage fresh chain is service-level evidence, not twenty manually played browser stages.','Browser audio was muted; no listening QA or physical mobile-device measurement.']};
await writeFile('reports/gameplay_qa/20260907_VERIFICATION_MANIFEST.json',JSON.stringify(output,null,2));
console.log(JSON.stringify({status:output.status,browser_checks:browserRuns.map(r=>({run:r.run,pass:r.acceptance.checks.filter(c=>c.pass).length,fail:r.acceptance.checks.filter(c=>!c.pass).length})),release_sha256:releaseSha,quarantined_files:quarantines.reduce((n,q)=>n+q.files.length,0)}));
