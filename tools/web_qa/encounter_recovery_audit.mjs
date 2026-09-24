import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9452']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],runs=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(ok,name){checks.push({pass:!!ok,name});if(!ok)throw Error(name);}
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function mapReady(){for(let n=0;n<200;n++){let s=await session.game();if(s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning)return s;if(s.screen==='STORY')await tap(s,b=>b.text==='다음');await delay(300);}throw Error('Map timeout');}
async function approach(){let s=await mapReady();check(s.map.player_rules,'Release entry rules active');if(s.buttons.some(b=>b.text==='위험 작전으로'&&!b.disabled)){await tap(s,b=>b.text==='위험 작전으로');await delay(400);s=await mapReady();}await tap(s,b=>b.text==='다음 조우');await delay(350);s=await session.game();check(s.map.preview.length>=2,'real contact route exists');await tap(s,b=>b.text.includes('칸 이동'));}
async function battleReady(stage){for(let n=0;n<180;n++){const s=await session.game();if(s.screen==='BATTLE'&&s.battle?.ready){check(s.stage===stage,stage+' correct battle entered');return s;}if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled))await tap(s,b=>b.name==='EventDialogueNext');await delay(300);}throw Error(stage+' battle timeout');}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:936,height:526});
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 for(const spec of [{stage_id:'CH01-N20',stamina:0},{stage_id:'CH01-H05',daily_exhausted:true},{stage_id:'CH02-N01',stamina:0}]){
  const fixture=await session.game('prepare_stage_contact',spec);check(!fixture.error,spec.stage_id+' fixture created');
  await approach();let s;
  for(let n=0;n<100;n++){s=await session.game();if(s.map?.ready&&!s.map.turn_transitioning&&!s.map.moving&&s.map.status.includes(spec.daily_exhausted?'횟수':'작전력 부족'))break;await delay(250);}
  check(s.screen==='STAGE_SELECT'&&!s.map.turn_transitioning&&!s.map.moving&&!s.map.paused,spec.stage_id+' rejection returns interactive map');
  check(Object.keys(s.map.pending_encounter).length===0,spec.stage_id+' rejected pending contact cleared');
  check(JSON.stringify(s.map.position)===JSON.stringify(fixture.neighbour),spec.stage_id+' returns to pre-contact tile');
  check(s.map.status.includes(spec.daily_exhausted?'횟수':'작전력 부족'),spec.stage_id+' visible entry reason');
  await session.checkpoint(spec.stage_id.replace('-','_')+'_rejected');
  await tap(s,b=>b.text==='대기');await delay(1400);s=await mapReady();check(!s.map.turn_transitioning,spec.stage_id+' wait still usable');
  runs.push({kind:'rejected',stage:spec.stage_id,map:s.map});
  if(spec.stage_id==='CH01-N20'){
   await session.game('restore_contact_stamina');await approach();s=await battleReady(spec.stage_id);
   await session.checkpoint('CH01_N20_recovered_battle');runs.push({kind:'retry',stage:spec.stage_id,actors:s.battle.actors});
  }
 }
 for(const stage of ['CH01-N04','CH01-N20','CH01-H05','CH02-N20','CH03-H05','CH10-N20','CH20-N20']){
  await session.game('prepare_stage_contact',{stage_id:stage});await approach();const s=await battleReady(stage);
  check(s.battle.actors.some(a=>a.team==='ENEMY'),stage+' real enemies loaded');
  await session.checkpoint(stage.replace('-','_')+'_battle');runs.push({kind:'success',stage,actors:s.battle.actors});
  console.log('CONTACT_PASS',stage);
 }
 check(session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text)).length===0,'no runtime errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,runs,scope:'Actual browser map movement/contact with Release entry rules in an isolated developer save; covers rejection, input recovery and retry, not all-stage battle victories.'},null,2));}
