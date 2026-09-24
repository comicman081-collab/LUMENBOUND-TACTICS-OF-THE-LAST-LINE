import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output,url,port='9430']=process.argv.slice(2);
const session=new GameplaySession(output), checks=[], captures=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const check=(ok,name,detail)=>{checks.push({ok,name,detail});if(!ok)console.log('FAIL',name,JSON.stringify(detail));};
async function capture(name) {
  await delay(450);
  const s=await session.game();
  await session.screenshot(name);
  const [w,h]=s.layout.size;
  for(const p of s.panels??[]) {
    const [x,y,pw,ph]=p.rect;
    check(x>=-1&&y>=-1&&x+pw<=w+1&&y+ph<=h+1,`${name}: ${p.name} contained`,p.rect);
  }
  for(const b of s.buttons.filter(b=>b.nowrap&&!b.disabled&&b.rect[1]>=0&&b.rect[1]+b.rect[3]<=h)) {
    check(b.text_width<=b.content_width+1,`${name}: button text fits ${b.name}`,b);
    if(b.name==='ScreenBackButton')check(b.rect[2]<=w*.20,`${name}: back button leaves title space`,b.rect);
  }
  captures.push({name,screen:s.screen,panels:s.panels,labels:s.labels,buttons:s.buttons,sandbox:s.sandbox});
  console.log('CAPTURE',name,s.screen);
  return s;
}
async function press(b){if(!b)throw Error('Required control missing');await session.click(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function readyMap() {
  for(let n=0;n<180;n++) {
    const s=await session.game();
    if(s.screen==='STORY') {
      const skip=s.buttons.find(b=>b.name==='StorySkipButton'||b.name==='PrologueSkipButton');
      if(skip)await press(skip);
    }
    const guide=s.buttons.find(b=>b.text==='안내 건너뛰기');
    if(guide){await press(guide);continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready&&!s.transition_loading.active)return s;
    await delay(250);
  }
  throw Error('Map failed to become ready');
}
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:634,height:357});
  for(let n=0;n<150;n++) {if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(500);}
  for(const [w,h] of [[634,357],[1280,720],[1920,1080]]) {
    await session.resize(w,h);
    await delay(700);
    for(const screen of ['TITLE','HOME','ROSTER','GROWTH','FORMATION','INVENTORY','SETTINGS','ARCHIVE','RELAY']) {
      await session.game('presentation_screen',{screen});
      await capture(`${w}_${screen.toLowerCase()}`);
    }
    for(const kind of ['REWARD','LOADING','RESULT']) {
      await session.game('layout_fixture',{kind});
      await capture(`${w}_${kind.toLowerCase()}`);
    }
  }
  await session.resize(634,357);
  await session.game('prepare_growth',{mode:'funded'});
  let s=await capture('634_growth_funded');
  await press(s.buttons.find(b=>b.text==='+5'));
  s=await capture('634_growth_lv7_preview');
  await press(s.buttons.find(b=>b.name==='GrowthLevelApply'));
  s=await capture('634_growth_lv7_applied');
  check(s.growth.progress.level===7,'target level 7 applied',s.growth.progress);
  check(s.growth.inventory.CREDIT===498950&&s.growth.inventory.TRAINING_NOTE_S===4999&&s.growth.inventory.TRAINING_NOTE_M===4997,'exact automatic material spend',s.growth.inventory);
  for(const stage of [1,2]) {
    await session.game('prepare_contact',{stage_number:stage,invincible:true});
    s=await readyMap();
    await capture(`634_map_before_n${stage}`);
    let move=s.buttons.find(b=>b.text.includes('1칸 이동')&&!b.disabled);
    if(!move){await press(s.buttons.find(b=>b.text==='다음 조우'));await delay(300);s=await session.game();move=s.buttons.find(b=>b.text.includes('이동')&&b.text.includes('칸')&&!b.disabled);}
    await press(move);
    let reached=false;
    for(let n=0;n<150;n++) {
      s=await session.game();
      if(s.screen==='BATTLE'&&s.battle?.ready&&!s.transition_loading.active){
        const pause=s.buttons.find(b=>b.name==='BattlePauseButton');await press(pause);
        await capture(`634_battle_n${stage}_paused`);
        s=await session.game();await press(s.buttons.find(b=>b.text==='계속'));
        await capture(`634_battle_n${stage}_playing`);
        s=await session.game();await press(s.buttons.find(b=>b.name==='BattleSkipButton'));
        reached=true;break;
      }
      await delay(250);
    }
    check(reached,`N${stage} enemy contact reaches battle`);
    for(let n=0;n<120;n++){s=await session.game();if(s.screen==='RESULT'&&!s.transition_loading.active)break;await delay(250);}
    check(s.screen==='RESULT',`N${stage} battle reaches result`);
    await capture(`634_actual_result_n${stage}`);
    await press(s.buttons.find(b=>b.text==='지도로'));
    s=await readyMap();
    await capture(`634_cached_return_n${stage}`);
    check(!s.map.moving&&!s.map.turn_transitioning,`N${stage} cached map returns idle`,s.map);
    check(Object.values(s.sandbox).filter(v=>typeof v==='number').length>0&&s.sandbox.production_write_attempt_count===0,'real player save untouched',s.sandbox);
  }
} catch(error){check(false,'audit execution',String(error));console.error(error);}
finally {
  await session.close().catch(e=>console.error(e));
  const errors=session.logs(2000).filter(x=>/SCRIPT ERROR|^ERROR:|Parse Error/.test(x.text));
  check(errors.length===0,'no Godot runtime script errors',errors);
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,captures},null,2));
  console.log('LAYOUT_AUDIT',checks.filter(x=>x.ok).length,'/',checks.length);
  process.exitCode=checks.every(x=>x.ok)?0:1;
}
