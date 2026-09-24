import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,input,port='9481']=process.argv.slice(2),session=new GameplaySession(output);
const url=new URL(input);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','redrawn-combat-20260913');
const checks=[],samples=[];const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name){checks.push({pass:!!ok,name});if(!ok)throw Error(name);}
async function ready(){for(let n=0;n<180;n++){const s=await session.game();if(s.battle?.ready&&!s.transition_loading.active)return s;await delay(500);}throw Error('battle warm timeout');}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:url.href,port:Number(port),width:1280,height:720});
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 for(const [group,party] of [['front',['CHR001','CHR002','CHR003','CHR004','CHR005']],['support',['CHR006','CHR007','CHR008','CHR002','CHR005']]]){
  await session.game('prepare_motion_stage',{party});let s=await ready();
  check(s.battle.action_frames.error===''&&party.every(id=>s.battle.action_frames.entities.includes(id)),group+' action pages loaded');
  check(s.battle.action_frames.decoded_bytes<=s.battle.action_frames.budget,group+' action memory bounded');
  for(const action of ['basic_attack','normal_skill','ultimate'])for(let frame=0;frame<6;frame++){
   await session.game('motion_frame_fixture',{action,frame});await delay(70);s=await session.game();
   const actors=s.battle.actors.filter(a=>a.hp>0&&party.includes(a.id));
   check(actors.length===5&&actors.every(a=>a.action_motion.redrawn&&a.action_motion.frame===frame),`${group} ${action} frame ${frame} actually rendered`);
   check(s.battle.actors.every(a=>Math.abs(a.ground_contact.contact_error)<.001),`${group} ${action} ${frame} grounded`);
   samples.push({group,action,frame,actors:s.battle.actors});await session.checkpoint(`${group}_${action}_${frame}`);
  }
  await session.game('art_boss_wave');
  for(const action of ['basic_attack','normal_skill'])for(let frame=0;frame<6;frame++){
   await session.game('motion_frame_fixture',{action,frame});s=await session.game();
   const bosses=s.battle.actors.filter(a=>a.id==='BOSS001');
   check(bosses.length>0&&bosses.every(a=>a.action_motion.redrawn&&a.action_motion.frame===frame),`${group} boss ${action} ${frame}`);
   if(group==='front')await session.checkpoint(`boss_${action}_${frame}`);
  }
 }
 await session.game('prepare_art_stage',{stage_id:'CH01-N01'});await ready();
 for(const action of ['basic_attack','normal_skill'])for(let frame=0;frame<6;frame++){
  await session.game('motion_frame_fixture',{action,frame});const s=await session.game();
  for(const id of ['ENM001','ENM002']){
   const actor=s.battle.actors.find(a=>a.id===id);
   check(actor?.action_motion.redrawn&&actor.action_motion.frame===frame,`${id} ${action} ${frame} actual renderer`);
  }
  await session.checkpoint(`creatures_${action}_${frame}`);
 }
 await session.send('Emulation.setDeviceMetricsOverride',{width:640,height:360,deviceScaleFactor:1,mobile:false});await delay(400);
 for(const action of ['basic_attack','normal_skill','ultimate']){
  await session.game('motion_frame_fixture',{action,frame:3});await session.checkpoint(`small_${action}`);
 }
 check(session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text)).length===0,'no renderer errors');
}catch(e){checks.push({pass:false,name:String(e)});console.error(e);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,samples,scope:'Held actual renderer frames in disposable art fixtures. Separate natural battle audit required for gameplay completion.'},null,2));}
