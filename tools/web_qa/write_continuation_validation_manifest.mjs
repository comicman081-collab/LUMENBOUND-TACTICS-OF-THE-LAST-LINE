// Run only after every listed gate exists and passes. This is not deployment.
import {readFile,writeFile,readdir,stat,copyFile,mkdir} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
async function hash(p){const h=createHash('sha256');for await(const b of createReadStream(p))h.update(b);return {path:p.replaceAll('\\','/'),bytes:(await stat(p)).size,sha256:h.digest('hex')};}
const prefix='reports/gameplay_qa/20260907_',candidate='builds/web_gameplay_qa_20260907_candidate33/development';
const runs=[];
for(const name of ['briefing26_audit','progression26_audit','route29_matrix','map31_gallery','audio32_audit','motion33_audit','final33_audit','final33_clean']){
  const base=prefix+name,acceptance=await json(base+'/acceptance.json'),report=await json(base+'/gameplay_report.json');
  if(!acceptance.checks.length||acceptance.checks.some(c=>!c.pass))throw Error('Acceptance not PASS: '+name);
  const errors=report.events.filter(e=>['Runtime.exceptionThrown','Network.loadingFailed','Network.responseReceived'].includes(e.method));
  const messages=report.events.filter(e=>e.method==='Runtime.consoleAPICalled').flatMap(e=>e.params.args.map(a=>a.value)).filter(v=>typeof v==='string');
  if(errors.length||messages.some(t=>t.includes('SCRIPT ERROR:')||t.includes('WARNING:')))throw Error('Runtime error: '+name);
  const phases={};for(const w of report.telemetry.windows){const p=phases[w.phase]??={frames:0,max_ms:0,over1000:0,full_window_p95_max_ms:0};p.frames+=w.count;p.max_ms=Math.max(p.max_ms,w.max);p.over1000+=w.over1000;if(w.count/w.fps>=4.5)p.full_window_p95_max_ms=Math.max(p.full_window_p95_max_ms,w.p95);}
  let readyCombat=null;
  if(name==='final33_clean'){
    const mark=report.actions.find(a=>a.type==='mark'&&a.name==='final_n20_battle');
    const perfMark=report.telemetry.marks.find(m=>m.name===mark.name),origin=mark.at-perfMark.at;
    const first=report.actions.find(a=>a.type==='game'&&a.result?.battle?.ready);
    const ready=first.at-origin;
    const complete=report.telemetry.windows.filter(w=>w.phase==='final_n20_battle'&&w.at-w.count/w.fps*1000>=ready);
    readyCombat={first_observed_ready_ms:ready,windows:complete.length,frames:complete.reduce((n,w)=>n+w.count,0),p95_max_ms:Math.max(...complete.map(w=>w.p95)),max_ms:Math.max(...complete.map(w=>w.max)),over250:complete.reduce((n,w)=>n+w.over250,0),scope:'Only complete windows after first observed assets-ready state; raw combined entry/combat measurements remain separately retained.'};
  }
  runs.push({name,checks:acceptance.checks.length,url:report.url,performance_baseline:name==='final33_clean',phases,ready_combat:readyCombat,loading_logs:messages.filter(t=>/WARMUP_COMPLETE|PRELOAD_/.test(t)),acceptance:await hash(base+'/acceptance.json')});
}
const fault=await json(prefix+'hd30_failure_recovery/acceptance.json');
if(!fault.checks.length||fault.checks.some(c=>!c.pass))throw Error('Expected 503 recovery gate failed');
const nativeFiles=[['ground33_independent_native.log','TEST_SUMMARY total=287 pass=287 fail=0'],['candidate31_map_native.log','MAP_TEST_SUMMARY total=354 pass=354 fail=0'],['candidate33_density_native.log','FULL_DENSITY_TEST actors=109 effects=436 map_actors=109 failures=[]']];
for(const [file,summary] of nativeFiles){const content=await readFile(prefix+file,'utf8');if(!content.includes(summary)||content.includes('SCRIPT ERROR:'))throw Error('Native gate: '+file);}
const matte=await json(prefix+'ENCLOSED_MATTE_RUNTIME_AUDIT.json');if(matte.checks.some(c=>!c.pass))throw Error('Matte gate');
const anchors=await json(prefix+'contact_anchor_analysis.json');
if((await hash(anchors.output)).sha256!==anchors.sha256)throw Error('Contact registry changed');
for(const source of anchors.sources)if((await hash(source.path)).sha256!==source.sha256)throw Error('Contact source changed: '+source.path);
const protectedDiff=execFileSync('git',['status','--porcelain','--','.deploy','.github','.openai','dist','builds/web_r7_current_release'],{encoding:'utf8'}).trim();
if(protectedDiff)throw Error('Protected release path changed: '+protectedDiff);
const release='builds/web_r7_current_release',chunks=await json(release+'/r7_current_a1be9b289386.pck.chunks.json'),releaseHash=createHash('sha256');let releaseBytes=0;
for(const c of chunks.chunks){const item=await hash(release+'/'+c.file);if(item.sha256!==c.sha256||item.bytes!==c.size)throw Error('Protected release chunk changed');for await(const b of createReadStream(release+'/'+c.file)){releaseHash.update(b);releaseBytes+=b.length;}}
const releaseSha=releaseHash.digest('hex');if(releaseSha!=='a1be9b289386df320c484567d72869f91a92c1e0da3621bb3db7b10dac80e98c')throw Error('Protected baseline mismatch');
const pages=[];
for(const [family,revision] of [['full_density','r2'],['full_density_effects','r1'],['map_density','r1']]){
  const base=`godot/assets/runtime_web/${family}/${revision}`;
  async function walk(relative=''){for(const e of await readdir(path.join(base,relative),{withFileTypes:true})){const sub=path.join(relative,e.name);if(e.isDirectory())await walk(sub);else if(e.name.endsWith('.png')){const src=await hash(path.join(base,sub)),dst=await hash(path.join(candidate,'_hd',family,revision,sub));if(src.sha256!==dst.sha256)throw Error('Sidecar mismatch');pages.push(dst);}}}await walk();
}
if(pages.length!==644)throw Error('Sidecar count changed');
const code=['godot/battle/view/battle_view.gd','godot/battle/view/battle_actor_choreography.gd','godot/battle/view/battle_grounding.gd','godot/data/battle_contact_anchors_r1.json','godot/battle/view/battle_sprite_library.gd','godot/battle/view/density_texture_loader.gd','godot/autoload/web_soak_probe.gd','godot/chapter_map/view/web_map_material_policy.gd','godot/chapter_map/view/environment_mesh_library.gd','godot/assets/art/chapter_map/R19/environment_polish.glb','godot/screens/app_shell.gd','godot/qa/local_gameplay_probe.gd','godot/tests/test_runner.gd','tools/art/build_battle_contact_anchors.py'];
const files=[];for(const file of [...code,...['index.html','index.pck','index.wasm'].map(f=>candidate+'/'+f)])files.push(await hash(file));
const audio=await json(prefix+'audio32_audit/acceptance.json'),route=await json(prefix+'route29_matrix/acceptance.json'),visual=await json(prefix+'ground33_visual_acceptance.json');
if(visual.status!=='LOCAL_GROUNDING_VISUAL_PASS')throw Error('Human-visible grounding review not recorded');
const quarantine=['enclosed_white_matte/retained_failures/retention_manifest.json','hd_loading_candidates/retention_manifest.json','startup_candidate28/retention_manifest.json','botanical_r18/retention_manifest.json','grounding_predecessors/retention_manifest.json','grounding_candidate32/retention_manifest.json'].map(p=>'work/gameplay_qa_quarantine_20260907/'+p);
for(const p of quarantine)await stat(p);
const limitations=['Browser viewport emulation, not physical Android/iOS thermal/memory verification.','Local graphical/audio signal QA, not human listening certification.','Source-derived art and role choreography do not establish new joint-animated commercial-reference art parity.','No external ChatGPT web review was performed in this continuation; no external generation/analysis service or model weights were used.','No deployment, promotion approval or failed-asset disposal is authorized by these local tests.'];
const output={created_at:new Date().toISOString(),status:'LOCAL_GAMEPLAY_AND_GROUNDING_VERIFIED_NOT_DEPLOYED',candidate:33,no_deployment:true,no_actions:true,no_deletion:true,physical_phone_tested:false,browser_runs:runs,full_route:{stages:route.results.length,waves:route.results.reduce((n,r)=>n+r.waves,0),checks:route.checks.length,fixture:route.fixture},expected_hd_failure:{checks:fault.checks.length,artifact:prefix+'hd30_failure_recovery/acceptance.json',intentional_network_error:'one HTTP 503, excluded from ordinary error-free runs'},audio:{samples:audio.graph.analysis.battle_samples,maximum_digital_silence_ms:audio.graph.analysis.maximum_zero_run_ms,scope:audio.scope},grounding:{frames:anchors.frames,entities:anchors.entities,visual},matte,native:nativeFiles,baseline_release:{sha256:releaseSha,bytes:releaseBytes,protected_diff:protectedDiff},hashes:files,sidecars:pages,quarantine_manifests:quarantine,limitations};
await mkdir('reports/gameplay_qa/history',{recursive:true});
for(const name of ['CURRENT_STATUS.md','REMAINING_GATES.md','VERIFICATION_MANIFEST.json']){
  const destination='reports/gameplay_qa/history/20260907_candidate27_'+name;
  try{await stat(destination);}catch{await copyFile(prefix+name,destination);}
}
await writeFile(prefix+'VERIFICATION_MANIFEST.json',JSON.stringify(output,null,2)+'\n');
const perf=runs.at(-1).phases.final_n20_battle;
await writeFile(prefix+'CURRENT_STATUS.md',`# 최신 로컬 검수 — candidate 33\n\n배포 · GitHub Actions · push · commit · 삭제 없음. 물리적 휴대전화 및 전체 상용 아트 승인과 구분한다.\n\n## 발 접지와 전투 동작\n\n- 벽·용암 위에 떠 있던 보스 전투를 넓게 이어진 석재 전경 바닥으로 수정. 기존 고해상도 배경을 Canvas에서 조합했고 원본 이미지는 수정하지 않았다.\n- 109개 기본/HD 개체와 8개 주요 고해상도 개체의 총 18,528개 프레임을 읽기 전용 알파 분석. 자세가 기울어도 바닥·접점·그림자·체력바를 같은 변환에 맞춘다.\n- 일반 공격과 대기 간 확대 배율 차이로 몸이 작아졌다 커지는 오류 제거. 근접 접근·총기 반동·지원 시전 구분, 피격에 의한 공격 중단과 배속 발사체 이중 가속도 수정.\n- 실패한 좁은 보스 배치(candidate32)와 공중부양 원본(candidate31)은 해시를 검증해 격리 보존.\n\n## 함께 검수한 나머지 작업\n\n- 실제 브라우저 CH01 N01~N20: 20스테이지 / 45웨이브 / 3,453검사 PASS. 무적·인접 시작 QA이며 밸런스 검수가 아니다.\n- N13 모바일 튜토리얼, N01/N05 보상·성장·장비 스크롤, N20→H01 연결, 강/벽 진입 차단, 맵 배경·오브젝트와 화면 회전 검수 포함.\n- CHR002 팔 안쪽·CHR004 머리카락 사이 흰 영역: 각 80프레임 실제 아틀라스 알파와 수정 원본이 일치.\n- 고해상도 전투 개체 109 / 발사체·스킬 FX 436 / 맵 개체 109 로딩 검사 실패 0. 실행본 HD 페이지 644개 모두 소스 해시와 일치.\n- Web 그래픽 준비는 후보29에서 약20.9초→7.95초로 감소. 총 다운로드/실행 시간이 7.95초라는 뜻은 아니다.\n- 실제 오디오 신호 ${audio.graph.analysis.battle_samples}회 샘플, 최장 연속 디지털 무음 ${audio.graph.analysis.maximum_zero_run_ms.toFixed(1)}ms. 스피커 청취/실기기 인증은 아니다.\n\n## 검증 결과\n\n${runs.map(r=>'- '+r.name+': '+r.checks+'/'+r.checks+' PASS').join('\n')}\n- 일반 회귀 287/287, 맵 회귀 354/354, 알파·HD 자산 검사 PASS.\n- 단독 측정 N20 전투/진입: 최대 ${perf.max_ms.toFixed(1)}ms, 1초 이상 지연 ${perf.over1000}회, 완전한 창의 최악 p95 ${perf.full_window_p95_max_ms.toFixed(1)}ms.\n\n## 검증 경계\n\n${limitations.map(t=>'- '+t).join('\n')}\n\n실행본: ${candidate}\n실제 녹화: reports/gameplay_qa/20260907_motion33_audit/actual_combat.webm\n상세: 20260907_VERIFICATION_MANIFEST.json\n`);
await writeFile(prefix+'REMAINING_GATES.md','# Remaining external/production gates\n\n'+limitations.map(t=>'- '+t).join('\n')+'\n\nThe reported grounding bug, scale pop, actual CH01 route and mobile layout regressions have local evidence. This is not a claim that source art now matches all commercial reference animation. Retain every failed batch; no deletion or deployment.\n');
const steady=runs.at(-1).ready_combat;
await writeFile(prefix+'CURRENT_STATUS.md',(await readFile(prefix+'CURRENT_STATUS.md','utf8'))+`\n### 로딩 완료 후 구간 분리\n\n최초 assets-ready 관측 이후의 완전한 측정 창 ${steady.windows}개 / ${steady.frames}프레임: 최악 p95 ${steady.p95_max_ms.toFixed(1)}ms, 최대 ${steady.max_ms.toFixed(1)}ms, 250ms 초과 프레임 ${steady.over250}회. 위의 진입 포함 수치와 함께 보존한다. 0ms 지연 또는 실기기 60fps 인증이라는 뜻은 아니다.\n`);
console.log(JSON.stringify({candidate:33,status:output.status,checks:runs.reduce((n,r)=>n+r.checks,0),pages:pages.length,release_sha256:releaseSha,performance:perf}));
