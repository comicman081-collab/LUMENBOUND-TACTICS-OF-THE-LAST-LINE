// Local Chrome acceptance of actual intro playback, gesture audio, and skip.
import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output, url, port='9394'] = process.argv.slice(2);
const session = new GameplaySession(output), checks = [], samples = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let graph = null;
function check(value, name) {
  checks.push({name, pass:!!value});
  console.log(JSON.stringify(checks.at(-1)));
  if (!value) throw Error(name);
}
async function ready() {
  for (let n=0; n<100; n++) {
    if (await session.evaluate('!!window.__localGameplayQA?.ready')) return;
    await delay(750);
  }
  throw Error('Intro browser did not become ready');
}
async function clickButton(state, name) {
  const b = state.buttons.find(b => b.name === name && !b.disabled);
  if (!b) throw Error(`Missing ${name}`);
  await session.click(b.rect[0]+b.rect[2]/2, b.rect[1]+b.rect[3]/2);
}
const hasSkip = state => state.buttons.some(b => b.name === 'StartupIntroSkipButton');
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',
    url, port:Number(port), width:1280, height:720, profileAudio:true});
  await ready();
  let state = await session.game();
  check(state.buttons.some(b => b.name === 'StartupIntroAudioStartButton'), 'holds intro for trusted audio start gesture');
  await session.screenshot('00_audio_gate');
  await session.mark('intro_playing');
  const start = Date.now();
  await clickButton(state, 'StartupIntroAudioStartButton');
  let nextShot = 2, endedAt = null;
  while (Date.now()-start < 55000) {
    state = await session.game();
    const elapsed = (Date.now()-start)/1000;
    samples.push({elapsed, intro_active:hasSkip(state), screen:state.screen});
    if (elapsed >= nextShot && hasSkip(state)) {
      await session.screenshot(`playing_${nextShot}s`);
      nextShot += 10;
    }
    if (!hasSkip(state)) {endedAt=elapsed;break;}
    await delay(450);
  }
  check(endedAt !== null && endedAt >= 49.8 && endedAt < 53,
    `complete intro reaches title at 50 seconds (observed ${endedAt?.toFixed(3)}s)`);
  check(state.screen === 'TITLE', 'natural completion reaches the title');
  await session.screenshot('60_title_after_complete');
  graph = await session.evaluate('window.__localAudioGraph');
  const sound = graph.mixed.filter(s => s.phase === 'intro_playing');
  check(sound.filter(s => s.rms > .0001 && s.state === 'running').length > 400,
    'existing music produces real WebAudio signal throughout the intro');
  const first = sound.find(s=>s.rms>.0001)?.at;
  const last = [...sound].reverse().find(s=>s.rms>.0001)?.at;
  check(last-first > 48000, 'music spans at least 48 seconds without source-clip audio');
  let silentSince=null, maximumSilence=0;
  for(const s of sound.filter(s=>s.at>=first && s.at<=last)) {
    if(s.rms<.000001) silentSince??=s.at;
    else if(silentSince!==null) {maximumSilence=Math.max(maximumSilence,s.at-silentSince);silentSince=null;}
  }
  check(maximumSilence < 700, `no unexpected audio gap over 700ms (max ${maximumSilence.toFixed(1)}ms)`);
  await session.send('Page.reload', {ignoreCache:true});
  await delay(1000); await ready();
  state=await session.game();
  await clickButton(state,'StartupIntroAudioStartButton');
  await delay(1500);
  await clickButton(await session.game(),'StartupIntroSkipButton');
  await delay(1000);
  state=await session.game();
  check(!hasSkip(state) && state.screen==='TITLE', 'skip during actual playback closes video and reaches title');
  await session.screenshot('skip_title');
  await delay(1000);
  const afterSkip=await session.evaluate('window.__localAudioGraph.mixed.slice(-6)');
  check(afterSkip.length>0 && afterSkip.every(s=>s.rms<.000001), 'skip stops intro soundtrack without an audio tail');
  check(session.logs(20000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0, 'intro playback and skip have no runtime errors or warnings');
  check(session.events.filter(e=>['Runtime.exceptionThrown','Network.loadingFailed','Network.responseReceived'].includes(e.method)).length===0, 'intro route has no JavaScript exceptions or failed requests');
} catch(error) {
  checks.push({name:String(error),pass:false}); console.error(error); process.exitCode=1;
} finally {
  await session.close();
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,samples,graph,
    scope:'Actual local desktop Chrome playback and audio-graph measurement; physical phone and human listening are not covered.'},null,2));
}
