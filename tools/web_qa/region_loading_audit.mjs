import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output,url,port='9395']=process.argv.slice(2);
const session=new GameplaySession(output), checks=[], maps=[], stories=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const contained=r=>r[0]>=-1&&r[1]>=-1&&r[0]+r[2]<=session.viewport.width+1&&r[1]+r[3]<=session.viewport.height+1;
function check(ok,name){checks.push({pass:!!ok,name});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&contained(b.rect)&&predicate(b));if(!b)throw Error('Visible action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(350);}
async function settle(chapter){
  for(let n=0;n<160;n++){
    const s=await session.game();
    if(s.screen==='STORY'){stories.push(s.story?.scenario);await tap(s,b=>b.text==='다음');continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready){
      if(s.buttons.some(b=>b.text==='안내 건너뛰기')){await tap(s,b=>b.text==='안내 건너뛰기');continue;}
      check(s.map.chapter===chapter,`${chapter} map is ready`);
      check(s.map.persistent_grid_cells>100&&s.map.persistent_grid_drawn>0,`${chapter} keeps a persistent map-wide cell grid`);
      check(s.map.natural_terrain&&s.map.natural_chunks>0,`${chapter} renders its Blender terrain`);
      check(s.map.natural_river_chunks>0&&s.map.environment_meshes.includes('canopy_alt')&&s.map.environment_meshes.includes('boulder'),`${chapter} renders the Blender river and natural grove kit`);
      if(chapter!=='CH01')check(s.map.status.startsWith(`제${Number(chapter.slice(2))}장`),`${chapter} HUD identifies the correct region`);
      check(s.density_cache.retained_bytes<=s.density_cache.budget_bytes,`${chapter} retained texture memory bounded`);
      return s;
    }
    if(s.buttons.some(b=>b.text==='RETRY'))throw Error('Map loading failed');
    await delay(350);
  }
  throw Error('Map did not settle');
}
async function travel(chapter){
  let s=await session.game();await tap(s,b=>['지역','지역 이동'].includes(b.text));s=await session.game();
  check(s.map.paused,'world pauses while region selector is open');
  await tap(s,b=>b.name===`Travel_${chapter}`);
  return settle(chapter);
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1280,height:720});
  for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
  await session.game('prepare_contact',{stage_number:1,invincible:true});
  let s=await settle('CH01');maps.push({label:'cold_ch01',state:s});
  await session.checkpoint('01_forest_landscape');
  await tap(s,b=>b.text==='지역 이동');s=await session.game();
  check(s.buttons.find(b=>b.name==='Travel_CH02')?.disabled,'unearned region is locked');
  await tap(s,b=>b.text==='닫기');s=await session.game();check(!s.map.paused,'closing region selector resumes world');
  await session.game('prepare_contact',{stage_number:1,invincible:true});s=await settle('CH01');maps.push({label:'warm_ch01',state:s});
  check(s.density_cache.misses===maps[0].state.density_cache.misses,'repeated entry performs no additional HD downloads or decoding');
  await session.resize(360,640);await delay(1200);s=await session.game();
  check(s.buttons.some(b=>b.text==='지역'&&contained(b.rect)),'region action fits 360px portrait');
  await tap(s,b=>b.text==='지역');await session.checkpoint('02_region_selector_portrait');s=await session.game();
  check(s.modals.some(m=>m.name==='RegionTravelOverlay'&&contained(m.rect)),'region modal fits portrait');
  await tap(s,b=>b.text==='닫기');
  await session.game('prepare_region',{chapter_number:2});s=await settle('CH02');maps.push({label:'ch02_ruins',state:s});
  await session.checkpoint('03_ruins_portrait');
  await travel('CH01');const storyCount=stories.length;await travel('CH02');
  check(stories.length===storyCount,'return to visited region does not repeat introduction');
  await session.resize(1280,720);await delay(1000);
  for(const number of [3,4,5,7,8,9,20]){
    const chapter=`CH${String(number).padStart(2,'0')}`;
    await session.game('prepare_region',{chapter_number:number});s=await settle(chapter);
    maps.push({label:chapter,state:s});await session.checkpoint(`${chapter}_${s.map.palette}`);
  }
  check(new Set(maps.map(m=>m.state.map.palette)).size===8,'all eight map environment families render');
  check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,'QA never accesses production saves');
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'no script, shader or runtime warnings');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,maps,stories:[...new Set(stories)],scope:'Local Chrome touch emulation; region fixtures unlock isolated saves only. Not a physical phone or balance run.'},null,2));}
