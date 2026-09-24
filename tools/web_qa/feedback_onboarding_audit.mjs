import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9444']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const check=(ok,name,detail)=>{checks.push({ok,name,detail});console.log(ok?'PASS':'FAIL',name);};
async function press(b){if(!b)throw Error('Required button absent');await session.click(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(600);}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:634,height:357});
  for(let n=0;n<150&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
  for(const [w,h] of [[634,357],[1280,720]]){
    await session.resize(w,h);await delay(700);
    await session.game('prepare_home_tutorial',{fresh:true});
    for(let step=1;step<=4;step++){
      await delay(400);const s=await session.game();await session.screenshot(`${w}_home_guide_${step}`);
      const b=s.buttons.find(b=>b.name==='HomeTutorialContinueButton');
      check(b&&b.rect[0]>=0&&b.rect[1]>=0&&b.rect[0]+b.rect[2]<=w+1&&b.rect[1]+b.rect[3]<=h+1,`${w}: home guide ${step} action contained`,b);
      await press(b);
    }
    let s;
    for(let n=0;n<180;n++){
      s=await session.game();
      if(s.screen==='STORY'){
        if(n<4)await session.screenshot(`${w}_chapter_story`);
        const skip=s.buttons.find(b=>b.name==='StorySkipButton');if(skip){await press(skip);continue;}
      }
      if(s.map?.ready&&s.map.tutorial?.visible&&!s.transition_loading.active)break;
      await delay(300);
    }
    for(let step=1;step<=3;step++){
      await delay(400);s=await session.game();await session.screenshot(`${w}_map_guide_${step}`);
      const t=s.map?.tutorial;
      check(t?.visible&&t.step===step,`${w}: map guide ${step} reached`,t);
      if(!t)throw Error('Map guide missing');
      check(t.panel[0]>=0&&t.panel[1]>=0&&t.panel[0]+t.panel[2]<=w+1&&t.panel[1]+t.panel[3]<=h+1,`${w}: map guide ${step} panel contained`,t.panel);
      check(t.content_height<=t.body[3]+1,`${w}: map guide ${step} complete text visible`,t);
      check(t.body[1]+t.body[3]<=t.continue[1]+1,`${w}: map guide ${step} reading area does not overlap action`,t);
      const b=s.buttons.find(b=>b.text.includes(step===3?'지도에서 시작':'다음 안내'));
      await press(b);
    }
    s=await session.game();check(!s.map.tutorial.visible&&!s.map.moving&&!s.map.turn_transitioning,`${w}: tutorial releases map interaction`,s.map.tutorial);
    await session.screenshot(`${w}_map_after_guidance`);
  }
  const logs=session.logs(1500),errors=logs.filter(x=>/SCRIPT ERROR|Parse Error|Invalid call/.test(x.text));
  check(errors.length===0,'no runtime errors',errors);
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,passed:checks.every(c=>c.ok),logs},null,2));
  console.log('ONBOARDING_AUDIT',checks.filter(c=>c.ok).length,'/',checks.length);
  if(checks.some(c=>!c.ok))process.exitCode=1;
}finally{await session.close().catch(()=>{});}
