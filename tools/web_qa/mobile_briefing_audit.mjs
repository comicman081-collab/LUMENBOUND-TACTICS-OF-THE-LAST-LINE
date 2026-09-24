import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9262']=process.argv.slice(2);
const stagesArgument=process.argv.find(arg=>arg.startsWith('--stages='));
const stageNumbers=stagesArgument?stagesArgument.slice(9).split(',').map(Number):[6,8,13];
if(stageNumbers.some(n=>![6,8,13].includes(n)))throw Error('Unsupported contact fixture');
const session=new GameplaySession(output), checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const state=()=>session.game();
function check(value,name){checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);}
const contained=r=>r[0]>=-1&&r[1]>=-1&&r[0]+r[2]<=session.viewport.width+1&&r[1]+r[3]<=session.viewport.height+1;
async function tapButton(predicate){const s=await state();const b=s.buttons.find(b=>predicate(b)&&!b.disabled&&contained(b.rect));if(!b)throw Error('Visible briefing action missing');await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(500);}
async function waitFor(predicate,seconds=90){for(let n=0;n<seconds*2;n++){const s=await state();if(predicate(s))return s;await delay(500);}throw Error('Briefing state timeout');}
const modal=(s,name='PreBattleEventDialog')=>s.modals?.find(m=>m.name===name);
const page=s=>modal(s)?.labels.find(l=>l.name==='EventDialoguePage')?.text;
async function verifyEvent(name){
  const s=await state(), m=modal(s);
  check(m&&contained(m.rect),`${name}: entire modal remains inside viewport`);
  for(const buttonName of ['EventDialogueNext','EventDialogueSkip']){
    const b=s.buttons.find(b=>b.name===buttonName);
    check(b&&contained(b.rect)&&b.rect[3]>=51&&b.rect[3]<=65,`${name}: ${buttonName} has a visible 52px-class hit target`);
  }
  check(m.labels.find(l=>l.name==='EventDialogueBody').font_css<=19,`${name}: body uses readable 18px type rather than oversized 42px`);
  check(m.labels.find(l=>l.name==='EventDialoguePage').rect[3]<24,`${name}: page counter stays on one line`);
  await session.checkpoint(name);
  return s;
}
async function mapReady(){
  for(let n=0;n<160;n++){
    const s=await state();
    if(s.screen==='STORY'){await tapButton(b=>b.name==='StorySkipButton');continue;}
    if(s.screen==='STAGE_SELECT'&&s.map?.ready)return s;
    await delay(500);
  }
  throw Error('Map did not become ready');
}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:360,height:800});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  await session.game('prepare_home_tutorial');
  await waitFor(s=>modal(s,'HomeFirstOperationTutorial'));
  await session.mark('home_tutorial');
  for(let p=1;p<=4;p++){
    let s=await state();
    check(contained(modal(s,'HomeFirstOperationTutorial').rect),`home tutorial ${p} is fully bounded at 360px`);
    await session.checkpoint(`home_${p}`);
    await tapButton(b=>b.name==='HomeTutorialContinueButton');
  }
  await mapReady();
  await session.mark('first_map_tutorial');
  for(let p=1;p<=3;p++){
    const s=await state(), m=modal(s,'FirstMapTutorial');
    check(m&&contained(m.rect),`map tutorial ${p} is fully bounded at 360px`);
    const scroll=s.scrolls.find(x=>x.name==='MapTutorialBodyScroll');
    if(scroll.max>scroll.page+2){
      const r=scroll.rect;
      await session.swipe(r[0]+r[2]/2,r[1]+r[3]-12,r[1]+12,650);
      const after=await state();
      const settled=after.scrolls.find(x=>x.name==='MapTutorialBodyScroll');
      // RichTextLabel's fitted height settles after the new page text. A short
      // second page may cease overflowing between the probe and the gesture.
      check(settled.max<=settled.page+2||settled.value>scroll.value,`map tutorial ${p} overflow is touch-readable or the complete copy fits`);
      check(modal(after,'FirstMapTutorial').labels.map(l=>l.text).join('|')===m.labels.map(l=>l.text).join('|'),`map tutorial ${p} drag does not skip instructions`);
    }
    await session.checkpoint(`map_tutorial_${p}`);
    await tapButton(b=>b.text.startsWith('클릭 / 터치하여'));
  }
  check(!modal(await state(),'FirstMapTutorial'),'three explicit map continue taps complete the tutorial');
  for(const stage of stageNumbers){
    await session.mark(`n${stage}_contact_loading`);
    await session.game('prepare_contact',{stage_number:stage,invincible:true});
    await mapReady();
    let s=await state();
    if(!s.buttons.some(b=>b.text.includes('1칸 이동')))await tapButton(b=>b.text==='다음 조우');
    await tapButton(b=>b.text.includes('1칸 이동'));
    await waitFor(s=>modal(s));
    await session.mark(`n${stage}_briefing`);
    await verifyEvent(`n${stage}_360_page1`);
    const initialPage=page(await state());
    await session.resize(800,360);await delay(1500);
    s=await verifyEvent(`n${stage}_landscape_page1`);
    check(page(s)===initialPage,`N${stage} rotation preserves the unread page`);
    const scroll=s.scrolls.find(x=>x.name==='BriefingBodyScroll'), r=scroll.rect;
    await session.swipe(r[0]+r[2]/2,r[1]+r[3]-15,r[1]+15,650);
    s=await state();
    check(page(s)===initialPage,`N${stage} reading drag does not advance the encounter`);
    if(scroll.max>scroll.page+2)check(s.scrolls.find(x=>x.name==='BriefingBodyScroll').value>scroll.value,`N${stage} landscape overflow scrolls by touch`);
    await session.checkpoint(`n${stage}_landscape_scrolled`);
    await session.resize(390,844);await delay(1500);
    await verifyEvent(`n${stage}_390_page1`);
    await tapButton(b=>b.name==='EventDialogueNext');
    check(page(await state())==='2 / 3',`N${stage} a single Next tap advances exactly one page`);
    await verifyEvent(`n${stage}_390_page2`);
    await session.resize(360,640);await delay(1500);
    await verifyEvent(`n${stage}_short_portrait_page2`);
    if(stage===8){
      await tapButton(b=>b.name==='EventDialogueSkip');
    }else{
      await tapButton(b=>b.name==='EventDialogueNext');
      check(page(await state())==='3 / 3',`N${stage} final instruction is reachable`);
      await verifyEvent(`n${stage}_short_portrait_page3`);
      await tapButton(b=>b.name==='EventDialogueNext');
    }
    checkFullDensity(await waitFor(s=>s.screen==='BATTLE'&&s.battle?.ready,90),check);
    check(!modal(await state()),`N${stage} ${stage===8?'Skip':'Continue'} enters real combat and closes its modal`);
    await session.resize(390,844);await delay(1000);
    await session.checkpoint(`n${stage}_combat`);
    // Finish each real transaction before staging another contact. Jumping
    // away mid-battle correctly fails the next transaction's entry guard.
    await tapButton(b=>b.name==='BattleSpeedButton');
    const result=await waitFor(s=>s.screen==='RESULT',150);
    check(result.result.victory,`N${stage} actual combat reaches victory after its briefing`);
    await session.checkpoint(`n${stage}_victory`);
    if(stage===13){
      await tapButton(b=>b.text==='챕터 맵으로');
      s=await mapReady();check(s.map.next==='CH01-N14','N13 victory reconnects to N14 without a dead end');
    }
    await session.resize(360,800);await delay(1000);
  }
  const s=await state();
  check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'briefing/touch/rotation/combat produce no Godot errors or warnings');
  check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,'tutorial and encounter fixtures never access production saves');
}catch(error){checks.push({name:String(error),pass:false});console.error(error);process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,stage_numbers:stageNumbers,fixture:'Fresh localhost sandbox; real home/map instruction taps, listed stage-neighbor contacts, scrolling, rotation and combat. Not physical-phone evidence.'},null,2));}
