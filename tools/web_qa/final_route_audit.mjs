import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9258'] = process.argv.slice(2);
const session = new GameplaySession(output);
const checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(value,name){checks.push({name,pass:!!value}); console.log(JSON.stringify(checks.at(-1))); if(!value)throw Error(name);}
async function state(){return session.game();}
async function tapText(text){const s=await state();const b=s.buttons.find(b=>b.text===text&&!b.disabled&&b.rect[1]>=0&&b.rect[1]+b.rect[3]<=session.viewport.height+1);if(!b)throw Error('Visible button missing: '+text);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(350);}
async function waitScreen(screen,seconds=30){for(let n=0;n<seconds*2;n++){const s=await state();if(s.screen===screen)return s;await delay(500);}throw Error('Screen timeout: '+screen);}
async function waitMapReady(seconds=60){for(let n=0;n<seconds*2;n++){const s=await state();if(s.screen==='STAGE_SELECT'&&s.map?.ready)return s;await delay(500);}throw Error('Map initialization timeout');}
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  await session.game('prepare_contact',{stage_number:20,invincible:true});
  await delay(1000);
  if((await state()).screen==='STORY')await tapText('SKIP  ▶');
  await waitScreen('STAGE_SELECT');
  await waitMapReady();
  let s=await state();
  if(s.buttons.some(b=>b.text==='안내 건너뛰기'))await tapText('안내 건너뛰기');
  await session.mark('final_n20_map');
  await session.checkpoint('01_n20_map');
  s=await state();check(s.map.backdrop.present&&s.map.backdrop.instances>0,'continuous backdrop loaded at N20');
  if(!s.buttons.some(b=>b.text==='조우 방향 · 1칸 이동'))await tapText('다음 조우');
  await session.mark('final_n20_battle');
  await tapText('조우 방향 · 1칸 이동');
  await waitScreen('BATTLE',30);
  let wave=0,sawBoss=false;
  for(let n=0;n<180;n++){
    s=await state(); if(s.screen==='RESULT')break;
    if(!s.battle && s.buttons.some(b=>b.text==='RETRY')){await session.checkpoint('entry_failure');throw Error('Real battle entry returned its loading-failure screen');}
    if(s.battle){
      if(s.battle.ready && s.battle.wave!==wave){wave=s.battle.wave;checkFullDensity(s,check);await session.checkpoint('02_wave_'+wave);console.log('BATTLE_WAVE '+wave);}
      if(s.battle.signature?.resident_actor_ids.includes('BOSS001')){
        sawBoss=true;
        check(s.battle.signature.face_crop_resident_bytes>0,'HUD face texture accounting survives boss-wave rollover');
        await session.checkpoint('03_hd_boss_and_orbs');
        break;
      }
    }
    await delay(1000);
  }
  check(sawBoss,'actual N20 boss HD lease acquired');
  if(process.argv.includes('--grounding')){
    await session.mark('grounding_orientation_live');
    check(!(await state()).battle.paused,'grounding rotation starts from a live real boss battle');
    for(const [width,height] of [[360,640],[390,844],[1280,720]]){
      await session.resize(width,height);await delay(700);
      const grounded=await state();
      check(grounded.battle.actors.every(a=>Math.abs(a.ground_contact?.contact_error??Infinity)<.001),`all actor contacts stay grounded at ${width}x${height}`);
      check(grounded.buttons.filter(b=>b.name.startsWith('BattleUltimateOrb_')).length===5&&grounded.buttons.filter(b=>b.name.startsWith('BattleUltimateOrb_')).every(b=>b.rect[0]>=-1&&b.rect[1]>=-1&&b.rect[0]+b.rect[2]<=width+1&&b.rect[1]+b.rect[3]<=height+1),`all five face orbs remain entirely visible at ${width}x${height}`);
      await session.checkpoint(`grounded_boss_${width}x${height}`);
    }
    await session.resize(390,844);await delay(500);
    check(!(await state()).battle.paused,'boss battle stays active through ground/portrait/landscape review');
    await session.mark('grounding_battle_steady');
  }
  s=await waitScreen('RESULT',120);
  check(s.result?.victory,'N20 result is an actual victory, not merely a result screen');
  await session.mark('final_reward');
  await session.checkpoint('04_result');
  const oldScroll=s.scrolls[0]?.value??0;
  await session.swipe(214,570,270,650);await delay(150);
  check((await state()).scrolls[0].value>oldScroll,'real reward touch drag reaches lower report');
  await session.checkpoint('05_result_scrolled');
  await tapText('챕터 맵으로');
  for(let n=0;n<12&&(await state()).screen==='STORY';n++){await delay(600);await tapText('다음');}
  await waitScreen('STAGE_SELECT',30);
  s=await waitMapReady();
  check(s.map.next==='CH01-H01','post-N20 reveal automatically guides toward the pending HARD route');
  await tapText('일반');
  s=await state();
  check(!s.map.next,'completed NORMAL route no longer points back to N01');
  await session.checkpoint('06_normal_complete');
  await tapText('위험 작전으로');
  s=await state();check(s.map.next==='CH01-H01','completion action selects pending HARD route');
  await session.mark('final_hard_map');
  await session.checkpoint('07_hard_route');
  const mapInstance=s.map.instance_id;
  await session.resize(360,800);await delay(800);await session.checkpoint('08_map_360');
  await session.resize(1280,720);await delay(800);await session.checkpoint('09_map_landscape');
  s=await state();
  check(s.map.instance_id===mapInstance,'rotation preserves the live map instance');
  check(s.map.viewport_rect[3]>720*.62&&s.map.viewport_rect[1]<720*.35,'landscape map is not compressed below oversized portrait controls');
  check(s.buttons.filter(b=>['‹ 뒤로','파티 편성','목록형 접근성'].includes(b.text)).every(b=>b.rect[3]<72),'landscape header and optional map buttons release portrait size floors');
  await session.mark('intentional_browser_suspend');
  await session.send('Page.setWebLifecycleState',{state:'frozen'});await delay(1500);
  await session.send('Page.setWebLifecycleState',{state:'active'});await delay(1000);
  await session.mark('resume_check');
  s=await state();check(s.map.ready&&!s.map.paused,'map remains ready and unpaused after browser suspend/resume');
  await session.resize(390,844);await delay(800);await session.checkpoint('10_map_return_portrait');
  await session.mark('final_map_steady');await delay(10000);
  const errors=session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:'));
  check(errors.length===0,'no Godot script errors or warnings during final gameplay');
  s=await state();check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,'all gameplay used isolated QA saves');
} catch(error){checks.push({name:String(error),pass:false});console.error(error);process.exitCode=1;}
finally {await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,fixture:'Local QA N20 neighbor with invincibility; prior history grants no rewards. Real movement/combat/reward actions.'},null,2));}
