import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9491']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],runs=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name){checks.push({pass:!!ok,name});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function boot(){for(let i=0;i<120;i++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))return;await delay(1000);}throw Error('Boot timeout');}
async function finishScenes(){
  const scenes=[];
  for(let i=0;i<180;i++){
    const s=await session.game();
    if(s.screen==='STORY'){
      if(!scenes.includes(s.story.scenario)){scenes.push(s.story.scenario);await session.checkpoint(s.story.scenario);}
      const next=s.buttons.find(b=>b.text==='다음'&&!b.disabled);
      if(next)await session.tap(next.rect[0]+next.rect[2]/2,next.rect[1]+next.rect[3]/2);
    }else if(s.map?.ready){return {scenes,state:s};}
    await delay(350);
  }
  throw Error('Story-to-map timeout');
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  await boot();
  for(const chapter of [1,2]){
    await session.game('prepare_story_gap',{chapter_number:chapter});
    const result=await finishScenes();
    const expected=chapter===1?['SCN_CH01_MID_A','SCN_CH01_MID_B','SCN_CH01_MID_C']:['SCN_CH02_MID_A'];
    check(JSON.stringify(result.scenes)===JSON.stringify(expected),`CH${chapter} missing optional-branch scenes play in order`);
    check(result.state.story_shards===expected.length*5,`CH${chapter} story rewards granted once`);
    check(result.state.pending_story.length===0&&result.state.map.persistent_grid_drawn>0,`CH${chapter} returns to the map with no stale story queue`);
    check(result.state.region_resume_stage===(chapter===1?'CH01-N10':'CH02-N06'),`CH${chapter} region entry advances to the next mandatory operation`);
    await session.evaluate('setTimeout(()=>location.reload(),0); true');await delay(1500);await boot();
    await session.game('prepare_region',{chapter_number:chapter});
    const restored=await finishScenes();
    check(restored.scenes.length===0,`CH${chapter} reload does not replay completed scenes`);
    check(restored.state.story_shards===result.state.story_shards,`CH${chapter} reload cannot duplicate story rewards`);
    check(restored.state.sandbox.production_read_attempt_count===0&&restored.state.sandbox.production_write_attempt_count===0,'isolated saves only');
    runs.push({chapter,scenes:result.scenes,reward_shards:result.state.story_shards,restored_shards:restored.state.story_shards});
  }
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'no runtime or shader warnings');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,runs,scope:'Isolated first-clear fixtures; actual story controls, rewards, browser reload and map return. Not actual combat clears.'},null,2));}
