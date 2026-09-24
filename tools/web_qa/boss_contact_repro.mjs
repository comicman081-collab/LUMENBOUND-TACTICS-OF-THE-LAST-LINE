import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9450']=process.argv.slice(2);
const session=new GameplaySession(output),states=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
try {
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:936,height:526});
 for(let n=0;n<180&&!await session.evaluate('!!window.__localGameplayQA?.ready');n++)await delay(500);
 await session.game('prepare_contact',{stage_number:20,invincible:true});
 let clicks=0,ready=false;
 for(let n=0;n<150;n++) {
  const s=await session.game();
  states.push(s);
  if(s.battle?.ready){ready=true;break;}
  const buttons=s.buttons.filter(b=>!b.disabled&&b.rect[0]>=0&&b.rect[1]>=0&&b.rect[0]+b.rect[2]<=937&&b.rect[1]+b.rect[3]<=527);
  let b=buttons.find(b=>b.name==='EventDialogueNext'||b.text==='안내 건너뛰기');
  if(s.screen==='STORY')b??=buttons.find(b=>b.text==='다음');
  if(s.screen==='STAGE_SELECT'&&s.map?.ready&&!s.map?.moving&&!s.map?.turn_transitioning){
   b??=buttons.find(b=>b.text.includes('1칸 이동'))??buttons.find(b=>b.text==='다음 조우');
  }
  if(b&&(clicks<8||s.screen==='STORY')){console.log('CLICK',b.text);await session.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);if(s.screen!=='STORY')clicks++;await delay(700);}
  if(n>20&&clicks>=8)break;
  await delay(400);
 }
 await session.checkpoint(ready?'contact_battle':'contact_stalled');
 const last=states.at(-1);
 console.log(JSON.stringify({ready,clicks,screen:last.screen,map:last.map,errors:session.logs(1000).filter(e=>e.type==='error'||/SCRIPT ERROR/.test(e.text))}));
 await writeFile(path.join(output,'reproduction.json'),JSON.stringify({ready,clicks,states,logs:session.logs(10000)},null,2));
 if(!ready)process.exitCode=1;
}finally{await session.close();}
