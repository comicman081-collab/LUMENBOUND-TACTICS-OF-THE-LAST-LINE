import {GameplaySession} from './gameplay_session.mjs';
import {writeFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import {frameStats as stats, summarizeCaptures, performanceAcceptance} from './fps_metrics.mjs';

const [output, input, port='9530', mode='full', gate='report', scenes='legacy', warmup='legacy'] = process.argv.slice(2);
const url=new URL(input); url.searchParams.set('gameplay-qa','1'); url.searchParams.set('qa','fps-1080p');
const session=new GameplaySession(output), checks=[], captures=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const initScript=`(()=>{
 const p=window.__fpsBrowser={active:true,label:'boot',frames:[],last:0,renderer:[]};
 p.start=label=>{p.active=true;p.label=label;p.frames=[];p.last=0};
 p.stop=()=>{p.active=false;return {label:p.label,frames:p.frames,renderer:p.renderer}};
 const get=HTMLCanvasElement.prototype.getContext;
 HTMLCanvasElement.prototype.getContext=function(...args){const c=get.apply(this,args);if(c&&String(args[0]).includes('webgl')){const e=c.getExtension('WEBGL_debug_renderer_info');p.renderer.push({type:args[0],renderer:e?c.getParameter(e.UNMASKED_RENDERER_WEBGL):c.getParameter(c.RENDERER)})}return c};
 function frame(t){if(p.active&&p.last)p.frames.push(t-p.last);p.last=t;requestAnimationFrame(frame)}requestAnimationFrame(frame);
})();`;
function check(pass,name){checks.push({pass:!!pass,name});console.log(JSON.stringify(checks.at(-1)));if(!pass)throw Error(name)}
async function clickButton(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Missing action on '+s.screen);await session.click(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2)}
async function ready(){
 for(let n=0;n<240;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready && !!window.__fpsEngine?.ready && window.__lanternRenderReady === true'))return;await delay(500)}
 throw Error('Paired-build local QA/engine recorder unavailable');
}
async function settleMap(){
 let s;
 for(let n=0;n<240;n++){
  s=await session.game();
  const skip=s.buttons.find(b=>!b.disabled&&b.text.startsWith('SKIP'));
  if(s.screen==='STORY'&&skip){await clickButton(s,b=>b===skip);await delay(400);continue}
  if(s.map?.tutorial?.visible){const r=s.map.tutorial.continue;await session.click(r[0]+r[2]/2,r[1]+r[3]/2);await delay(300);continue}
  if(s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning&&!s.transition_loading.active)return s;
  await delay(400);
 }
 throw Error('Map not ready');
}
async function record(label,seconds,action){
 await session.evaluate(`window.__fpsBrowser.start(${JSON.stringify(label)});window.__fpsEngine.command('start',${JSON.stringify(label)});true`);
 const started=Date.now(); if(action)await action();
 while(Date.now()-started<seconds*1000){await delay(Math.min(5000,seconds*1000-(Date.now()-started)));console.log('Sampling '+label+' '+Math.round((Date.now()-started)/1000)+'s')}
 const browser=await session.evaluate('window.__fpsBrowser.stop()');
 const engine=await session.evaluate("window.__fpsEngine.command('stop'); window.__fpsEngine.result");
 check(engine?.count>30&&!engine.limit_reached,label+' captured actual engine frames');
 const capture={label,engine,browser};captures.push(capture);
 await writeFile(path.join(output,label+'_raw_frames.json'),JSON.stringify(capture));
 console.log(JSON.stringify({label,engine:stats(engine.frames.slice(1).map(f=>f[1])),browser:stats(browser.frames)}));
 return capture;
}
try{
 await mkdir(output,{recursive:true});
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:url.href,
  port:Number(port),width:1920,height:1080,initScript,profileGPU:mode==='map_profile'});
 await ready();
 const boot=await session.evaluate('window.__fpsBrowser.stop()');
 await writeFile(path.join(output,'bootstrap_browser_frames.json'),JSON.stringify(boot));
 check(boot.renderer.some(r=>/NVIDIA|RTX/i.test(r.renderer)),'hardware GPU renderer active');
 console.log(JSON.stringify({renderer:boot.renderer,bootstrap:stats(boot.frames)}));
 const backing=await session.evaluate("Array.from(document.querySelectorAll('canvas')).filter(c=>c.width>256).map(c=>[c.width,c.height])");
 check(backing.some(s=>s[0]===1920&&s[1]===1080),'actual GPU canvas backing is 1920x1080');
 if(mode!=='combat'&&mode!=='boss'){
  await session.game('prepare_fresh_first_map');let s=await settleMap();
  check(s.layout.size[0]===1920&&s.layout.size[1]===1080,'actual game viewport is 1920x1080');
  await session.screenshot('map_1080p_before');
  await record('map_idle',20);
  for(let i=0;i<(mode==='map_profile'?1:3);i++){
   s=await settleMap();
   const [q,r]=s.map.position, distance=c=>Math.max(Math.abs(c[0]-q),Math.abs(c[1]-r),Math.abs(c[0]+c[1]-q-r));
   const bounds=s.map.viewport_rect;
   const target=s.map.terrain_samples.filter(t=>t.reachable&&!t.blocked&&distance(t.coord)>0&&distance(t.coord)<=2&&
     t.screen[0]>bounds[0]+30&&t.screen[0]<bounds[0]+bounds[2]-30&&t.screen[1]>bounds[1]+60&&t.screen[1]<bounds[1]+bounds[3]-60)
     .sort((a,b)=>distance(b.coord)-distance(a.coord))[0];
   check(target,'reachable real movement target '+i);
   const prior=s.map.position.join(',');
   await record('map_move_'+i,10,async()=>{await session.click(...target.screen);await delay(150);await session.click(...target.screen,{clickCount:2})});
   s=await session.game();
   check(s.map?.position.join(',')!==prior,'real player movement committed '+i);
   if(s.screen!=='STAGE_SELECT')break;
  }
  await session.screenshot('map_1080p_after');
 }
 if(mode!=='map'&&mode!=='map_profile'){
  for(const stage of (mode==='boss'?['CH01-N20']:['CH01-N05','CH01-N20'])){
   await session.game('prepare_stage_contact',{stage_id:stage,campaign_flow:true});let s=await settleMap();
   check(s.map.player_rules,'ordinary rules before '+stage);
   await clickButton(s,b=>b.text==='다음 조우');
   for(let n=0;n<40;n++){s=await session.game();if(s.buttons.some(b=>!b.disabled&&b.text.includes('칸 이동')))break;await delay(200)}
   await clickButton(s,b=>b.text.includes('칸 이동'));
   for(let n=0;n<240;n++){
    s=await session.game();
    if(s.buttons.some(b=>!b.disabled&&b.text.startsWith('건너뛰기'))){await clickButton(s,b=>b.text.startsWith('건너뛰기'));await delay(250);continue}
    if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled)){await clickButton(s,b=>b.name==='EventDialogueNext');await delay(250);continue}
    if(s.battle?.ready&&!s.transition_loading.active){
     const deploy=s.buttons.find(b=>!b.disabled&&b.text==='전투 개시');if(deploy)await clickButton(s,b=>b===deploy);
     break;
    }
    await delay(300);
   }
   check(s.battle?.ready,'combat loaded '+stage);
   await session.screenshot('battle_'+stage+'_1080_before');
   const capture=await record('combat_'+stage,scenes==='wave-scenes'&&stage==='CH01-N20'?60:45);
   s=await session.game();
   const fieldSkip=s.buttons.find(b=>!b.disabled&&b.name==='FieldSceneSkip');
   if(stage==='CH01-N20'&&fieldSkip){
    await record('combat_'+stage+'_exit',8,()=>clickButton(s,b=>b===fieldSkip));
    s=await session.game();
   }
   await session.screenshot('after_'+stage);
   check(s.restart_progress.first_clear[stage],'natural AUTO victory '+stage);
   check(capture.engine.frames.some(f=>f[2].startsWith('BATTLE')&&f[2].includes('WAVE:2')),'second wave observed '+stage);
   if(scenes==='wave-scenes')check(capture.engine.frames.some(f=>f[2].includes('WAVE_TRANSITION')),'ordinary wave scene included in scored samples '+stage);
   if(stage==='CH01-N20')check(capture.engine.frames.some(f=>f[2].includes('BOSS_ENTRY')),'boss entrance included in gameplay samples');
  }
 }
 if(mode==='map_profile')await writeFile(path.join(output,'gpu_profile.json'),JSON.stringify(await session.evaluate('window.__localGPUProfile'),null,2));
 if(warmup==='verify-map-warmup'){
  const completed=session.logs(10000).filter(e=>e.text.startsWith('WEB_MAP_WARMUP_COMPLETE'));
  check(completed.length===1,'map pipelines initialized exactly once across first entry and later encounters');
  check(await session.evaluate('window.__lanternRenderReady === true && !document.getElementById("lantern-render-loading")'),'map loading never reinstates the startup input gate');
  console.log(JSON.stringify({map_pipeline_warmup:completed}));
 }
 const errors=session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text));
 check(errors.length===0,'no engine/browser console errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.screenshot('failure').catch(()=>{});process.exitCode=1}
finally{
 const groups=summarizeCaptures(captures);
 const acceptance=performanceAcceptance(groups,mode,scenes==='wave-scenes');
 const summary={resolution:[1920,1080],method:'1% low = 1000 / arithmetic mean of slowest ceil(frame_count * 0.01) actual engine frame intervals',
  scope:'Fresh sandbox save; physical map movement and ordinary-rule AUTO CH01-N05/N20 with legal geared level60 party. No forced victory, invincibility, held renderer, video recording, screenshots or state polling during scored captures. Loading is tagged separately. First partial interval excluded; all subsequent slow gameplay frames retained.',
  checks,groups,acceptance};
 await writeFile(path.join(output,'fps_summary.json'),JSON.stringify(summary,null,2));
 console.log(JSON.stringify({acceptance,checks}));await session.close();
 if(gate==='require-fps'&&!acceptance.pass)process.exitCode=1;
}
