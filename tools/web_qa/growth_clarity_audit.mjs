import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9551']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name){checks.push({pass:!!ok,name});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function boot(){for(let i=0;i<120;i++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))return;await delay(1000);}throw Error('boot timeout');}
async function tap(match){
 for(let i=0;i<35;i++){
  const s=await session.game(),b=s.buttons.find(match);
  if(!b)throw Error('missing control');
  if(b.disabled)throw Error('disabled control '+b.text);
  const bottom=session.viewport.height-6;
  if(b.rect[1]>=Math.max(80,s.scrolls[0]?.rect[1]||0)&&b.rect[1]+b.rect[3]<bottom){await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(450);return;}
  const down=b.rect[1]+b.rect[3]>=bottom;
  await session.swipe(session.viewport.width*.88,down?bottom-20:120,down?160:bottom-20,350);await delay(200);
 }
 throw Error('could not scroll to control');
}
const text=async t=>{const s=await session.game();if(s.buttons.some(b=>b.text===t&&b.disabled))return;await tap(b=>b.text===t);};
async function fixture(mode){await session.game('prepare_growth',{mode});await delay(600);}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:844,height:390});await boot();
 await fixture('funded');await session.checkpoint('level_before');
 let s=await session.game();const before=structuredClone(s.growth);
 check(s.buttons.filter(b=>['레벨업','스킬업','장비·돌파','캐릭터 정보'].includes(b.text)).every(b=>b.rect[2]>150),'growth tabs use full columns instead of narrow text boxes');
 check(s.buttons.filter(b=>b.text.includes('경험치 +')).every(b=>b.rect[2]>140),'training material labels have readable column widths');
 check(s.growth.labels.some(l=>l.text.includes('필요')&&l.text.includes('보유')),'cost and balance are adjacent to the action');
 await tap(b=>b.name==='GrowthLevelApply');s=await session.game();
 check(s.growth.progress.level>before.progress.level||s.growth.progress.xp>before.progress.xp,'real touch applies level or EXP');
 check(s.growth.inventory.TRAINING_NOTE_S===before.inventory.TRAINING_NOTE_S-1,'one selected note consumed');
 check(s.growth.feedback.includes('저장 완료'),'visible success and saved feedback');
 await text('스킬업');s=await session.game();const skillBefore=structuredClone(s.growth);
 await session.checkpoint('skill_before');await tap(b=>b.name==='GrowthSkillApply_normal');s=await session.game();
 check(s.growth.progress.skills.normal===skillBefore.progress.skills.normal+1,'real skill control upgrades one level');
 check(s.growth.tab==='스킬업'&&s.growth.feedback.includes('강화 완료'),'skill tab and readable result survive refresh');
 const saved=structuredClone(s.growth);
 await session.evaluate('setTimeout(()=>location.reload(),0);true');await delay(1500);await boot();await fixture('resume');s=await session.game();
 check(JSON.stringify(s.growth.progress)===JSON.stringify(saved.progress),'browser reload preserves individual growth');
 check(JSON.stringify(s.growth.inventory)===JSON.stringify(saved.inventory),'browser reload preserves exact paid inventory');
 for(const [width,height] of [[640,360],[915,412],[1280,720]]){
  await session.resize(width,height);await delay(750);await text('스킬업');s=await session.game();
  const visible=s.growth.labels.filter(l=>l.rect[1]>=0&&l.rect[1]+l.rect[3]<=height);
  check(visible.length>0&&visible.every(l=>l.rect[0]>=-1&&l.rect[0]+l.rect[2]<=width+1),`reading stays within ${width}x${height}`);
  await session.checkpoint(`skills_${width}x${height}`);
 }
 await session.resize(844,390);await fixture('empty');await text('레벨업');s=await session.game();
 check(s.buttons.find(b=>b.name==='GrowthLevelApply').disabled,'missing training notes cannot be spent');
 check(s.growth.labels.some(l=>l.text.includes('부족')),'numeric shortage is explicit');
 await text('스킬업');s=await session.game();
 check(s.buttons.filter(b=>b.name.startsWith('GrowthSkillApply_')).every(b=>b.disabled),'missing skill materials cannot be spent');
 await session.checkpoint('skills_insufficient');
 await fixture('cap');await text('레벨업');s=await session.game();
 check(s.buttons.find(b=>b.name==='GrowthLevelApply').disabled&&s.growth.labels.some(l=>l.text.includes('돌파가 필요')),'breakthrough cap explains the next step');
 await fixture('fixed');await text('스킬업');s=await session.game();
 check(s.buttons.find(b=>b.name==='GrowthSkillApply_ultimate').disabled,'fixed effect does not sell a meaningless upgrade');
 check(s.growth.labels.some(l=>l.text.includes('공격 속도 +20%')),'fixed effect matches real battle behavior');
 check(s.sandbox.production_read_attempt_count===0&&s.sandbox.production_write_attempt_count===0,'only isolated saves touched');
 check(session.logs(10000).filter(e=>e.type==='error').length===0,'no runtime errors');
}catch(e){checks.push({pass:false,name:String(e)});console.error(e);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,scope:'Real UI taps and browser reload using isolated earned-material fixtures; not a physical device.'},null,2));}
