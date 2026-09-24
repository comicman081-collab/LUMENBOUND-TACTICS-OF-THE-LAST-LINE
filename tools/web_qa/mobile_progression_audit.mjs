import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9260']=process.argv.slice(2);
const session=new GameplaySession(output), checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const state=()=>session.game();
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
async function tapButton(predicate){
 for(let n=0;n<24;n++){
  const s=await state(),b=s.buttons.find(b=>predicate(b)&&!b.disabled);
  if(!b)throw Error('Progression button missing');
  const top=s.scrolls?.[0]?.rect[1]||0,bottom=session.viewport.height-5;
  if(b.rect[1]>=top&&b.rect[1]+b.rect[3]<=bottom){await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(350);return;}
  const down=b.rect[1]>=bottom||b.rect[1]+b.rect[3]>bottom;
  await session.swipe(session.viewport.width*.85,down?bottom-20:top+20,down?top+20:bottom-20,350);await delay(150);
 }
 throw Error('Progression control is unreachable by scrolling');
}
const tapText=text=>tapButton(b=>b.text===text);
async function waitFor(predicate,seconds=90){for(let n=0;n<seconds*2;n++){const s=await state();if(predicate(s))return s;await delay(500);}throw Error('Progression state timeout');}
async function battle(stage){
  await session.mark(`n${stage}_loading`);
  await session.game('prepare_contact',{stage_number:stage,invincible:true});
  for(let n=0;n<120;n++){
    const s=await state();
    if(s.screen==='STORY'){await tapText('SKIP  ▶');continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready)break;
    await delay(500);
  }
  let s=await state();
  if(s.buttons.some(b=>b.text==='안내 건너뛰기'))await tapText('안내 건너뛰기');
  s=await state();
  if(!s.buttons.some(b=>b.text==='조우 방향 · 1칸 이동'))await tapText('다음 조우');
  await tapText('조우 방향 · 1칸 이동');
  await waitFor(s=>s.screen==='BATTLE',40);
  const ready=await waitFor(s=>s.screen==='BATTLE'&&s.battle?.ready,90);
  checkFullDensity(ready,check);
  await session.checkpoint(`n${stage}_hd_combat`);
  // Use the actual player's speed control, never force the simulation result.
  await tapButton(b=>b.name==='BattleSpeedButton');
  await session.mark(`n${stage}_combat`);
  const result=await waitFor(s=>s.screen==='RESULT',150);
  check(result.result.victory,`N${stage} actual combat ends in victory`);
  await session.checkpoint(`n${stage}_victory`);
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  await battle(1);
  await tapText('권장 파티 성장');
  let s=await waitFor(s=>s.screen==='GROWTH');
  await session.mark('growth_real_touch');
  await session.checkpoint('growth_top');
  const names=['마에루','로안','나린','에다','소렌'];
  const tabs=s.buttons.filter(b=>names.includes(b.text));
  check(tabs.length===5&&Math.max(...tabs.map(b=>b.rect[1]))-Math.min(...tabs.map(b=>b.rect[1]))<2,'five character tabs share one mobile row');
  const firstScroll=s.scrolls[0].value;
  await session.swipe(213,650,300,650);await delay(150);
  check((await state()).scrolls[0].value>firstScroll,'real finger drag scrolls growth content');
  for(let n=0;n<8&&(await state()).scrolls[0].value>0;n++){await session.swipe(213,300,690,500);await delay(100);}
  s=await state();const previousLevel=s.growth.progress.level,previousXP=s.growth.progress.xp;
  await tapButton(b=>b.name==='GrowthLevelApply');
  s=await state();check(s.growth.progress.level>previousLevel||s.growth.progress.xp>previousXP,'real training updates the selected character');
  await tapText('장비·돌파');s=await state();
  const equipment=s.buttons.find(b=>b.name.startsWith('MobileEquipmentOption_')&&!b.disabled);
  check(!!equipment,'an owned compatible alternate equipment choice is available');
  await tapButton(b=>b.name===equipment.name);
  s=await state();check(s.growth.progress.equipped_weapon_id===equipment.name.replace('MobileEquipmentOption_',''),'real equipment selection updates the character loadout');
  await session.checkpoint('growth_upgraded_and_equipped');
  await battle(5);
  await tapText('챕터 맵으로');
  s=await waitFor(s=>s.screen==='STORY',30);
  check(s.story.scenario==='SCN_CH01_MID_B','N05 reward opens the authored mid-boss story');
  await session.mark('n05_story');
  const pages=[];
  for(let page=1;page<=3;page++){
    // NEXT is a direct advance command, whereas touching the text box reveals
    // the current typewriter. Do not mistake NEXT for a reveal-only action.
    s=await waitFor(s=>s.screen==='STORY'&&s.story?.visible_ratio>=.999,12);
    check(s.story.scenario==='SCN_CH01_MID_B',`N05 page ${page} remains in the authored scenario`);
    check(s.story.content_height<=s.story.visible_height+1,`N05 page ${page} complete text fits its box`);
    pages.push(s.story.text);await session.checkpoint(`n05_story_page_${page}`);
    await tapText('다음');
  }
  check(new Set(pages).size===3,'N05 story advances through three distinct complete pages');
  s=await waitFor(s=>s.screen==='STAGE_SELECT'&&s.map?.ready,60);
  check(s.map.next==='CH01-N06','N05 story returns to the next normal encounter N06');
  await session.checkpoint('n06_available');
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'mobile progression has no Godot script errors or warnings');
  check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,'progression remains inside isolated QA saves');
}catch(error){checks.push({name:String(error),pass:false});console.error(error);process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,fixture:'Local reward-free N01/N05 neighbors with invincibility; actual 2x battle, UI and touch actions. Not physical-phone evidence.'},null,2));}
