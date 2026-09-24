import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9370'] = process.argv.slice(2);
const session = new GameplaySession(output), checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const state=()=>session.game();
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
async function tapText(predicate){const s=await state(),b=s.buttons.find(b=>predicate(b)&&!b.disabled&&b.rect[1]>=0&&b.rect[1]+b.rect[3]<=session.viewport.height+1);if(!b)throw Error('Missing visible audio audit action');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(400);}
let graph=null,playback=[];
try {
  const target=new URL(url);target.searchParams.set('r7-web-soak-probe','1');
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:target.href,port:Number(port),width:844,height:390,profileAudio:true});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  await session.game('prepare_contact',{stage_number:20,invincible:true});
  for(let n=0;n<120;n++){const s=await state();if(s.screen==='STORY'){await tapText(b=>b.name==='StorySkipButton');continue;}if(s.map?.ready){if(s.buttons.some(b=>b.text==='안내 건너뛰기')){await tapText(b=>b.text==='안내 건너뛰기');continue;}break;}await delay(500);}
  // Actual input opens WebAudio; no force-resume or browser autoplay override.
  await session.mark('audio_map_steady');await delay(16000);
  // Map readiness can precede the deferred first-map tutorial. Dismiss that
  // real overlay before clicking the encounter action beneath it.
  for(let n=0;n<10;n++){const s=await state();if(!s.buttons.some(b=>b.text==='안내 건너뛰기'&&!b.disabled))break;await tapText(b=>b.text==='안내 건너뛰기');}
  if(!(await state()).buttons.some(b=>b.text.includes('1칸 이동')))await tapText(b=>b.text==='다음 조우');
  await tapText(b=>b.text.includes('1칸 이동'));
  let result=null,started=false;
  for(let n=0;n<240;n++){
    const s=await state();
    if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled)){await tapText(b=>b.name==='EventDialogueNext');continue;}
    if(s.screen==='STORY'){await tapText(b=>b.text==='다음');continue;}
    if(s.battle?.ready&&!started){started=true;await session.mark('audio_battle_steady');}
    if(s.screen==='RESULT'){result=s;break;}
    await delay(700);
  }
  check(result?.result?.victory,'actual N20 combat reaches victory with browser audio enabled');
  await session.mark('audio_reward');await delay(1800);
  graph=await session.evaluate('window.__localAudioGraph');
  playback=session.logs(20000).filter(e=>e.text.startsWith('R7_WEB_SOAK_SAMPLE ')).map(e=>JSON.parse(e.text.slice('R7_WEB_SOAK_SAMPLE '.length)));
  check(graph.connections.length>0,'a real WebAudio node feeds the original audio destination');
  // Aggregate the simultaneous destination branches once per sampling tick.
  // A silent unused GainNode must not interleave zero-duration "silence" runs
  // with the actual Godot AudioWorklet and weaken the continuity assertion.
  const battle=graph.mixed.filter(s=>s.phase==='audio_battle_steady');
  check(battle.filter(s=>s.rms>.0001&&s.state==='running').length>100,'actual non-silent combat output is measured, not only play calls');
  check(battle.every(s=>s.state==='running'),'audio context does not suspend itself during combat');
  const zeroRuns=[];let zeroStart=null;
  for(const s of battle){if(s.rms<.000001){zeroStart??=s.at;}else if(zeroStart!==null){zeroRuns.push(s.at-zeroStart);zeroStart=null;}}
  if(zeroStart!==null)zeroRuns.push(battle.at(-1).at-zeroStart);
  graph.analysis={battle_samples:battle.length,zero_runs_ms:zeroRuns,maximum_zero_run_ms:Math.max(0,...zeroRuns)};
  check(Math.max(0,...zeroRuns)<700,'no continuous digital silence of 700ms or longer during the real battle');
  const active=playback.filter(s=>s.audio.audio_enabled&&s.audio.web_unlocked);
  check(active.length>5&&active.every(s=>s.audio.music_active),'verified music playback remains active across sampled map/battle/reward transitions');
  check(active.every(s=>Object.values(s.audio.bgm_consecutive_failures).every(v=>v===0)),'BGM recovery circuit does not accumulate failures');
  check(session.logs(20000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'audio-enabled route has no runtime warnings');
}catch(error){checks.push({name:String(error),pass:false});console.error(error);process.exitCode=1;}
finally{
  graph??=await session.evaluate('window.__localAudioGraph').catch(()=>null);
  await session.close();
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,graph,playback,scope:'Local real Chrome audio graph and verified Godot playback, not human listening or physical phone certification. Chrome output is muted at device level; waveform is measured before that mute. Probe/sampling overhead excludes this run from performance baselines.'},null,2));
}
