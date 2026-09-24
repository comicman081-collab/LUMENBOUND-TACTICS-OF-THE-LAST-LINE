import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,inputUrl,port='9455',width='936',height='526']=process.argv.slice(2);
const qaUrl=new URL(inputUrl);qaUrl.searchParams.set('gameplay-qa','1');qaUrl.searchParams.set('qa','chapter-boss-flow-20260912');
const url=qaUrl.href;
const session=new GameplaySession(output),checks=[],timeline=[],stories=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(value,name){checks.push({pass:!!value,name});if(!value)throw Error(name);}
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Missing action '+s.screen);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function settleMap(stage){for(let n=0;n<240;n++){const s=await session.game();if(s.screen==='STAGE_SELECT'&&s.stage===stage&&s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning&&!s.transition_loading.active)return s;await delay(300);}throw Error('Map timeout '+stage);}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:Number(width),height:Number(height)});
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 await session.game('prepare_stage_contact',{stage_id:'CH01-N20',campaign_flow:true});
 let s=await settleMap('CH01-N20');check(s.map.player_rules,'Release stamina and unlock rules active');
 await tap(s,b=>b.text==='다음 조우');await delay(400);s=await session.game();
 check(s.map.preview.length>=2,'Real adjacent map route');await tap(s,b=>b.text.includes('칸 이동'));
 let result=null,entryTick=null,entrySamples=0,seenDescent=false,seenLanding=false,seenVictory=false,finishedEntry=false;
 for(let n=0;n<700;n++){
  s=await session.game();
  if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled))await tap(s,b=>b.name==='EventDialogueNext');
  if(s.battle?.ready){
   const scene=s.battle.boss_scene;
   timeline.push({time:s.battle.time,wave:s.battle.wave,ended:s.battle.ended,scene});
   if(scene.entry_elapsed>=0){
    if(entryTick===null){entryTick=s.battle.time;await session.checkpoint('boss_aperture');}
    check(s.battle.time===entryTick,'No combat time consumed during entrance '+entrySamples++);
    if(scene.entry_elapsed>=1.1&&!seenDescent){seenDescent=true;await session.checkpoint('boss_descent');}
    if(scene.entry_elapsed>=2.0&&!seenLanding){seenLanding=true;await session.checkpoint('boss_landed_caption');}
   }else if(entryTick!==null&&!finishedEntry&&!s.battle.ended){finishedEntry=true;check(scene.arena&&scene.background_mix===1,'Boss arena retained after entrance');await session.checkpoint('boss_combat');}
   if(scene.victory_elapsed>=0&&!seenVictory){seenVictory=true;check(scene.arena&&scene.background_mix===1,'Boss arena retained throughout victory');await session.checkpoint('boss_victory');}
  }
  if(s.screen==='RESULT'&&!s.transition_loading.active){result=s;break;}
  await delay(100);
 }
 check(result!==null,'Actual simulation reached results without fast-forward');
 check(seenDescent&&seenLanding&&entrySamples>=2,'Observed animated descent and landing');
 check(seenVictory,'Observed boss victory exit');
 check(result.restart_progress.first_clear['CH01-N20'],'Real victory committed N20');
 check(result.chapter_progress.CH02.unlocked,'Victory opened chapter 2');
 check(result.chapter_progress.CH01.hard_unlocked,'Optional hard route retained');
 check(result.campaign_transition.to_stage==='CH02-N01','Persisted next-region handoff');
 await session.checkpoint('victory_next_chapter_action');
 await tap(result,b=>b.text.includes('제2장으로'));
 let next=null;
 for(let n=0;n<300;n++){
  s=await session.game();
  if(s.screen==='STORY'){
   if(!stories.includes(s.scenario)){stories.push(s.scenario);await session.checkpoint(s.scenario);}
   const skip=s.buttons.find(b=>!b.disabled&&/SKIP|건너뛰기/.test(b.text));
   if(skip)await tap(s,b=>b===skip);
   else if(s.buttons.some(b=>b.text==='다음'&&!b.disabled))await tap(s,b=>b.text==='다음');
  }
  if(s.screen==='STAGE_SELECT'&&s.stage==='CH02-N01'&&s.map?.ready&&!s.transition_loading.active){next=s;break;}
  await delay(350);
 }
 check(next!==null,'Result leads to interactive chapter 2 map');
 check(stories.includes('SCN_CH01_OUTRO')&&stories.includes('SCN_CH02_INTRO'),'Chapter 1 aftermath precedes chapter 2 introduction');
 check(stories.indexOf('SCN_CH01_OUTRO')<stories.indexOf('SCN_CH02_INTRO'),'Story order preserved');
 check(Object.keys(next.campaign_transition).length===0,'Handoff acknowledged once');
 check(next.map.player_rules&&!next.map.turn_transitioning,'Next map remains interactive under player rules');
 await session.checkpoint('chapter_2_arrival');
 await tap(next,b=>b.text==='다음 조우'||b.text==='탐색 방향');await delay(600);s=await session.game();
 check(s.map.preview.length>=2,'Chapter 2 provides a usable next encounter route');
 const errors=session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text));
 check(errors.length===0,'No browser or engine runtime errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,timeline,stories,scope:'Real contact and natural AUTO combat of CH01-N20 with an isolated geared level-60 party, Release resource rules, actual rewards/story/next-map flow; no forced victory or wave seek.'},null,2));}
