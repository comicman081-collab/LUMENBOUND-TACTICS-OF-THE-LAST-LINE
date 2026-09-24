import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9446']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const check=(ok,name,details)=>{checks.push({ok,name,details});console.log(ok?'PASS':'FAIL',name);};
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:634,height:357});
  for(let n=0;n<180&&!session.logs(100).some(x=>x.text.includes('WEB_RENDER_WARMUP_COMPLETE'));n++)await delay(500);
  check(await session.evaluate('typeof window.__localGameplayQA')==='undefined','player export does not expose developer command bridge');
  await session.screenshot('01_intro_gate');
  await session.click(579,37);await delay(800);await session.screenshot('02_title');
  await session.click(112,256);await delay(1200);await session.screenshot('03_prologue');
  await session.click(578,54);await delay(1200);await session.screenshot('04_home_guide');
  await session.click(168,261);await delay(1200);await session.screenshot('05_chapter_story');
  await session.click(156,99);
  for(let n=0;n<100&&!session.logs(200).some(x=>x.text.includes('STAGE_ENTRY_PRELOAD_COMPLETE'));n++)await delay(400);
  await delay(700);await session.screenshot('06_map_guide');
  for(let step=1;step<=3;step++){await session.click(319,264);await delay(650);await session.screenshot(`07_map_guide_after_${step}`);}
  const audio=await session.evaluate('window.__lumenBGM?.status()');
  check(audio?.active&&audio.active_sources===1&&!audio.error,'map BGM is playing one independent browser source',audio);
  const logs=session.logs(1500),errors=logs.filter(x=>/SCRIPT ERROR|Parse Error|Invalid call/.test(x.text));
  check(logs.some(x=>x.text.includes('STAGE_ENTRY_PRELOAD_COMPLETE')),'real player navigation reaches the tactical map');
  check(errors.length===0,'no Godot runtime errors during player startup',errors);
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,passed:checks.every(c=>c.ok),logs},null,2));
  console.log('PLAYER_BOOT_AUDIT',checks.filter(c=>c.ok).length,'/',checks.length);
  if(checks.some(c=>!c.ok))process.exitCode=1;
}finally{await session.close().catch(()=>{});}
