import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9259']=process.argv.slice(2);
const session=new GameplaySession(output);
const checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const check=(value,name)=>{checks.push({name,pass:!!value});console.log(JSON.stringify(checks.at(-1)));if(!value)throw Error(name);};
const state=()=>session.game();
async function tapText(text){const s=await state();const b=s.buttons.find(b=>b.text===text&&!b.disabled);if(!b)throw Error('Missing button: '+text);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(300);}
async function ready(){for(let n=0;n<120;n++){const s=await state();if(s.screen==='STORY'){await tapText('SKIP  ▶');continue;}if(s.screen==='STAGE_SELECT'&&s.map?.ready)return s;await delay(500);}throw Error('Map ready timeout');}
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
  for(let n=0;n<90;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready'))break;await delay(1000);}
  let blockedTouchTests=0;
  for(const stage of [1,5,10,20]){
    await session.mark(`gallery_n${stage}_loading`);
    await session.game('prepare_contact',{stage_number:stage,invincible:false});
    let s=await ready();
    if(s.buttons.some(b=>b.text==='안내 건너뛰기'))await tapText('안내 건너뛰기');
    s=await state();
    if(s.buttons.some(b=>b.text==='선택 취소'&&!b.disabled))await tapText('선택 취소');
    await delay(700);
    await session.mark(`gallery_n${stage}_steady`);
    await session.checkpoint(`n${String(stage).padStart(2,'0')}_portrait`);
    s=await state();
    check(s.map.persistent_grid_cells>100&&s.map.persistent_grid_drawn>0,`N${stage} persistent cells remain after cancelling selection`);
    check(s.map.ready&&s.map.backdrop.present&&s.map.backdrop.instances>0,`N${stage} terrain and continuous backdrop are ready`);
    check(s.map.pawn_texture.width===192&&s.map.pawn_texture.height===192,`N${stage} actual map pawn uses its 192px animation sheet`);
    check(s.map.terrain_samples.filter(t=>t.type==='SHALLOW_WATER').every(t=>t.blocked&&!t.reachable),`N${stage} visible water is excluded from walking range`);
    const water=s.map.terrain_samples.find(t=>t.type==='SHALLOW_WATER'&&t.screen[0]>40&&t.screen[0]<350&&t.screen[1]>220&&t.screen[1]<740);
    if(water){
      const before=JSON.stringify(s.map.position);
      await session.tap(...water.screen);await delay(60);await session.tap(...water.screen);await delay(500);
      const after=await state();
      check(JSON.stringify(after.map.position)===before&&!after.map.moving&&!after.map.preview.some(p=>JSON.stringify(p)===JSON.stringify(water.coord)),`N${stage} actual double-touch cannot enter blocked water`);
      blockedTouchTests++;
    }
    await delay(4000);
    if(stage===1){
      const instance=s.map.instance_id;
      await session.resize(1280,720);await delay(1000);await session.checkpoint('n01_landscape');
      const landscape=await state();
      check(landscape.map.instance_id===instance&&landscape.map.viewport_rect[3]>720*.62,'N1 rotation retains the map and more than 62 percent landscape height');
      await session.resize(390,844);await delay(500);
    }
  }
  check(blockedTouchTests>0,'at least one visible river was tested with real touch input');
  const errors=session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:'));
  check(errors.length===0,'gallery has no Godot script/shader errors or warnings');
  const s=await state();check(s.sandbox.production_write_attempt_count===0&&s.sandbox.production_read_attempt_count===0,'map gallery uses isolated QA saves only');
}catch(error){checks.push({name:String(error),pass:false});console.error(error);process.exitCode=1;}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,fixture:'Reward-free staged contact positions for N01/N05/N10/N20; not a claim of traversing the entire campaign.'},null,2));}
