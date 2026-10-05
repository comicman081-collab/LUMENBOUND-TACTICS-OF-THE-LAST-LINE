// Actual Sites player: trusted start, complete movie, and return to title.
import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output, url, port = '9478', widthValue = '1280', heightValue = '720'] = process.argv.slice(2);
const width=Number(widthValue),height=Number(heightValue);
const session = new GameplaySession(output), checks = [], samples = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function check(ok, name, details) {
  checks.push({ok: !!ok, name, details});
  console.log(JSON.stringify(checks.at(-1)));
  if (!ok) throw Error(name);
}
try {
  await session.start({browserPath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    url, port: Number(port), width, height});
  let ready = false;
  for (let n = 0; n < 180; n++) {
    ready = !!await session.evaluate('window.__lanternRenderReady');
    if (ready) break;
    await delay(500);
  }
  check(ready, 'player boots');
  await session.screenshot('01_start_gate');
  await session.click(320*width/1280,581*height/720);
  for (let n = 0; n < 40 && !await session.evaluate('!!window.__lumenIntro?.video'); n++) await delay(100);
  check(await session.evaluate('!!window.__lumenIntro?.video'), 'start button opens the browser movie');
  await session.evaluate(`(() => {
    const video=window.__lumenIntro.video;
    window.__introAuditEvents=[];
    for(const name of ['playing','ended','error','waiting']) video.addEventListener(name,()=>
      window.__introAuditEvents.push({name,time:video.currentTime,duration:video.duration,wall:performance.now()}),
      {capture:true}); // Observe ended before the production bridge removes src.
  })()`);
  const started = Date.now();
  let nextShot = 5, media, played = false, metadataChecked = false;
  while (Date.now() - started < 95000) {
    media = await session.evaluate(`(() => {
      const a=window.__lumenIntro,v=a?.video;
      return {done:a?.done,time:a?.time,error:a?.error,current:v?.currentTime,duration:v?.duration,
        width:v?.videoWidth,height:v?.videoHeight,paused:v?.paused,readyState:v?.readyState,
        volume:v?.volume,decodedAudio:v?.webkitAudioDecodedByteCount,
        decodedFrames:v?.getVideoPlaybackQuality?.().totalVideoFrames,src:v?.currentSrc,
        rootExists:!!a?.root,wall:performance.now()};
    })()`);
    samples.push(media);
    if (media.error) throw Error(media.error);
    if (media.current > 1 && !metadataChecked) {
      check(media.width === 1920 && media.height === 1080 && Math.abs(media.duration - 50) < .05,
        '1080p 50-second media is decoded', media);
      metadataChecked = true;
    }
    if (media.current > 2 && media.decodedAudio > 0 && media.volume > 0) played = true;
    if (media.current >= nextShot) {
      await session.screenshot(`playing_${nextShot}s`);
      nextShot += 20;
    }
    if (media.done) break;
    await delay(400);
  }
  const events = await session.evaluate('window.__introAuditEvents');
  check(played, 'preserved intro BGM decodes during playback');
  check(events.some(event => event.name === 'ended' && event.time >= 49.95),
    'movie reaches its own ended event at 50 seconds', events);
  check(media?.done && media.time >= 49.95 && !media.rootExists,
    'complete movie closes its overlay without an early cutoff', media);
  // The existing title cast enters over four seconds. Capture its settled
  // composition, not a still taken while the portraits are crossing the floor.
  await delay(4500);
  await session.screenshot('title_after_full_intro');
  const errors = session.events.filter(e => e.method === 'Runtime.exceptionThrown'
    || (e.method === 'Network.responseReceived' && new URL(e.params.response.url).pathname === '/intro.mp4'));
  check(errors.length === 0, 'movie has no JavaScript exception or failed video response', errors);
  await writeFile(path.join(output, 'acceptance.json'), JSON.stringify({passed: true, url, checks, samples, events}, null, 2));
} catch (error) {
  console.error(String(error));
  await session.screenshot('failure').catch(() => {});
  await writeFile(path.join(output, 'acceptance.json'), JSON.stringify({passed: false, url, error: String(error), checks, samples}, null, 2));
  process.exitCode = 1;
} finally {
  await session.close();
}
