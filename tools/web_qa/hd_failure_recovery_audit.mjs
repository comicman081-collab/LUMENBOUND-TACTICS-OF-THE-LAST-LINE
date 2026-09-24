import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9366']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const state=()=>session.game();
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
async function tapText(predicate){const s=await state(),b=s.buttons.find(b=>predicate(b)&&!b.disabled&&b.rect[1]>=0&&b.rect[1]+b.rect[3]<=session.viewport.height+1);if(!b)throw Error('Visible recovery action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(450);}
async function waitFor(predicate,seconds=120){for(let i=0;i<seconds*2;i++){const s=await state();if(predicate(s))return s;await delay(500);}throw Error('Recovery state timeout');}
let intercepted=0;
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  session.socket.addEventListener('message',async event=>{
    const packet=JSON.parse(event.data);if(packet.method!=='Fetch.requestPaused')return;
    const {requestId}=packet.params;
    try{if(intercepted++===0)await session.send('Fetch.fulfillRequest',{requestId,responseCode:503,responseHeaders:[{name:'Content-Type',value:'text/plain'}],body:Buffer.from('Intentional local QA unavailable page').toString('base64')});else await session.send('Fetch.continueRequest',{requestId});}catch(error){console.error('FAULT_INTERCEPT_ERROR',String(error));}
  });
  await session.send('Fetch.enable',{patterns:[{urlPattern:'*/_hd/full_density/r2/CHR001/page_00.png',requestStage:'Request'}]});
  for(const stage of [1,2]){
    await session.game('prepare_contact',{stage_number:stage,invincible:true});
    for(let i=0;i<150;i++){
      const s=await state();if(s.screen==='STORY'){await tapText(b=>b.name==='StorySkipButton');continue;}
      if(s.map?.ready){if(s.buttons.some(b=>b.text==='안내 건너뛰기'))await tapText(b=>b.text==='안내 건너뛰기');break;}await delay(500);
    }
    if(!(await state()).buttons.some(b=>b.text.includes('1칸 이동')))await tapText(b=>b.text==='다음 조우');
    await tapText(b=>b.text.includes('1칸 이동'));
    const s=await waitFor(s=>s.battle?.ready);
    await session.checkpoint(`n${stage}_ready`);
    if(stage===1){
      check(intercepted>0,'an actual active actor PNG request received the intentional 503');
      check(typeof s.battle.signature.full_density.error==='string'&&s.battle.signature.full_density.error.length>0,'failed HD family does not masquerade as a valid high-density lease');
      check(s.battle.actors.every(a=>a.action_textures.idle.width>0),'complete fallback actors remain visible after one HD page fails');
      await session.send('Fetch.disable');
    }else checkFullDensity(s,check);
    await tapText(b=>b.name==='BattleSpeedButton');
    const result=await waitFor(s=>s.screen==='RESULT');
    check(result.result?.victory,`N${stage} finishes actual gameplay ${stage===1?'despite the failed optional page':'after network recovery'}`);
    await tapText(b=>b.text==='챕터 맵으로');
    await waitFor(s=>s.map?.ready);
  }
  check(session.events.filter(e=>e.method==='Runtime.exceptionThrown').length===0,'no JavaScript exceptions during failure and recovery');
  const s=await state();check(s.sandbox.production_write_attempt_count===0,'failure/recovery uses isolated local saves');
}catch(error){checks.push({name:String(error),pass:false});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,intercepted,fixture:'One intentional local HD HTTP 503, real battles N01/N02, invincible neighbor fixtures. Expected asset/network diagnostics are retained.'},null,2));}
