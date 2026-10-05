import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output, input, port = '9531'] = process.argv.slice(2);
const url = new URL(input); url.searchParams.set('gameplay-qa', '1');
url.searchParams.set('qa', 'resolution-1080p');
const session = new GameplaySession(output), checks = [], cases = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function check(pass, name) {
  checks.push({pass: !!pass, name}); console.log(JSON.stringify(checks.at(-1)));
  if (!pass) throw Error(name);
}
async function ready() {
  for (let n = 0; n < 240; n++) {
    if (await session.evaluate('!!window.__localGameplayQA?.ready')) return;
    await delay(500);
  }
  throw Error('Local QA not ready');
}
try {
  await session.start({browserPath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    url: url.href, port: Number(port), width: 1920, height: 1080});
  await ready();
  await session.game('presentation_screen', {screen:'TITLE'});
  await delay(500);
  const profiles = [[1920,1080,1,false], [2560,1440,2,false], [2560,1080,1,false],
    [1280,720,1,false], [700,1100,1,false], [844,390,2,true], [390,844,2,true]];
  let mobileLoaded = false;
  for (const [width, height, dpr, mobile] of profiles) {
    if (mobile && !mobileLoaded) {
      await session.send('Network.setUserAgentOverride', {
        userAgent:'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36',
        platform:'Android', userAgentMetadata:{brands:[],platform:'Android',platformVersion:'14.0.0',
          architecture:'arm',model:'Pixel 8',mobile:true},
      });
      await session.send('Emulation.setTouchEmulationEnabled', {enabled:true,maxTouchPoints:5});
      await session.send('Emulation.setDeviceMetricsOverride', {width,height,deviceScaleFactor:dpr,mobile});
      await session.send('Page.reload');
      await delay(500);
      await ready();
      await session.game('presentation_screen', {screen:'TITLE'});
      mobileLoaded = true;
    }
    await session.send('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor:dpr, mobile});
    await delay(1200);
    const dimensions = await session.evaluate(`({inner:[innerWidth,innerHeight],
      canvas:[document.getElementById('canvas').width,document.getElementById('canvas').height],
      host:window.__lumenboundHostLayoutSize,config:GODOT_CONFIG.canvasResizePolicy})`);
    const outer = await session.send('Runtime.evaluate', {returnByValue:true, expression:`(() => {
      const f=document.getElementById('landscape-game'),r=f.getBoundingClientRect();
      return {rect:[r.left,r.top,r.width,r.height],rotated:f.dataset.rotated,scale:Number(f.dataset.scale),deviceClass:f.dataset.deviceClass};
    })()`});
    cases.push({width,height,dpr,mobile,dimensions,outer:outer.result.value});
    check(outer.result.value.deviceClass === (mobile ? 'mobile' : 'desktop'), 'actual device class');
    check(outer.result.value.rotated === (mobile && height > width ? '1' : '0'), 'correct device rotation');
    check(dimensions.inner[0] === 1920 && dimensions.inner[1] === 1080, 'fixed inner viewport '+width+'x'+height);
    check(dimensions.canvas[0] === 1920 && dimensions.canvas[1] === 1080 && dimensions.config === 0,
      'fixed GPU backing and policy at DPR '+dpr+' / '+width+'x'+height);
    const [left,top,w,h] = outer.result.value.rect;
    check(left >= -1 && top >= -1 && left+w <= width+1 && top+h <= height+1,
      'game fits host '+width+'x'+height);
    await session.screenshot('title_'+width+'x'+height+'_dpr'+dpr);
    const state = await session.game();
    const settings = state.buttons.find(b => !b.disabled && b.text === '설정');
    check(settings, 'settings action visible '+width+'x'+height);
    const settingsPoint=[settings.rect[0]+settings.rect[2]/2,settings.rect[1]+settings.rect[3]/2];
    if(mobile)await session.tap(...settingsPoint);else await session.click(...settingsPoint);
    await delay(400);
    const after = await session.game();
    check(after.screen === 'SETTINGS', 'scaled/rotated real pointer works '+width+'x'+height);
    const back = after.buttons.find(b => !b.disabled && b.text.includes('뒤로'));
    check(back, 'return action visible');
    const backPoint=[back.rect[0]+back.rect[2]/2,back.rect[1]+back.rect[3]/2];
    if(mobile)await session.tap(...backPoint);else await session.click(...backPoint);
    await delay(400);
    check((await session.game()).screen === 'TITLE', 'returned to title');
  }
  const errors = session.logs(10000).filter(e => e.type === 'error' || /SCRIPT ERROR|Parse Error/.test(e.text));
  check(errors.length === 0, 'no console errors');
} catch (error) {
  checks.push({pass:false,name:String(error)}); console.error(error); process.exitCode=1;
  await session.screenshot('failure').catch(()=>{});
} finally {
  await writeFile(path.join(output,'resolution_summary.json'),JSON.stringify({checks,cases},null,2));
  await session.close();
}
