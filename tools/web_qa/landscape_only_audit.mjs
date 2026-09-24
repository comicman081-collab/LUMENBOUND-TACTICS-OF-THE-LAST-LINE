import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9621']=process.argv.slice(2),s=new GameplaySession(output),checks=[];
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name){checks.push({pass:!!ok,name});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function tap(t){const v=await s.game(),b=v.buttons.find(b=>b.text===t&&!b.disabled);if(!b)throw Error('missing '+t);await s.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await wait(450);}
async function layout(name){let v=await s.game();check(!v.layout.portrait&&v.layout.viewport[0]>v.layout.viewport[1]&&!v.layout.rotation_prompt&&!v.layout.paused,name+' is running in landscape without a prompt');return v;}
async function host(){return (await s.send('Runtime.evaluate',{expression:`(() => {const f=document.getElementById('landscape-game'),r=f.getBoundingClientRect();return {rotated:f.dataset.rotated,width:f.clientWidth,height:f.clientHeight,rect:[r.x,r.y,r.width,r.height]};})()`,returnByValue:true})).result.value;}
try{
 await s.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:390,height:844});
 await s.send('Network.setUserAgentOverride',{userAgent:'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/128.0.0.0 Mobile Safari/537.36',platform:'Linux armv8l'});
 await s.send('Page.reload',{ignoreCache:true});
 for(let i=0;i<120;i++){if(await s.evaluate('!!window.__localGameplayQA?.ready'))break;await wait(1000);}
 let h=await host();check(h.rotated==='1'&&h.width===844&&h.height===390&&h.rect[2]>=389&&h.rect[3]>=843,'portrait handset gets a full-size sideways landscape frame');
 await s.game('prepare_growth',{mode:'funded'});await wait(600);await tap('스킬업');
 let first=await layout('Portrait handset growth');await s.checkpoint('growth_sideways');
 check(first.growth.tab==='스킬업','real sideways touch selects the correct tab');
 await s.resize(844,390);await wait(750);let normal=await layout('Landscape growth');h=await host();check(h.rotated==='0'&&normal.growth.tab===first.growth.tab,'turning the phone keeps the selected tab and removes display rotation');await s.checkpoint('growth_landscape');
 await s.game('prepare_region',{chapter_number:2});
 for(let i=0;i<90;i++){if((await s.game()).screen==='STORY')break;await wait(500);}
 let story=await layout('Story');check(story.screen==='STORY','chapter introduction opens');
 await s.resize(390,844);await wait(700);let sideways=await layout('Sideways story');check(sideways.story.scenario===story.story.scenario,'rotation retains the live scenario');await s.checkpoint('story_sideways');
 for(let i=0;i<140;i++){const v=await s.game();if(v.map?.ready)break;if(v.screen==='STORY')await tap('다음');else await wait(500);}
 let map=await layout('Sideways map');check(map.map?.ready&&map.map.persistent_grid_drawn>0,'sideways map and grid are visible');await s.checkpoint('map_sideways');
 await s.resize(915,412);await wait(900);let rotated=await layout('Landscape map');check(rotated.map.instance_id===map.map.instance_id&&JSON.stringify(rotated.map.position)===JSON.stringify(map.map.position),'orientation change keeps map instance and position');await s.checkpoint('map_landscape');
 check(s.logs(10000).filter(e=>e.type==='error').length===0,'no runtime errors');
}catch(e){checks.push({pass:false,name:String(e)});console.error(e);await s.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await s.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks},null,2));}
