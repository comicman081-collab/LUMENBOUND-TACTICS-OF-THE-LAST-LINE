import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,inputUrl,port='9481']=process.argv.slice(2);
const url=new URL(inputUrl);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','scout-siblings');
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function check(value,name){checks.push({pass:!!value,name});console.log(`${value?'PASS':'FAIL'} ${name}`);if(!value)throw Error(name);}
async function tap(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Missing button '+s.screen);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
async function bridge(){for(let n=0;n<180;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))return;await delay(500);}throw Error('Bridge unavailable');}
async function mapReady(){for(let n=0;n<220;n++){const s=await session.game();if(s.screen==='STAGE_SELECT'&&s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning&&!s.transition_loading.active)return s;await delay(300);}throw Error('Map did not settle');}
async function approach(id){await session.game('prepare_node_contact',{node_id:id});let s=await mapReady();for(let n=0;n<30&&!s.map.enemies.find(e=>e.id===id)?.visible;n++){await delay(150);s=await session.game();}check(s.map.enemies.find(e=>e.id===id)?.visible,id+' physical pawn remains visible');return s;}
async function fight(id,label){
 let s=await approach(id);await session.checkpoint(label+'_contact');
 await session.tap(...s.map.enemies.find(e=>e.id===id).screen);await delay(300);s=await session.game();
 check(s.map.selected_node===id,id+' can be selected independently');
 await tap(s,b=>b.text.includes('칸 이동'));
 let result=null,battle=false;
 for(let n=0;n<300;n++){
  s=await session.game();
  if(!s.transition_loading.active&&s.buttons.some(b=>b.name==='EventDialogueNext'&&!b.disabled))await tap(s,b=>b.name==='EventDialogueNext');
  if(s.battle?.ready)battle=true;
  if(s.screen==='RESULT'&&!s.transition_loading.active){result=s;break;}
  await delay(250);
 }
 check(battle&&result,id+' actual contact and natural AUTO battle reaches results');
 await tap(result,b=>b.text.includes('챕터 맵')||b.text==='지도로');s=await mapReady();
 check(s.map.cleared_nodes.includes(id)&&s.map.encounter_receipts[id],id+' exact kill receipt persisted');
 check(!s.map.enemies.some(e=>e.id===id&&e.visible),id+' defeated pawn is absent');
 await session.checkpoint(label+'_return');return s;
}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:url.href,port:Number(port),width:1128,height:635});await bridge();
 for(const order of [[1,2],[2,1]]){
  const label=order.join('_');
  await session.game('prepare_stage_contact',{stage_id:'CH01-N01',campaign_flow:true});await mapReady();
  const first='NODE_N01_SCOUT_'+order[0],second='NODE_N01_SCOUT_'+order[1];
  await approach(second);
  let s=await fight(first,label+'_first');
  check(!s.map.cleared_nodes.includes(second),label+' sibling has no false kill receipt');
  check(s.map.enemies.find(e=>e.id===second)?.visible,label+' sibling remains visible immediately after battle return');
  await session.checkpoint(label+'_survivor');
  // Reload directly: the ordinary victory transaction must have saved both
  // lives without a manual save or another fixture writing the profile.
  await session.send('Page.reload',{ignoreCache:true});await delay(1500);await bridge();
  await session.game('resume_saved_map');s=await mapReady();
  check(s.map.cleared_nodes.includes(first)&&!s.map.cleared_nodes.includes(second),label+' browser reload preserves separate lives');
  await approach(second);await session.checkpoint(label+'_reload_survivor');
  s=await fight(second,label+'_second');
  check(s.map.cleared_nodes.includes(first)&&s.map.cleared_nodes.includes(second),label+' both scouts require their own victory');
  check(!s.map.cleared_nodes.includes('NODE_N01'),label+' main encounter also survives shared stage victories');
  await approach('NODE_N01');await session.checkpoint(label+'_main_survivor');
 }
 const errors=session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text));check(errors.length===0,'No browser or engine errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,scope:'Two kill orders, four real AUTO battles, exact pawn visibility/selection/contact and two browser reloads in isolated saves.'},null,2));}
