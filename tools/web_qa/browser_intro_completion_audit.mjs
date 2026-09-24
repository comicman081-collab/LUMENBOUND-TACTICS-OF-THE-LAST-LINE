import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9431']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],samples=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name,details){checks.push({ok,name,details});console.log(ok?'PASS':'FAIL',name);}
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1280,height:720});
  for(let n=0;n<160&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
  const state=await session.game();
  const start=state.buttons.find(b=>b.name==='StartupIntroAudioStartButton');
  if(!start)throw Error('Intro start gesture missing');
  await session.screenshot('intro_start_gate');
  await session.click(start.rect[0]+start.rect[2]/2,start.rect[1]+start.rect[3]/2);
  await delay(300);
  await session.evaluate(`window.__introEvidence=[]; const v=window.__lumenIntro.video; for(const name of ['loadedmetadata','pause','playing','ended','error'])v.addEventListener(name,()=>window.__introEvidence.push({name,time:v.currentTime,duration:v.duration,wall:performance.now()}),{capture:true});`);
  const read=()=>session.evaluate(`(()=>{const a=window.__lumenIntro,v=a?.video;return {done:a?.done,time:a?.time,error:a?.error,current:v?.currentTime,duration:v?.duration,width:v?.videoWidth,height:v?.videoHeight,paused:v?.paused,volume:v?.volume,decodedAudio:v?.webkitAudioDecodedByteCount,wall:performance.now()}})()`);
  let s,paused=false,resumed=false,pauseWall=0,pauseTime=0;
  const started=Date.now();
  while(Date.now()-started<85000){
    s=await read();samples.push(s);
    if(!paused&&s.current>14){
      check(s.width===1920&&s.height===1080&&Math.abs(s.duration-50)<.05,'1080p 50-second media loaded',s);
      check(s.volume>0&&s.decodedAudio>0,'embedded preserved BGM is decoded',s);
      await session.evaluate('window.__lumenIntro.video.pause()');paused=true;pauseTime=s.current;pauseWall=Date.now();
      await session.screenshot('intro_before_hold');
    }
    if(paused&&!resumed&&Date.now()-pauseWall>12000){
      check(!s.done&&Math.abs(s.current-pauseTime)<.3,'12-second pause does not finish the intro',s);
      await session.evaluate('window.__lumenIntro.video.play()');resumed=true;
    }
    if(s.done)break;
    await delay(400);
  }
  const events=await session.evaluate('window.__introEvidence');
  check(events.some(e=>e.name==='ended'&&e.time>=49.99),'authoritative ended event occurs at 50 seconds',events);
  check(s?.done&&s.time>=49.99,'completed media retains final 50-second position',s);
  check(Date.now()-started>61000,'wall-clock duration includes the intentional pause');
  await session.screenshot('intro_complete_title');
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,samples,events},null,2));
}catch(error){check(false,'intro audit',String(error));}
finally{await session.close();process.exitCode=checks.every(c=>c.ok)?0:1;}
