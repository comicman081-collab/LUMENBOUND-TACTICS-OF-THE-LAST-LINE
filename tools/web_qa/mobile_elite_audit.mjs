import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9271']=process.argv.slice(2),session=new GameplaySession(output),checks=[];
const pause=ms=>new Promise(r=>setTimeout(r,ms)),state=()=>session.game();
const inside=r=>r[0]>=0&&r[1]>=0&&r[0]+r[2]<=session.viewport.width+1&&r[1]+r[3]<=session.viewport.height+1;
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
async function wait(test,seconds=120){for(let n=0;n<seconds*2;n++){const s=await state();if(test(s))return s;await pause(500);}throw Error('Elite audit state timeout');}
async function tap(test){const s=await state(),b=s.buttons.find(b=>test(b)&&!b.disabled&&inside(b.rect));if(!b)throw Error('Elite audit visible action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await pause(500);}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:360,height:640});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await pause(1000);}
  await session.game('prepare_home_tutorial');await wait(s=>s.modals?.some(m=>m.name==='HomeFirstOperationTutorial'));
  for(const dimensions of [[360,640],[800,360],[390,844]]){
    await session.resize(...dimensions);await pause(1400);
    const s=await state(),m=s.modals.find(m=>m.name==='HomeFirstOperationTutorial');
    check(m&&inside(m.rect),`home briefing bounded at ${dimensions.join('x')}`);
    check(m.labels.some(l=>l.text.includes('1 / 4')),'home rotation preserves the unread first page');
    for(const name of ['HomeTutorialSkipButton','HomeTutorialContinueButton'])check(s.buttons.some(b=>b.name===name&&inside(b.rect)),`${name} remains accessible after home rotation`);
    await session.checkpoint(`home_${dimensions.join('x')}`);
  }
  await tap(b=>b.name==='HomeTutorialSkipButton');
  await session.game('prepare_contact',{stage_number:10,invincible:true});
  for(let n=0;n<160;n++){const s=await state();if(s.screen==='STORY'){await tap(b=>b.name==='StorySkipButton');continue;}if(s.screen==='STAGE_SELECT'&&s.map?.ready)break;await pause(500);}
  let s=await state();if(s.buttons.some(b=>b.text==='안내 건너뛰기'))await tap(b=>b.text==='안내 건너뛰기');
  await session.resize(360,640);await pause(1000);
  s=await state();if(!s.buttons.some(b=>b.text.includes('1칸 이동')))await tap(b=>b.text==='다음 조우');
  await session.checkpoint('n10_before_contact');
  await tap(b=>b.text.includes('1칸 이동'));
  await wait(s=>s.screen==='BATTLE'&&s.battle?.ready);
  check(!(await state()).modals.length,'second authored ELITE N10 enters battle without an orphaned tutorial/modal');
  await session.checkpoint('n10_combat');await tap(b=>b.name==='BattleSpeedButton');
  const result=await wait(s=>s.screen==='RESULT',150);check(result.result.victory,'N10 real combat reaches victory in short portrait');
  await session.checkpoint('n10_victory');await tap(b=>b.text==='챕터 맵으로');
  s=await wait(s=>s.screen==='STAGE_SELECT'&&s.map?.ready);check(s.map.next==='CH01-N11','N10 victory connects to N11');
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'home rotation and N10 progression emit no Godot errors/warnings');
  check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,'elite audit remains in isolated saves');
}catch(e){checks.push({name:String(e),pass:false});console.error(e);process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,fixture:'Local sandbox; actual short-portrait N10 battle and home tutorial rotation. Not a physical device test.'},null,2));}
