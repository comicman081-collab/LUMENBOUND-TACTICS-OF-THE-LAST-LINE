import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,input,port='9482',width='1280',height='720']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],samples=[];
const url=new URL(input);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','live-motion-20260913');
const delay=ms=>new Promise(r=>setTimeout(r,ms));let recording=false;
function check(ok,name){checks.push({pass:!!ok,name});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Missing action '+s.screen);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function stop(){if(!recording)return;const data=await session.evaluate(`new Promise(resolve=>{const r=window.__record;r.recorder.onstop=()=>{const reader=new FileReader();reader.onloadend=()=>resolve(reader.result);reader.readAsDataURL(new Blob(r.chunks,{type:r.recorder.mimeType}));r.stream.getTracks().forEach(t=>t.stop())};r.recorder.stop()})`);await writeFile(path.join(output,'actual_combat.webm'),Buffer.from(data.split(',')[1],'base64'));recording=false;}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:url.href,port:Number(port),width:Number(width),height:Number(height)});
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 await session.game('prepare_stage_contact',{stage_id:'CH01-N20',campaign_flow:true});let s;
 for(let n=0;n<200;n++){s=await session.game();if(s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning&&!s.transition_loading.active)break;await delay(350);}
 check(s.map?.player_rules,'ordinary resource and unlock rules');
 await delay(350);await tap(await session.game(),b=>b.text==='다음 조우');
 for(let n=0;n<30;n++){s=await session.game();if(s.buttons.some(b=>!b.disabled&&b.text.includes('칸 이동')))break;await delay(200);}
 await tap(s,b=>b.text.includes('칸 이동'));
 let result,started=0,entryTick=null,entrySeen=false,victoryScene=false;
 for(let n=0;n<700;n++){
  s=await session.game();
  if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled))await tap(s,b=>b.name==='EventDialogueNext');
  if(s.battle?.ready){
   if(!started){started=Date.now();await session.evaluate(`(()=>{const stream=document.querySelector('canvas').captureStream(30);const recorder=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp8',videoBitsPerSecond:4500000});const r=window.__record={stream,recorder,chunks:[]};recorder.ondataavailable=e=>{if(e.data.size)r.chunks.push(e.data)};recorder.start(1000);return true})()`);recording=true;await session.mark('recorded_real_combat');}
   const b=s.battle;samples.push({at:Date.now(),time:b.time,wave:b.wave,action_frames:b.action_frames,contact:b.contact_commits,readout:b.combat_readout,projectiles:b.projectiles,defeats:b.enemy_defeat_bursts,scene:b.boss_scene,actors:b.actors.map(a=>({id:a.id,hp:a.hp,action:a.action_motion,track:a.motion_track,ground:a.ground_contact})),numbers:b.damage_numbers});
   if(samples.length%45===0)await session.checkpoint('live_'+samples.length);
   if(b.boss_scene.entry_elapsed>=0){if(entryTick===null)entryTick=b.time;check(b.time===entryTick,'entrance preserves combat clock');entrySeen=true;}
   if(b.boss_scene.victory_elapsed>=0){victoryScene=true;check(b.boss_scene.arena,'boss arena retained at victory');}
  }
  if(s.screen==='RESULT'&&!s.transition_loading.active){result=s;break;}
  await delay(100);
 }
 await stop();
 check(result?.restart_progress.first_clear['CH01-N20'],'natural AUTO victory committed stage 1-20');
 check(result?.campaign_transition.to_stage==='CH02-N01','next chapter handoff preserved');
 check(entrySeen&&victoryScene,'boss arrival and exit both observed');
 check(samples.every(s=>s.action_frames.error===''),'motion pages loaded without errors throughout');
 check(samples.every(s=>s.action_frames.decoded_bytes<=s.action_frames.budget),'motion memory stays bounded');
 const observed=new Map();for(const s of samples)for(const a of s.actors)if(a.action.redrawn){const key=a.id+':'+a.action.action;if(!observed.has(key))observed.set(key,new Set());observed.get(key).add(a.action.frame);}
 check([...observed.keys()].some(k=>k.endsWith(':basic_attack'))&&[...observed.keys()].some(k=>k.endsWith(':normal_skill'))&&[...observed.keys()].some(k=>k.endsWith(':ultimate')),'new basic, skill and ultimate poses occur during real combat');
 check([...observed.entries()].filter(([k,v])=>k.startsWith('CHR')&&v.size>=3).length>=5,'multiple real player attacks advance across at least three poses');
 check([...observed.entries()].some(([k,v])=>k.startsWith('BOSS')&&v.size>=2),'boss redrawn attack advances under actual rules');
 check(samples.every(s=>s.actors.every(a=>Math.abs(a.ground.contact_error)<.001)),'ground contact retained during hits and skills');
 check(samples.some(s=>s.projectiles>0)&&samples.some(s=>s.contact>0),'projectile launch and delayed contact both active');
 check(samples.some(s=>s.numbers.some(n=>n.crit)),'critical damage presentation observed');
 check(session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text)).length===0,'no browser or engine runtime errors');
 await session.checkpoint('actual_victory');
}catch(e){checks.push({pass:false,name:String(e)});console.error(e);await stop().catch(()=>{});await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,samples,scope:'Real-rule AUTO CH01-N20 combat with legal geared level-60 disposable party. No invincibility, forced win, wave seek or held renderer. Actual canvas video; recording overhead is not a performance baseline.'},null,2));}
