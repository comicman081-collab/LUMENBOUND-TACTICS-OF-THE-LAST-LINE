import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9463']=process.argv.slice(2);
const session=new GameplaySession(output), checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function check(ok,name){checks.push({name,pass:!!ok});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function tapText(text){const s=await session.game();const b=s.buttons.find(b=>b.text===text&&!b.disabled);if(!b)throw Error('Missing '+text);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(400);}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:360,height:640});
  for(let n=0;n<100&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(1000);
  await session.game('prepare_contact',{stage_number:9,invincible:false});
  for(let n=0;n<150;n++){
    const s=await session.game();
    if(s.screen==='STORY'){await tapText('SKIP  ▶');continue;}
    if(s.buttons.some(b=>b.text==='안내 건너뛰기')){await tapText('안내 건너뛰기');continue;}
    if(s.map?.ready)break;
    await delay(500);
  }
  await tapText('다음 조우');
  const instance=(await session.game()).map.instance_id;
  for(const [i,[w,h]] of [[360,640],[1280,720],[390,844],[915,412],[360,640],[1280,720]].entries()){
    await session.resize(w,h);await delay(1100);
    const s=await session.game(),m=s.map;
    await session.checkpoint(`selected_${i}_${w}x${h}`);
    check(m.persistent_grid_cells>100&&m.persistent_grid_drawn>0,`${w}x${h} persistent grid survives rotation`);
    check(m.instance_id===instance,`${w}x${h} retains map state`);
    check(m.toolbar_rect[3]<=65,`${w}x${h} toolbar is a single compact row (${m.toolbar_rect[3]}px)`);
    check(m.detail.visible&&m.detail.z>48,`${w}x${h} selected card is above character overlay`);
    const r=m.detail.rect;
    check(r[0]>=0&&r[1]>=0&&r[0]+r[2]<=w+2&&r[1]+r[3]<=h+2,`${w}x${h} selection stays inside viewport`);
    if(h>w){
      check(!s.buttons.some(b=>b.text==='파티 편성'),`${w}x${h} hides desktop formation action`);
      check(r[3]<=245,`${w}x${h} card height is capped (${r[3]}px)`);
      check(m.viewport_rect[3]>=h*.65,`${w}x${h} map keeps at least 65 percent height`);
    }else if(w>980){
      const formation=s.buttons.find(b=>b.text==='파티 편성');
      check(formation&&formation.rect[2]<150&&formation.rect[3]<65,'desktop formation resets after portrait');
      check(m.viewport_rect[3]>h*.7,'landscape map keeps at least 70 percent height');
    }else{
      check(m.toolbar_rect[3]<=36&&r[2]<=245&&r[3]<=211,'short landscape uses small toolbar and a compact decision card');
      check(r[0]>=w*.6&&r[1]>=m.toolbar_rect[1]+m.toolbar_rect[3]-1,'short landscape places card beside map and below toolbar');
      check(m.viewport_rect[2]>=w*.55&&m.viewport_rect[3]>=h*.60,'short landscape retains usable map width and height');
    }
    const cancel=s.buttons.find(b=>b.text==='선택 취소'&&!b.disabled);
    check(cancel&&cancel.rect[0]>=r[0]-1&&cancel.rect[1]>=r[1]-1&&cancel.rect[0]+cancel.rect[2]<=r[0]+r[2]+1&&cancel.rect[1]+cancel.rect[3]<=r[1]+r[3]+1,'selection cancel is fully visible inside card');
  }
  await tapText('선택 취소');await delay(400);
  check(!(await session.game()).map.detail.visible,'cancel hides selection card');
  const errors=session.logs(10000).filter(e=>e.type==='error'||e.text.includes('WARNING:'));
  check(errors.length===0,'no runtime errors or warnings');
  const s=await session.game();check(s.sandbox.production_write_attempt_count===0,'QA does not write production saves');
}catch(error){checks.push({name:String(error),pass:false});process.exitCode=1;console.error(error);}
finally{await session.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks},null,2));}
