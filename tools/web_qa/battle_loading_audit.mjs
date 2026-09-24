import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9396']=process.argv.slice(2);
const session=new GameplaySession(output), checks=[], runs=[], requests=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(ok,name){checks.push({pass:!!ok,name});if(!ok)throw Error(name);}
const contained=r=>r[0]>=0&&r[1]>=0&&r[0]+r[2]<=session.viewport.width+1&&r[1]+r[3]<=session.viewport.height+1;
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&contained(b.rect)&&predicate(b));if(!b)throw Error('Visible action unavailable');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function settle(){for(let n=0;n<160;n++){const s=await session.game();if(s.screen==='STORY'){await tap(s,b=>b.text==='다음');continue;}if(s.screen==='STAGE_SELECT'&&s.map?.ready){if(s.buttons.some(b=>b.text==='안내 건너뛰기')){await tap(s,b=>b.text==='안내 건너뛰기');continue;}await delay(1100);return session.game();}await delay(350);}throw Error('Map timeout');}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:844,height:390});
  session.socket.addEventListener('message',event=>{
    const m=JSON.parse(event.data),p=m.params;
    if(m.method==='Network.requestWillBeSent'&&p.request.url.includes('/_hd/'))requests.push({at:Date.now(),url:p.request.url,request_id:p.requestId,start_seconds:p.timestamp});
    if(m.method==='Network.loadingFinished'){
      const row=requests.findLast(r=>r.request_id===p.requestId);
      if(row){row.network_ms=(p.timestamp-row.start_seconds)*1000;row.transfer_bytes=p.encodedDataLength;}
    }
  });
  for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
  for(let run=0;run<3;run++){
    await session.game('prepare_contact',{stage_number:1,invincible:true});let s=await settle();
    const mapPreload=s.map_preload_msec,cacheBefore=s.density_cache,requestStart=requests.length;
    if(!s.buttons.some(b=>b.text.includes('1칸 이동')&&contained(b.rect))){await tap(s,b=>b.text==='다음 조우');await delay(500);s=await session.game();}
    await tap(s,b=>b.text.includes('1칸 이동'));
    const contact=Date.now();let loadStart=0,readyAt=0,readyState=null,result=null;
    for(let n=0;Date.now()-contact<150000;n++){
      s=await session.game();
      if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled)){await tap(s,b=>b.name==='EventDialogueNext');continue;}
      if(s.screen==='STORY'){await tap(s,b=>b.text==='다음');continue;}
      if(s.screen==='BATTLE'&&!loadStart)loadStart=Date.now();
      if(s.battle?.ready&&!readyAt){readyAt=Date.now();readyState=s;checkFullDensity(s,check);await session.checkpoint(`battle_${run+1}`);await tap(s,b=>b.name==='BattleSpeedButton');}
      if(s.screen==='RESULT'){result=s;break;}
      if(s.buttons.some(b=>b.text==='RETRY'))throw Error('Battle loading failed');
      await delay(250);
    }
    check(readyAt>0&&result?.result?.victory,`run ${run+1} completes actual combat`);
    const row={run:run+1,load_ms:readyAt-loadStart,map_preload_ms:mapPreload,hd_requests:requests.slice(requestStart),cache_before:cacheBefore,cache_ready:readyState.density_cache};
    runs.push(row);console.log(JSON.stringify({...row,hd_requests:row.hd_requests.length}));
    await tap(result,b=>b.text==='지도로'||b.text==='챕터 맵으로');await settle();
  }
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'no runtime or shader warnings');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,runs,measurement:'First BATTLE snapshot to first assets-ready snapshot; 250ms polling plus browser bridge latency. Same isolated CH01 N01, party and viewport; actual combat with fixture invincibility.'},null,2));}
