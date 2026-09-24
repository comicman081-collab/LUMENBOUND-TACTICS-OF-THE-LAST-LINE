import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9434']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name,detail){checks.push({ok,name,detail});console.log(ok?'PASS':'FAIL',name);}
const inside=(r,w=634,h=357)=>r&&r[0]>=-1&&r[1]>=-1&&r[0]+r[2]<=w+1&&r[1]+r[3]<=h+1;
async function press(b){if(!b)throw Error('Required button absent');await session.click(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function mapReady(){
  for(let n=0;n<150;n++){
    const s=await session.game();
    const skip=s.buttons.find(b=>['StorySkipButton','PrologueSkipButton'].includes(b.name));
    if(s.screen==='STORY'&&skip){await press(skip);continue;}
    const guide=s.buttons.find(b=>b.text==='안내 건너뛰기');
    if(guide){await press(guide);continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready&&!s.transition_loading.active)return s;
    await delay(300);
  }
  throw Error('Map readiness timeout');
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:634,height:357});
  for(let n=0;n<150&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
  await session.game('prepare_prologue');
  let s,choiceSeen=false;
  for(let n=0;n<70;n++){
    s=await session.game();
    if(s.screen!=='STORY'){await delay(300);continue;}
    check(inside(s.story.dialogue_rect),`prologue ${n}: dialogue inside canvas`,s.story.dialogue_rect);
    check(s.story.dialogue_rect[1]>90&&s.story.dialogue_rect[3]<357*.60,`prologue ${n}: reading panel leaves title and characters visible`,s.story.dialogue_rect);
    check(s.story.content_height<=s.story.visible_height+1,`prologue ${n}: reading text fits`,s.story);
    if(n===0)await session.screenshot('prologue_narration');
    const choice=s.buttons.find(b=>b.text.includes('불빛을 확인')||b.text.includes('기록 장치를'));
    if(choice){
      choiceSeen=true;
      check(s.buttons.filter(b=>b.text.includes('불빛을 확인')||b.text.includes('기록 장치를')).every(b=>inside(b.rect)),'all prologue choices remain inside canvas',s.buttons);
      await session.screenshot('prologue_choices');
      await press(choice);break;
    }
    const r=s.story.body_rect;
    await session.click(r[0]+r[2]/2,r[1]+Math.min(r[3]/2,20));
    await delay(300);
  }
  check(choiceSeen,'intro choice reached through dialogue input');
  await session.game('prepare_fresh_first_map');
  s=await mapReady();
  const mini=s.map.minimap;
  check(mini.explored_tiles.length>0&&mini.explored_tiles.length<mini.total_tiles*.3,'initial minimap contains only explored territory',mini);
  await session.screenshot('initial_map');
  const r=mini.rect,p=await session.inputPoint(r[0]+r[2]/2,r[1]+r[3]/2);
  for(const clickCount of [1,2]){await session.send('Input.dispatchMouseEvent',{type:'mousePressed',...p,button:'left',clickCount});await session.send('Input.dispatchMouseEvent',{type:'mouseReleased',...p,button:'left',clickCount});}
  await delay(350);s=await session.game();
  check(s.map.full_map_open,'double click opens full map');
  check(s.map.full_map?.explored_tiles.length===mini.explored_tiles.length,'full map retains exactly the same exploration fog',s.map.full_map);
  await session.screenshot('explored_full_map');
  const close=s.buttons.find(b=>b.text.includes('닫기'));if(close)await press(close);else await session.key('Escape','Escape',27);
  await session.game('prepare_treasure_contact');
  s=await mapReady();
  const treasure=s.map.treasures.find(t=>t.visible&&t.state!=='CLAIMED');
  if(!treasure)throw Error('Visible unclaimed treasure missing');
  await session.click(...treasure.screen);await delay(300);s=await session.game();
  const move=s.buttons.find(b=>b.text.includes('칸 이동')&&!b.disabled);await press(move);
  for(let n=0;n<70;n++){s=await session.game();if(s.buttons.some(b=>b.name==='MapRewardContinueButton'))break;await delay(250);}
  check(s.buttons.some(b=>b.name==='MapRewardContinueButton'),'treasure contact reaches reward overlay');
  check(s.map.treasures.find(t=>t.id===treasure.id)?.state==='CLAIMED'&&!s.map.treasures.find(t=>t.id===treasure.id)?.visible,'claimed reward is removed immediately',s.map.treasures);
  await session.screenshot('treasure_claimed_reward');
  await press(s.buttons.find(b=>b.name==='MapRewardContinueButton'));
  for(let n=0;n<60;n++){s=await session.game();if(!s.map.moving&&!s.map.turn_transitioning&&!s.map.paused)break;await delay(250);}
  check(!s.map.moving&&!s.map.turn_transitioning&&!s.map.paused,'treasure popup returns to interactive movement',s.map);
  await session.screenshot('treasure_resume');
}catch(error){check(false,'story/map audit execution',String(error));console.error(error);}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks},null,2));process.exitCode=checks.every(c=>c.ok)?0:1;}
