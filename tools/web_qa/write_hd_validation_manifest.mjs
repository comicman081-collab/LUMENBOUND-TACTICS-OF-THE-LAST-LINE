import {readFile,writeFile,readdir,stat} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
const root=process.cwd(),normalize=p=>p.replaceAll('\\','/');
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
async function hash(p){const h=createHash('sha256');for await(const b of createReadStream(p))h.update(b);return {path:normalize(p),bytes:(await stat(p)).size,sha256:h.digest('hex')};}
const runs=[];
for(const name of ['map26_gallery','briefing26_audit','progression26_audit','final26_audit','final27_audit']){
  const base=`reports/gameplay_qa/20260907_${name}`;
  const acceptance=await json(base+'/acceptance.json'),report=await json(base+'/gameplay_report.json');
  if(acceptance.checks.some(c=>!c.pass)||!acceptance.checks.length)throw Error('Runtime gate not PASS: '+name);
  const phases={};
  for(const w of report.telemetry.windows){const p=phases[w.phase]??={frames:0,max_ms:0,over1000:0,full_window_p95_max_ms:0};p.frames+=w.count;p.max_ms=Math.max(p.max_ms,w.max);p.over1000+=w.over1000;if(w.count/w.fps>=4.5)p.full_window_p95_max_ms=Math.max(p.full_window_p95_max_ms,w.p95);}
  const errors=report.events.filter(e=>['Runtime.exceptionThrown','Network.loadingFailed','Network.responseReceived'].includes(e.method));
  if(errors.length)throw Error('Network or JS errors: '+name);
  const messages=report.events.filter(e=>e.method==='Runtime.consoleAPICalled').flatMap(e=>e.params.args.map(a=>a.value)).filter(v=>typeof v==='string');
  runs.push({name,url:report.url,checks:acceptance.checks.length,phases,loading_logs:messages.filter(t=>/WARMUP_COMPLETE|PRELOAD_/.test(t)),acceptance:await hash(base+'/acceptance.json')});
}
for(const [file,summary] of [['20260907_candidate26_native.log','TEST_SUMMARY total=277 pass=277 fail=0'],['20260907_candidate26_map.log','MAP_TEST_SUMMARY total=354 pass=354 fail=0'],['20260907_candidate27_density.log','FULL_DENSITY_TEST actors=109 effects=436 map_actors=109 failures=[]']]){
  const text=await readFile('reports/gameplay_qa/'+file,'utf8');if(!text.includes(summary)||text.includes('SCRIPT ERROR:'))throw Error('Native gate failed: '+file);
}
const matte=await json('reports/gameplay_qa/20260907_ENCLOSED_MATTE_RUNTIME_AUDIT.json');
if(matte.checks.some(c=>!c.pass))throw Error('Matte regression gate failed');
const progression=await json('reports/gameplay_qa/20260907_progression26_fresh/R15_PROGRESSION_SIMULATION.json');
if(!progression.completed_normal_route||progression.dead_ends||progression.save_reload_mismatches)throw Error('Fresh progression chain failed');
const protectedDiff=execFileSync('git',['status','--porcelain','--','.deploy','.github','.openai','dist','builds/web_r7_current_release'],{encoding:'utf8'}).trim();
if(protectedDiff)throw Error('Protected release paths differ: '+protectedDiff);
const release='builds/web_r7_current_release',chunks=await json(release+'/r7_current_a1be9b289386.pck.chunks.json');
const releaseHash=createHash('sha256');let releaseBytes=0;
for(const chunk of chunks.chunks){const file=await hash(release+'/'+chunk.file);if(file.sha256!==chunk.sha256||file.bytes!==chunk.size)throw Error('Baseline release chunk mismatch');for await(const b of createReadStream(release+'/'+chunk.file)){releaseHash.update(b);releaseBytes+=b.length;}}
const releaseSha=releaseHash.digest('hex');if(releaseSha!==chunks.original.sha256||releaseBytes!==chunks.original.size)throw Error('Release changed');
const pages=[];
for(const [family,revision] of [['full_density','r2'],['full_density_effects','r1'],['map_density','r1']]){
  const base=`godot/assets/runtime_web/${family}/${revision}`;
  async function walk(relative=''){for(const entry of await readdir(path.join(base,relative),{withFileTypes:true})){const sub=path.join(relative,entry.name);if(entry.isDirectory())await walk(sub);else if(entry.name.endsWith('.png')){const source=await hash(path.join(base,sub));const sidecar=await hash(path.join('builds/web_gameplay_qa_20260907_candidate27/development/_hd',family,revision,sub));if(source.sha256!==sidecar.sha256)throw Error('Sidecar mismatch: '+sub);pages.push(sidecar);}}}
  await walk();
}
const codePaths=['godot/battle/view/battle_sprite_library.gd','godot/battle/view/battle_view.gd','godot/battle/view/density_texture_loader.gd','godot/battle/view/full_density_effects.gd','godot/autoload/stage_asset_cache.gd','godot/autoload/web_soak_probe.gd','godot/chapter_map/runtime/chapter_map_screen.gd','godot/screens/app_shell.gd','godot/data/runtime_texture_integrity.json','godot/export_presets.cfg','tools/art/repair_enclosed_character_matte.py','tools/art/audit_enclosed_matte_runtime.py','tools/powershell/BUILD_WEB_R7.ps1'];
const files=[];for(const p of [...codePaths,'builds/web_gameplay_qa_20260907_candidate27/development/index.pck','builds/web_gameplay_qa_20260907_candidate27/development/index.wasm','builds/web_gameplay_qa_20260907_candidate27/development/index.html'])files.push(await hash(p));
const quarantineManifests=['work/gameplay_qa_quarantine_20260907/enclosed_white_matte/retained_paths_and_hashes.json','work/gameplay_qa_quarantine_20260907/enclosed_white_matte/retained_failures/retention_manifest.json','work/gameplay_qa_quarantine_20260907/hd_loading_candidates/retention_manifest.json'];
const output={created_at:new Date().toISOString(),status:'LOCAL_RUNTIME_VALIDATED_NOT_RELEASE_APPROVED',current_candidate:27,physical_phone_tested:false,external_chatgpt_review:'NOT_PERFORMED_IN_THIS_BATCH',no_deployment:true,no_github_actions:true,no_deletion:true,baseline_release:{sha256:releaseSha,bytes:releaseBytes,protected_diff:protectedDiff},browser_runs:runs,matte,art:{actors:109,all_action_cell:256,signature_cell:384,projectiles:109,projectile_cell:192,skills:327,normal_skill_cell:192,ultimate_cell:256,map_actors:109,map_cell:192,source:'existing original art / existing procedural profiles; no generative model or model weights used'},fresh_progression:{stages:progression.stages_completed,dead_ends:progression.dead_ends,save_reload_mismatches:progression.save_reload_mismatches},hashes:files,sidecars:pages,quarantine_manifests:quarantineManifests,limitations:['First Web shader initialization remains long; do not equate splitting the loading gate with eliminating startup cost.','Representative real browser gameplay is not a manual playthrough of every stage or a physical Android/iOS measurement.','Some existing animations/effects are procedural; increased source density does not establish commercial-reference animation/art parity.','No external ChatGPT review, physical-phone thermal/memory testing, or audible playback review was performed.']};
await writeFile('reports/gameplay_qa/20260907_VERIFICATION_MANIFEST.json',JSON.stringify(output,null,2)+'\n');
const latest=runs.at(-1),combat=latest.phases.final_n20_battle;
const report=`# 최신 로컬 검수 — candidate 27\n\n배포·GitHub Actions·push·파일 삭제 없음. 전체 상용 아트 승인과 구분한 로컬 검수 기록이다.\n\n## 이번 흰 잔여물 수정\n\n- 로안(CHR002) 팔 안쪽과 에다(CHR004) 헤어 내부의 불투명 흰 영역을 제거했다.\n- 각 80개 동작 프레임의 투명 영역이 실제 256px 아틀라스와 오차 없이 일치한다.\n- 필살기용 384px 프레임도 녹색 마스터·RGBA·해시를 개별 보존했다.\n- 기존 의상·무기·얼굴·게임 수치는 변경하지 않았다. 잘못된 자산은 격리했으며 삭제하지 않았다.\n\n## 함께 반영·검수한 범위\n\n- 109개 캐릭터·몹의 모든 동작 256px, 선택된 주요 동작 384px.\n- 109개 발사체 192px, 기본·일반 스킬 192px, 필살기 256px. 기존 원본/프로시저를 사용했으며 저해상도 썸네일 확대가 아니다.\n- 109개 맵 캐릭터의 대기·이동·도착 동작 192px. 화면상 크기와 발 접점은 유지한다.\n- 고해상도 PNG는 첫 실행 PCK에 넣지 않고 필요한 장면에서만 해시 검증 후 읽는다. 동시 요청은 최대 3개, 디코딩/업로드는 프레임당 1개다.\n- 파일 크기 비교 오류로 HD가 거절되던 문제와, 실제 다운로드 중인데 로딩 감시가 중단시키던 오류를 고쳤다.\n- 맵 개체별 프레임 선택을 분리해 한 몹의 이동 동작이 다른 몹의 텍스처 상태를 바꾸지 않게 했다.\n- N13 모바일 설명창 전체 페이지·회전·터치·전투·N14 연결, N01/N05 보상·성장·장비·대사, N20 보스 3웨이브·H01 연결·회전·브라우저 복귀를 검수했다.\n- 맵 배경·오브젝트·192px 캐릭터, 강 터치 통과 차단, 가로/세로 가시성 검수 통과.\n\n## 결과\n\n${runs.map(r=>'- '+r.name+': '+r.checks+'/'+r.checks+' PASS').join('\n')}\n- 일반 회귀 277/277, 맵 회귀 354/354.\n- 전체 자산 로딩: 전투 109, 발사체·이펙트 436, 맵 109 — 실패 0.\n- 새 프로필 20스테이지 서비스 체인: 막힘 0, 저장/재로드 불일치 0. 실제 전 스테이지 수동 플레이와는 구분한다.\n- 최신 N20 전투/진입 구간: 최대 ${combat.max_ms.toFixed(1)}ms, 1초 이상 지연 ${combat.over1000}회, 완전한 측정 창의 최악 p95 ${combat.full_window_p95_max_ms.toFixed(1)}ms. 물리적 휴대전화 60fps 인증은 아니다.\n\n## 남아 있는 한계\n\n첫 Web 그래픽 준비는 여전히 길다. 최신 실행 로그: ${latest.loading_logs.join(' / ')}.\n해상도와 연결 개선이 업로드 영상 수준의 관절 애니메이션/상용 아트 완성을 뜻하지 않는다. 실제 Android/iOS, 음원 청취, 외부 ChatGPT 리뷰는 이번 배치에서 수행하지 않았다. 따라서 격리본 삭제·공개 배포·전체 상용 품질 PASS는 승인하지 않았다.\n\n실행본: builds/web_gameplay_qa_20260907_candidate27/development\n상세 해시·측정·검수 경계: 20260907_VERIFICATION_MANIFEST.json\n이전 candidate 20 기록: history/20260907_candidate20_status.md\n`;
await writeFile('reports/gameplay_qa/20260907_CURRENT_STATUS.md',report);
await writeFile('reports/gameplay_qa/20260907_REMAINING_GATES.md','# Remaining production gates\n\n'+output.limitations.map(t=>'- '+t).join('\n')+'\n\nHD coverage and enclosed-matte runtime gates are now locally verified; the older partial-coverage note is superseded. Preserve all failed batches; no deployment or disposal. Full detail: 20260907_CURRENT_STATUS.md and 20260907_VERIFICATION_MANIFEST.json.\n');
console.log(JSON.stringify({status:output.status,browser_checks:runs.reduce((n,r)=>n+r.checks,0),sidecar_pages:pages.length,release_sha256:releaseSha,latest:latest.phases}));
