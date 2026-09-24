import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9438']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const check=(ok,name,detail)=>{checks.push({ok,name,detail});console.log(ok?'PASS':'FAIL',name);};
async function press(b){if(!b)throw Error('Required button missing');await session.click(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await delay(450);}
async function snap(name){const s=await session.game();await session.screenshot(name);return s;}
try{
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:634,height:357});
  for(let n=0;n<150&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
  await session.game('presentation_screen',{screen:'FORMATION'});
  let s=await snap('formation_initial'),original=[...s.party];
  await press(s.buttons.find(b=>b.name==='FormationSlot_0'));
  s=await session.game();
  await press(s.buttons.find(b=>b.name==='CharacterCard_'+original[1]));
  s=await snap('formation_swapped');
  check(s.party[0]===original[1]&&s.party[1]===original[0]&&new Set(s.party).size===5,'selecting an occupied character swaps the two slots without duplicates',s.party);
  const changed=[...s.party];
  await press(s.buttons.find(b=>b.text==='편성 저장'));
  s=await session.game();
  await press(s.buttons.find(b=>b.text==='편성 2'));
  s=await session.game();
  check(s.active_party===1,'second preset selected');
  await press(s.buttons.find(b=>b.text==='편성 1'));
  s=await session.game();
  check(s.active_party===0&&JSON.stringify(s.party)===JSON.stringify(changed),'returning to first preset retains its composition',s.party);
  await session.game('presentation_screen',{screen:'HOME'});
  await session.game('presentation_screen',{screen:'FORMATION'});
  s=await session.game();
  check(JSON.stringify(s.party)===JSON.stringify(changed),'saved composition persists across screen navigation');
  await session.game('presentation_screen',{screen:'GROWTH'});
  for(const [tab,name] of [['스킬업','skills'],['장비·돌파','equipment'],['캐릭터 정보','information'],['레벨업','level']]){
    s=await session.game();await press(s.buttons.find(b=>b.text===tab));s=await snap('growth_'+name);
    for(const b of s.buttons.filter(b=>b.nowrap&&!b.disabled&&b.rect[1]>=0&&b.rect[1]+b.rect[3]<=357)){
      check(b.text_width<=b.content_width+1,`${name}: ${b.name} label fits`,b);
    }
    check(s.screen==='GROWTH',`${name}: tab remains in character screen`);
  }
  const production=Object.entries(s.sandbox).filter(([k])=>k.startsWith('production_'));
  check(production.length>=5&&production.every(([,v])=>v===0),'no access to real player saves',s.sandbox);
  const logs=session.logs(1000),errors=logs.filter(x=>/SCRIPT ERROR|Parse Error|Invalid call/.test(x.text));
  check(errors.length===0,'no Godot runtime errors',errors);
  await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,passed:checks.every(c=>c.ok),logs},null,2));
  console.log('PARTY_AUDIT',checks.filter(c=>c.ok).length,'/',checks.length);
  if(checks.some(c=>!c.ok))process.exitCode=1;
}finally{await session.close().catch(()=>{});}
