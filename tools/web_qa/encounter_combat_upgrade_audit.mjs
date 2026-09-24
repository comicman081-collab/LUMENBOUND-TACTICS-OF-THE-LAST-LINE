import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,inputUrl,port='9460',width='936',height='526']=process.argv.slice(2);
const url=new URL(inputUrl);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','encounter-combat-upgrade');
const session=new GameplaySession(output),checks=[],timeline=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(value,name){checks.push({pass:!!value,name});if(!value)throw Error(name);}
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Missing button '+s.screen);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function mapReady(){for(let n=0;n<220;n++){const s=await session.game();if(s.screen==='STAGE_SELECT'&&s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning&&!s.transition_loading.active)return s;await delay(400);}throw Error('Map did not settle');}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:url.href,port:Number(port),width:Number(width),height:Number(height)});
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 await session.game('prepare_stage_contact',{stage_id:'CH01-N04',campaign_flow:true});
 let s=await mapReady();
 check(s.map.terraced_terrain&&!s.map.natural_terrain,'Tactical height mesh selected');
 const scout=Object.keys(s.map.patrol_states).find(id=>id.includes('N04')&&id.endsWith('SCOUT_1'));
 check(scout,'Independent nearby scout exists');
 const canonical=scout.replace(/_SCOUT_1$/,'');
 const fixture=await session.game('prepare_treasure_contact');
 s=await mapReady();
 const treasure=s.map.treasures.find(t=>t.id===fixture.treasure_id);
 check(treasure?.visible,'Unclaimed treasure is visible');
 await session.tap(...treasure.screen);await delay(400);s=await session.game();
 const travel=s.buttons.find(b=>!b.disabled&&b.text.includes('칸 이동'));
 if(travel)await tap(s,b=>b===travel);else await session.tap(...treasure.screen);
 let claimed=false;
 for(let n=0;n<80;n++){
  s=await session.game();
  if(s.buttons.some(b=>!b.disabled&&/보상 확인|지도 계속/.test(b.text))){await session.checkpoint('treasure_reward');await tap(s,b=>/보상 확인|지도 계속/.test(b.text));}
  if(s.map?.treasures.some(t=>t.id===treasure.id&&t.state==='CLAIMED')){claimed=true;break;}
  await delay(300);
 }
 check(claimed,'Actual treasure movement and reward completes');
 s=await mapReady();
 check(!s.map.treasures.find(t=>t.id===treasure.id).visible,'Claimed treasure disappears');
 check(!s.map.cleared_nodes.includes(canonical)&&!s.map.cleared_nodes.includes(scout),'Treasure never removes either live monster');
 await session.game('prepare_node_contact',{node_id:scout});
 s=await mapReady();await session.checkpoint('terraced_map_before_contact');
 let enemy=s.map.enemies.find(e=>e.id===scout);
 check(enemy?.visible,'Exact scout visible at real physical position');
 await session.tap(...enemy.screen);await delay(400);s=await session.game();
 check(s.map.selected_node===scout,'Selecting the pawn targets its exact node identity');
 await tap(s,b=>b.text.includes('칸 이동'));
 let result=null,seenContact=false,seenFormation=false,seenKill=false;
 for(let n=0;n<240;n++){
  s=await session.game();
  if(s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled))await tap(s,b=>b.name==='EventDialogueNext');
  if(s.battle?.ready){
   const b=s.battle;
   timeline.push({time:b.time,wave:b.wave,contacts:b.contact_commits,queue:b.contact_queue,readout:b.combat_readout,actors:b.actors.map(a=>({id:a.id,hp:a.hp,foot:a.foot,action:a.motion_track.name}))});
   if(!seenFormation&&b.time>1){seenFormation=true;await session.checkpoint('engaged_frontline');}
   if(!seenContact&&b.contact_commits>0&&b.damage_numbers.length){seenContact=true;await session.checkpoint('contact_and_damage');}
   if(!seenKill&&b.combat_readout){seenKill=true;await session.checkpoint('explosion_cause');}
  }
  if(s.screen==='RESULT'&&!s.transition_loading.active){result=s;break;}
  await delay(250);
 }
 check(result,'Real AUTO combat reaches results');
 check(seenContact&&seenFormation,'Observed advancing formation and committed impact numbers');
 check(result.restart_progress.first_clear['CH01-N04'],'Actual victory awarded stage progress');
 await tap(result,b=>b.text.includes('챕터 맵')||b.text==='지도로');
 s=await mapReady();
 check(s.map.cleared_nodes.includes(scout),'Only defeated scout removed');
 check(!s.map.cleared_nodes.includes(canonical),'Monster #1 survives killing monster #2');
 check(s.map.encounter_receipts[scout],'Exact encounter has durable victory receipt');
 check(s.map.treasures.find(t=>t.id===treasure.id).state==='CLAIMED','Treasure state survives battle return');
 await session.checkpoint('surviving_monsters_after_battle');
 await tap(s,b=>b.text.includes('뒤로'));
 s=await session.game();
 const save=s.buttons.find(b=>b.text.includes('저장')&&!b.disabled);if(save)await tap(s,b=>b===save);
 await session.send('Page.reload',{ignoreCache:true});await delay(1500);
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 await session.game('resume_saved_map');s=await mapReady();
 check(s.map.cleared_nodes.includes(scout)&&!s.map.cleared_nodes.includes(canonical),'Browser reload preserves exact kill and surviving monster');
 check(s.map.treasures.find(t=>t.id===treasure.id).state==='CLAIMED','Browser reload preserves claimed treasure');
 await session.checkpoint('saved_encounter_identity');
 const errors=session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text));
 check(errors.length===0,'No browser or engine runtime errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,timeline,scope:'Isolated disposable save; actual treasure movement, exact scout contact, natural AUTO fight and reward return; no forced victory.'},null,2));}
