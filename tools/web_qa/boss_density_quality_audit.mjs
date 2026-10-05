// Inspect actual exported boss textures in the real 1080p renderer.
// Held final-wave fixtures prove art/loading/grounding only, not wins or FPS.
import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,input,port='9547',density='512']=process.argv.slice(2);
const url=new URL(input);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','boss-quality-1080p');
const session=new GameplaySession(output),checks=[],stages=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(pass,name,details){
 checks.push({pass:!!pass,name,details});console.log(JSON.stringify(checks.at(-1)));
 if(!pass)throw Error(name);
}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1920,height:1080});
 for(let n=0;n<180&&!await session.evaluate('window.__localGameplayQA?.ready && window.__lanternRenderReady');n++)await delay(500);
 check(await session.evaluate('!!window.__localGameplayQA?.ready'),'local-only QA available');
 for(const stage of ['CH01-N20','CH10-N20','CH20-N20']){
  await session.game('prepare_art_stage',{stage_id:stage});let s;
  for(let n=0;n<360;n++){
   s=await session.game();
   if(s.battle?.ready&&!s.transition_loading.active)break;
   await delay(300);
  }
  check(s.battle?.ready&&!s.transition_loading.active,'authored stage assets ready '+stage);
  await session.game('art_boss_wave');await delay(300);
  s=await session.game();
  const boss=s.battle.actors.find(a=>a.rank==='BOSS');
  check(boss,'actual authored final-wave boss present '+stage);
  check(!s.battle.hd.error&&s.battle.hd.decoded_rgba_bytes<=s.battle.hd.budget_bytes,'error-free bounded HD lease '+stage,s.battle.hd);
  check(['idle','move','basic_attack','normal_skill','ultimate','hit','down','victory'].every(a=>boss.action_textures[a].width===Number(density)&&boss.action_textures[a].height===Number(density)),'all eight base actions retain '+density+'px '+boss.id);
  check(Math.abs(boss.ground_contact.contact_error)<.01,'boss feet stay on the authored ground '+boss.id);
  check(s.battle.actors.filter(a=>a.team==='PLAYER').every(a=>a.action_textures.idle.width===256),'player density unchanged '+stage);
  check(s.battle.paused,'visual fixture is held and excluded from FPS/win evidence');
  await session.screenshot(stage+'_boss_'+boss.id);
  stages.push({stage,boss,hd:s.battle.hd});
 }
 check(!session.logs(10000).some(e=>e.type==='error'||/SCRIPT ERROR|Parse Error|Full-density actor pack unavailable/.test(e.text)),'no runtime/script/HD loading errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);process.exitCode=1;await session.screenshot('failure').catch(()=>{});}
finally{
 await writeFile(path.join(output,'boss_quality_summary.json'),JSON.stringify({passed:checks.every(c=>c.pass),checks,stages,scope:'Actual 1920x1080 renderer, held authored final waves; no victory or FPS claim'},null,2));
 await session.close();
}
