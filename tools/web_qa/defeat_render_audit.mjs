import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9460']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(ok,name){checks.push({pass:!!ok,name});if(!ok)throw Error(name);}
async function tap(s,predicate){
  const b=s.buttons.find(b=>!b.disabled&&b.rect[0]>=0&&b.rect[1]>=0&&b.rect[0]+b.rect[2]<=1281&&b.rect[1]+b.rect[3]<=721&&predicate(b));
  if(!b)throw Error('Visible action unavailable');
  await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1280,height:720});
  for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
  await session.game('prepare_contact',{stage_number:1,invincible:true});
  let ready=false;
  for(let n=0;n<250;n++){
    const s=await session.game();
    if(s.battle?.ready){ready=true;break;}
    if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled)){await tap(s,b=>b.name==='EventDialogueNext');continue;}
    if(s.screen==='STORY'){await tap(s,b=>b.text==='다음');continue;}
    if(s.buttons.some(b=>b.text==='안내 건너뛰기')){await tap(s,b=>b.text==='안내 건너뛰기');continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready&&!s.map?.moving){
      if(s.buttons.some(b=>b.text.includes('1칸 이동')&&!b.disabled))await tap(s,b=>b.text.includes('1칸 이동'));
      else if(s.buttons.some(b=>b.text==='다음 조우'&&!b.disabled))await tap(s,b=>b.text==='다음 조우');
    }
    await delay(400);
  }
  check(ready,'real map contact loads battle');
  for(const [index,ids] of [['starting',['CHR001','CHR002','CHR003','CHR004','CHR005']],['alternate',['CHR006','CHR007','CHR008','CHR004','CHR005']]]){
    await session.game('defeat_fixture',{ids,elapsed:.30});await delay(300);
    const s=await session.game();
    await session.checkpoint(`${index}_prone_and_explosion`);
    for(const id of ids){const a=s.battle.actors.find(a=>a.id===id);check(a?.hp===0&&a?.down_pose?.width===512&&a?.down_pose?.height===512,`${id} exported SD prone texture renders at 512px`);}
    check(s.battle.enemy_defeat_bursts>0,'mob and boss destruction visible');
    await session.game('defeat_fixture',{ids,elapsed:1.2});await delay(300);
    const expired=await session.game();
    check(expired.battle.enemy_defeat_bursts===0,'mob and boss destruction retires completely');
    await session.checkpoint(`${index}_prone_enemies_gone`);
  }
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'no runtime or asset errors');
}catch(error){checks.push({pass:false,name:String(error)});await session.checkpoint('failure').catch(()=>{});process.exitCode=1;console.error(error);}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,scope:'Real map-to-battle transition, then held developer-only defeat renderer; does not claim natural combat deaths.'},null,2));}
