import {GameplaySession} from './gameplay_session.mjs';
import {checkFullDensity} from './full_density_checks.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9441']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[],captures=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(ok,name){checks.push({pass:!!ok,name});if(!ok)throw Error(name);}
async function click(name){
 const s=await session.game(),b=s.buttons.find(b=>b.name===name&&!b.disabled);
 check(b&&b.rect[0]>=0&&b.rect[1]>=0&&b.rect[0]+b.rect[2]<=session.viewport.width+1&&b.rect[1]+b.rect[3]<=session.viewport.height+1,name+' fully visible');
 await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(350);
}
async function battle(stage){
 await session.game('prepare_art_stage',{stage_id:stage});
 let s;
 for(let n=0;n<240;n++){s=await session.game();if(s.screen==='BATTLE'&&s.stage===stage&&s.battle?.ready)return s;await delay(350);}
 throw Error('Battle failed to become ready: '+stage);
}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1280,height:720});
 for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
 await session.game('restart_fixture');await delay(400);
 const prior=(await session.game()).restart_progress;
 await click('TitleNewGameButton');
 await session.checkpoint('new_game_confirmation_1280');
 await click('NewGameCancelButton');
 check(JSON.stringify((await session.game()).restart_progress)===JSON.stringify(prior),'cancel preserves all seeded progress');
 await session.resize(640,360);await delay(1200);
 await session.checkpoint('title_640');
 await click('TitleNewGameButton');
 await session.checkpoint('new_game_confirmation_640');
 await click('NewGameConfirmButton');
 let s;
 for(let n=0;n<80;n++){s=await session.game();if(s.screen==='STORY')break;await delay(300);}
 check(s.screen==='STORY','real new game button enters prologue');
 check(Object.keys(s.restart_progress.stars).length===0&&Object.keys(s.restart_progress.first_clear).length===0&&s.restart_progress.character_level===1,'new game clears progression and resets growth');
 await session.checkpoint('fresh_prologue_640');
 await session.send('Page.reload',{ignoreCache:true});
 for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
 s=await session.game();
 check(Object.keys(s.restart_progress.stars).length===0&&s.restart_progress.character_level===1,'fresh game persists through browser reload');
 for(const width of [1280,640]){
  await session.resize(width,width*9/16);await delay(800);
  s=await battle('CH01-N01');checkFullDensity(s,check);
  for(const actor of s.battle.actors)check(actor.source_asset_id.includes('_spritegen_'),actor.id+' actual renderer selects redrawn source');
  await session.game('damage_fixture',{age:.04});await delay(200);
  s=await session.game();
  const numbers=s.battle.damage_numbers;
  check(numbers.length>=3,width+' damage render has player and enemy targets');
  for(const n of numbers){
   check(n.font==='Lantern Rounded Black'&&n.font_css>=20,width+' rounded readable '+n.text);
   check(n.position[1]<n.head[1],width+' number above impacted head '+n.text);
   check(n.position[0]-n.width_css/2>=0&&n.position[0]+n.width_css/2<=width,width+' number horizontally contained '+n.text);
  }
  const normal=numbers.find(n=>!n.crit),crit=numbers.find(n=>n.crit);
  check(crit.font_css>normal.font_css*1.3,width+' critical visibly larger than normal');
  await session.checkpoint('damage_'+width);
  captures.push({width,numbers});
  await session.game('damage_fixture',{age:.3});
  const settled=(await session.game()).battle.damage_numbers.find(n=>n.crit);
  check(crit.pop>settled.pop&&settled.pop===1,width+' critical pop settles');
 }
 await session.resize(1280,720);await delay(700);
 s=await battle('CH01-N20');checkFullDensity(s,check);
 await session.game('art_boss_wave');await delay(600);
 s=await session.game();
 check(s.battle.actors.some(a=>a.id==='BOSS001'&&a.source_asset_id.includes('_spritegen_')),'original cathedral boss replaced in actual final wave');
 await session.checkpoint('redrawn_boss');
 check(session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:')).length===0,'no runtime or asset errors');
 check(s.sandbox.production_read_attempt_count===0&&s.sandbox.production_write_attempt_count===0,'all actions isolated from player saves');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,captures,scope:'Real title cancel/confirm and browser reload; authored encounter loading; held damage/boss art fixtures for geometry inspection.'},null,2));}
