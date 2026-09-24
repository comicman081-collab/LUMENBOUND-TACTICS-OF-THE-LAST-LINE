import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9421']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],runs=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(ok,name){checks.push({pass:!!ok,name});if(!ok)throw Error(name);}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1280,height:720});
  for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
  for(const stage of ['CH02-N01','CH08-N20','CH20-N20']){
    await session.game('prepare_art_stage',{stage_id:stage});
    let state;
    for(let n=0;n<240;n++){
      state=await session.game();
      if(state.screen==='BATTLE'&&state.stage===stage&&state.battle?.ready)break;
      if(state.buttons.some(b=>b.text==='RETRY'))throw Error(stage+' load failure');
      await delay(400);
    }
    check(state.screen==='BATTLE'&&state.stage===stage&&state.battle?.ready,stage+' enters actual renderer');
    checkFullDensity(state,check);
    await delay(1700);
    if(stage.endsWith('20')){
      await session.game('art_boss_wave');
      await delay(700);
    }
    state=await session.game();
    const enemies=state.battle.actors.filter(a=>a.team==='ENEMY');
    check(enemies.length>0,stage+' enemies visible');
    if(stage.endsWith('20'))check(enemies.some(e=>e.id.startsWith('BOSS')),stage+' final boss visible');
    await session.checkpoint(stage.replaceAll('-','_'));
    runs.push({stage,actors:state.battle.actors,full_density:state.battle.signature.full_density});
    console.log(stage+' verified');
  }
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'no runtime or shader errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,runs,scope:'Real battle asset loading and rendering at three authored encounters, including held final boss waves. Held waves are not claims of preceding combat victories.'},null,2));}
