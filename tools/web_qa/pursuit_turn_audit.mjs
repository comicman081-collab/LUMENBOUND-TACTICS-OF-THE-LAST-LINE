import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,inputUrl,port='9462']=process.argv.slice(2),q=new URL(inputUrl);
q.searchParams.set('gameplay-qa','1');q.searchParams.set('qa','pursuit-turns');
const session=new GameplaySession(output),checks=[],turns=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const distance=(a,b)=>Math.max(Math.abs(a[0]-b[0]),Math.abs(a[1]-b[1]),Math.abs(a[0]+a[1]-b[0]-b[1]));
function check(v,name){checks.push({pass:!!v,name});if(!v)throw Error(name);}
async function tap(b){await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:q.href,port:Number(port),width:936,height:526});
 for(let i=0;i<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');i++)await delay(500);
 await session.game('prepare_fresh_first_map');
 let s;
 for(let i=0;i<160;i++){
  s=await session.game();
  if(s.screen==='STORY'){const skip=s.buttons.find(b=>b.text.startsWith('SKIP')&&!b.disabled);if(skip)await tap(skip);await delay(400);continue;}
  if(s.map?.tutorial?.visible){const r=s.map.tutorial.continue;await session.tap(r[0]+r[2]/2,r[1]+r[3]/2);await delay(400);continue;}
  if(s.map?.ready&&!s.map.turn_transitioning&&!s.transition_loading.active)break;
  await delay(400);
 }
 check(s.map?.ready,'Fresh map finishes its authored introduction');
 const player=s.map.position.slice();
 const enemies=Object.entries(s.map.patrol_states).filter(([id,r])=>!s.map.cleared_nodes.includes(id)&&distance([r.q,r.r],player)<=8).sort((a,b)=>distance([a[1].q,a[1].r],player)-distance([b[1].q,b[1].r],player));
 check(enemies.length>0,'Fresh map has visible patrols near the player');
 const id=enemies[0][0];let prior=distance([enemies[0][1].q,enemies[0][1].r],player);
 await session.checkpoint('before_enemy_turn');
 for(let turn=0;turn<3;turn++){
  const wait=s.buttons.find(b=>b.text==='대기'&&!b.disabled);check(wait,'Wait ends player turn '+turn);await tap(wait);
  for(let n=0;n<100;n++){s=await session.game();if(s.screen==='BATTLE'||(s.map?.ready&&!s.map.turn_transitioning&&!s.map.moving))break;await delay(150);}
  if(s.screen==='BATTLE'){check(prior<=1,'Enemy enters battle only after reaching player');break;}
  const r=s.map.patrol_states[id],next=distance([r.q,r.r],player);
  turns.push({turn,id,fromDistance:prior,toDistance:next,coord:[r.q,r.r],camera:s.map.enemy_camera_history});
  check(next<prior,'Enemy closes distance instead of oscillating on turn '+turn);
  check(s.map.position.join(',')===player.join(','),'Waiting does not move the player '+turn);
  prior=next;await session.checkpoint('pursuit_turn_'+turn);
 }
 check(turns.length>=2,'Observed pursuit across multiple real player turns');
 check(turns.some(t=>t.camera.length>0),'Enemy movement has camera tracking history');
 check(session.logs(10000).filter(e=>e.type==='error'||/SCRIPT ERROR|Parse Error/.test(e.text)).length===0,'No runtime errors');
}catch(e){checks.push({pass:false,name:String(e)});console.error(e);await session.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,turns},null,2));}
