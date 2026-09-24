import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9368']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],samples=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const state=()=>session.game();
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
async function tapText(predicate){const s=await state(),b=s.buttons.find(b=>predicate(b)&&!b.disabled&&b.rect[1]>=0&&b.rect[1]+b.rect[3]<=844);if(!b)throw Error('Visible motion audit action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(450);}
let recording=false;
async function stopRecording(){
  if(!recording)return;
  const data=await session.evaluate(`new Promise(resolve=>{const r=window.__localMotionRecording;r.recorder.onstop=()=>{const blob=new Blob(r.chunks,{type:r.recorder.mimeType});const reader=new FileReader();reader.onloadend=()=>resolve(reader.result);reader.readAsDataURL(blob);r.stream.getTracks().forEach(t=>t.stop());};r.recorder.stop();})`);
  await writeFile(path.join(output,'actual_combat.webm'),Buffer.from(data.split(',')[1],'base64'));recording=false;
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  await session.game('prepare_contact',{stage_number:20,invincible:true});
  for(let n=0;n<130;n++){const s=await state();if(s.screen==='STORY'){await tapText(b=>b.name==='StorySkipButton');continue;}if(s.map?.ready){if(s.buttons.some(b=>b.text==='안내 건너뛰기'))await tapText(b=>b.text==='안내 건너뛰기');break;}await delay(500);}
  if(!(await state()).buttons.some(b=>b.text.includes('1칸 이동')))await tapText(b=>b.text==='다음 조우');
  await tapText(b=>b.text.includes('1칸 이동'));
  let start=0,result=null;
  for(let n=0;n<400;n++){
    const s=await state();
    if(s.battle?.ready){
      if(!start){
        await session.evaluate(`(()=>{const canvas=document.querySelector('canvas');const stream=canvas.captureStream(30);const recorder=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp8',videoBitsPerSecond:3500000});const r=window.__localMotionRecording={stream,recorder,chunks:[]};recorder.ondataavailable=e=>{if(e.data.size)r.chunks.push(e.data)};recorder.start(1000);return {width:canvas.width,height:canvas.height}})()`);
        recording=true;start=Date.now();await session.mark('recorded_motion_not_performance_baseline');
      }
      samples.push({at:Date.now(),wave:s.battle.wave,actors:s.battle.actors.map(a=>({id:a.id,hp:a.hp,track:a.motion_track,ground:a.ground_contact}))});
      if(samples.length%14===0)await session.checkpoint(`motion_${samples.length}`);
      if(recording&&Date.now()-start>50000)await stopRecording();
    }
    if(s.screen==='RESULT'){result=s;break;}
    await delay(300);
  }
  await stopRecording();
  check(result?.result?.victory,'actual N20 combat completes while motion is observed and recorded');
  const actions=new Set(samples.flatMap(s=>s.actors.map(a=>a.track?.name)));
  check(['basic_attack','normal_skill','ultimate'].every(a=>actions.has(a)),'actual gameplay shows basic, normal skill and ultimate action tracks');
  const playerProgress=new Set(),enemyProgress=new Set();
  for(const s of samples)for(const a of s.actors){if(['basic_attack','normal_skill','ultimate'].includes(a.track?.name)&&a.track.elapsed>.22)(a.id.startsWith('CHR')?playerProgress:enemyProgress).add(a.id);}
  check(playerProgress.size>=4&&enemyProgress.size>=1,'both teams advance beyond first attack frames under live incoming damage');
  check(samples.every(s=>s.actors.every(a=>a.ground&&Math.abs(a.ground.contact_error)<.001&&Math.abs(a.ground.shadow_ground_y-a.ground.opaque_contact_ground_y)<.001)),'all sampled real action frames retain opaque body contact on their ground shadow');
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'recorded battle has no runtime or shader errors');
}catch(error){checks.push({name:String(error),pass:false});console.error(error);await stopRecording().catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,samples,fixture:'Real N20 browser combat from isolated invincible neighbor fixture, 1x speed, WebM captures the actual canvas. Capture/probe overhead excludes this run from performance baselines; no copied reference-game art.'},null,2));}
