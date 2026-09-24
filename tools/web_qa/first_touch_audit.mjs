import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output,url,port='9381']=process.argv.slice(2);
const session=new GameplaySession(output), results=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
  for(const stage of [9,16,9,16]) {
    await session.resize(stage===9?360:390,stage===9?640:844);
    await session.game('prepare_contact',{stage_number:stage,invincible:true});
    let before;
    for(let n=0;n<140;n++) {
      before=await session.game();
      if(before.screen==='STORY') {
        const next=before.buttons.find(b=>b.text==='다음'&&!b.disabled);
        if(next)await session.tap(next.rect[0]+next.rect[2]/2,next.rect[1]+next.rect[3]/2);
      }
      const skip=before.buttons.find(b=>b.text==='안내 건너뛰기'&&!b.disabled);
      if(skip) {await session.tap(skip.rect[0]+skip.rect[2]/2,skip.rect[1]+skip.rect[3]/2);continue;}
      if(before.screen==='STAGE_SELECT'&&before.map?.ready)break;
      await delay(500);
    }
    const button=before.buttons.find(b=>b.text==='다음 조우'&&!b.disabled);
    if(!button)throw Error(`N${stage}: next encounter unavailable`);
    await session.tap(button.rect[0]+button.rect[2]/2,button.rect[1]+button.rect[3]/2);
    let after, pass=false;
    for(let n=0;n<40;n++) {
      after=await session.game();
      pass=after.buttons.some(b=>b.text.includes('1칸 이동')&&!b.disabled);
      if(pass)break;
      await delay(250);
    }
    results.push({stage,pass,before,after});
    console.log(JSON.stringify({stage,pass}));
    await session.checkpoint(`n${stage}_${results.length}_${pass?'pass':'fail'}`);
    if(!pass)process.exitCode=1;
  }
} catch(error) {results.push({pass:false,error:String(error)});process.exitCode=1;console.error(error);}
finally {
  await session.close();
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({contract:'Exactly one touch per encounter; no retry and no forced UI selection',results},null,2));
}
