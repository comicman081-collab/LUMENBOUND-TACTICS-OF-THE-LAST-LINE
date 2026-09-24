import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,input]=process.argv.slice(2),s=new GameplaySession(output),checks=[];
const u=new URL(input);u.searchParams.set('gameplay-qa','1');u.searchParams.set('qa','small-motion-20260913');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
try{
 await s.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:u.href,port:9484,width:640,height:360});
 for(let n=0;n<180&&!await s.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 await s.game('prepare_art_stage',{stage_id:'CH01-N01'});
 for(let n=0;n<180;n++){const p=await s.game();if(p.battle?.ready&&!p.transition_loading.active)break;await delay(350);}
 for(const action of ['basic_attack','normal_skill','ultimate']){
  await s.game('motion_frame_fixture',{action,frame:3});let state=await s.game();
  const resume=state.buttons.find(b=>b.text==='계속'&&!b.disabled);
  if(resume){await s.tap(resume.rect[0]+resume.rect[2]/2,resume.rect[1]+resume.rect[3]/2);await delay(120);await s.game('motion_frame_fixture',{action,frame:3});state=await s.game();}
  checks.push({pass:state.battle.actors.filter(a=>a.team==='PLAYER').every(a=>a.action_motion.redrawn&&a.action_motion.frame===3),name:action+' visible 640x360 attack pose'});
  await s.checkpoint(action);
 }
 await s.game('damage_fixture',{age:.05});await s.checkpoint('damage_numbers');
 checks.push({pass:s.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text)).length===0,name:'no small viewport runtime errors'});
 if(checks.some(c=>!c.pass))process.exitCode=1;
}finally{await s.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,scope:'Actual 640x360 renderer with held art and damage fixtures. No resize pause overlay is accepted as visual evidence.'},null,2));}
