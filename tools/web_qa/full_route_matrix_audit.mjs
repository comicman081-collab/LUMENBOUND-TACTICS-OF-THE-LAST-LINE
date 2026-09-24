import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output,url,port='9365'] = process.argv.slice(2);
const stageArgument=process.argv.find(v=>v.startsWith('--stages='));
const stages=stageArgument?stageArgument.slice(9).split(',').map(Number):Array.from({length:20},(_,i)=>i+1);
if(stages.some(n=>!Number.isInteger(n)||n<1||n>20))throw Error('Invalid stage');
const session=new GameplaySession(output), checks=[], results=[], motion=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const state=()=>session.game();
const contained=r=>r[0]>=-1&&r[1]>=-1&&r[0]+r[2]<=session.viewport.width+1&&r[1]+r[3]<=session.viewport.height+1;
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
async function persist(){await writeFile(path.join(output,'route_progress.json'),JSON.stringify({checks,results,motion},null,2));}
async function tapFrom(s,predicate){const b=s.buttons.find(b=>predicate(b)&&!b.disabled&&contained(b.rect));if(!b)throw Error('Visible route action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(450);}
async function ensureMoveAction(s){
  if(s.buttons.some(b=>b.text.includes('1칸 이동')&&!b.disabled&&contained(b.rect)))return s;
  // On a streamed district boundary the selection ring/button can settle a few
  // frames after the encounter button has accepted the touch.  Waiting for the
  // actual actionable control keeps the audit from mistaking render latency for
  // a route dead end. A browser touch can also land during the streamed map's
  // final input-suppression frame, so retry the visible button just as a player
  // naturally would; still fail after three accepted-looking attempts.
  for(let attempt=0;attempt<3;attempt++){
    s=await state();
    await tapFrom(s,b=>b.text==='다음 조우');
    for(let n=0;n<40;n++){
      s=await state();
      if(s.buttons.some(b=>b.text.includes('1칸 이동')&&!b.disabled&&contained(b.rect)))return s;
      await delay(250);
    }
  }
  throw Error('Move action did not become visible after three next-encounter touches');
}
async function settleMap(expected){
  for(let n=0;n<140;n++){
    const s=await state();
    if(s.screen==='STORY'){await tapFrom(s,b=>b.name==='StoryNextButton'||b.text==='다음');continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready){
      const tutorial=s.buttons.find(b=>b.text==='안내 건너뛰기'&&!b.disabled);
      if(tutorial){await tapFrom(s,b=>b===tutorial);continue;}
      if(expected)check(s.map.next===expected,`real result transition selects ${expected}`);
      return s;
    }
    await delay(500);
  }
  throw Error('Route map did not settle');
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  for(const stage of stages){
    const label=`n${String(stage).padStart(2,'0')}`;
    await session.resize(stage%3===0?360:390,stage%3===0?640:844);
    await session.mark(`${label}_map_loading`);
    await session.game('prepare_contact',{stage_number:stage,invincible:true});
    let s=await settleMap();
    check(s.map.backdrop.present&&s.map.backdrop.instances>0,`${label} continuous map background`);
    check(s.map.pawn_texture.width===192,`${label} actual high-density map pawn`);
    check(s.map.terrain_samples.filter(t=>t.type==='SHALLOW_WATER').every(t=>t.blocked&&!t.reachable),`${label} water excluded from walk range`);
    await session.checkpoint(`${label}_01_map`);
    s=await ensureMoveAction(s);
    await tapFrom(s,b=>b.text.includes('1칸 이동'));
    const entered=Date.now(); let checkedWave=0, enteredReady=false, result=null;
    await session.mark(`${label}_battle_loading`);
    for(let sample=0;Date.now()-entered<240000;sample++){
      s=await state();
      const dialog=s.modals?.find(m=>m.name==='PreBattleEventDialog');
      if(dialog){
        check(contained(dialog.rect),`${label} briefing fits ${session.viewport.width}x${session.viewport.height}`);
        const next=s.buttons.find(b=>b.name==='EventDialogueNext');
        check(next&&contained(next.rect),`${label} briefing next button visible`);
        await session.checkpoint(`${label}_briefing_${sample}`);
        await tapFrom(s,b=>b.name==='EventDialogueNext'); continue;
      }
      if(s.screen==='STORY'){await tapFrom(s,b=>b.text==='다음');continue;}
      if(s.buttons.some(b=>b.text==='RETRY'))throw Error(`${label} real battle entry failed`);
      if(s.battle?.ready){
        if(s.battle.wave!==checkedWave){
          checkedWave=s.battle.wave; checkFullDensity(s,check);
          await session.checkpoint(`${label}_02_wave${checkedWave}`);
        }
        if(!enteredReady){enteredReady=true;await session.mark(`${label}_combat`);await tapFrom(s,b=>b.name==='BattleSpeedButton');}
        if(motion.length<1000&&sample%2===0)motion.push({stage,at:Date.now(),actors:s.battle.actors.map(a=>({id:a.id,hp:a.hp,track:a.motion_track}))});
      }
      if(s.screen==='RESULT'){result=s;break;}
      await delay(600);
    }
    check(enteredReady,`${label} entered real battle`);
    check(result?.result?.victory,`${label} actual combat victory`);
    await session.mark(`${label}_reward`);
    await session.checkpoint(`${label}_03_reward`);
    const scroll=result.scrolls.find(r=>r.max>r.page+4&&contained(r.rect));
    if(scroll){await session.swipe(scroll.rect[0]+scroll.rect[2]/2,scroll.rect[1]+scroll.rect[3]-25,scroll.rect[1]+25,600);check((await state()).scrolls.find(r=>r.name===scroll.name).value>scroll.value,`${label} real touch reaches lower reward report`);}
    s=await state();await tapFrom(s,b=>b.text==='챕터 맵으로');
    const next=stage===20?'CH01-H01':`CH01-N${String(stage+1).padStart(2,'0')}`;
    s=await settleMap(next);
    check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,`${label} isolated QA save only`);
    check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,`${label} no runtime/script/shader warnings`);
    results.push({stage,waves:checkedWave,victory:true,next,duration_ms:Date.now()-entered});
    await session.checkpoint(`${label}_04_next`);await persist();
    console.log(`ROUTE_MATRIX_COMPLETE ${stage}/20`);
  }
}catch(error){checks.push({name:String(error),pass:false});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await persist();await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,results,fixture:'Each stage starts from a reward-free local neighbor fixture with invincibility; actual touch contact, briefing, battle, reward and next-stage transition. Not an unmodified balance run or physical-phone test.'},null,2));}
