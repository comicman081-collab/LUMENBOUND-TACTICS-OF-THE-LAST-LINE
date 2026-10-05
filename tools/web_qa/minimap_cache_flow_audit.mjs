import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output,input,port='9532']=process.argv.slice(2);
const url=new URL(input);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','minimap-cache-flow');
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(pass,name){checks.push({pass:!!pass,name});console.log(JSON.stringify(checks.at(-1)));if(!pass)throw Error(name)}
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',
    url:url.href,port:Number(port),width:1920,height:1080});
  for(let n=0;n<240&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
  await session.game('prepare_fresh_first_map');let state;
  for(let n=0;n<240;n++){
    state=await session.game();
    if(state.map?.tutorial?.visible){const r=state.map.tutorial.continue;await session.click(r[0]+r[2]/2,r[1]+r[3]/2);await delay(300);continue}
    const skip=state.buttons.find(b=>!b.disabled&&b.text.startsWith('SKIP'));
    if(state.screen==='STORY'&&skip){await session.click(skip.rect[0]+skip.rect[2]/2,skip.rect[1]+skip.rect[3]/2);await delay(300);continue}
    if(state.map?.ready&&!state.transition_loading.active)break;
    await delay(400);
  }
  check(state.map?.ready,'real map ready');
  const original=state.map.minimap;
  check(original.drawn_tiles>0&&original.explored_tiles.length<original.total_tiles,'cached minimap renders explored terrain only');
  const [x,y,w,h]=original.rect;
  await session.click(x+w/2,y+h/2);await delay(150);await session.click(x+w/2,y+h/2,{clickCount:2});
  await delay(500);state=await session.game();
  check(state.map.full_map_open&&state.map.full_map.full_map,'real double-click expands map through cached layers');
  check(JSON.stringify([...state.map.full_map.explored_tiles].sort())===JSON.stringify([...original.explored_tiles].sort()),
    'expanded map retains identical exploration/fog authority');
  check(state.map.full_map.drawn_tiles>0&&state.map.full_map.drawn_tiles<=original.explored_tiles.length,
    'expanded cached terrain actually renders within explored coverage');
  await session.screenshot('expanded_explored_map');
  const close=state.buttons.find(b=>!b.disabled&&b.name==='CloseExploredMap');check(close,'map close action visible');
  await session.click(close.rect[0]+close.rect[2]/2,close.rect[1]+close.rect[3]/2);
  await delay(300);state=await session.game();check(!state.map.full_map_open,'closed map returns to exploration');
  check(session.logs(10000).every(e=>e.type!=='error'&&!/SCRIPT ERROR|Parse Error/.test(e.text)),'no engine/browser errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);process.exitCode=1;await session.screenshot('failure').catch(()=>{})}
finally{await writeFile(path.join(output,'minimap_flow_summary.json'),JSON.stringify({checks},null,2));await session.close()}
