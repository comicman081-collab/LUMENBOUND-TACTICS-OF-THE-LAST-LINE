import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url,port='9641']=process.argv.slice(2),s=new GameplaySession(output),checks=[];
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,name){checks.push({pass:!!ok,name});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function tapMatch(match){const v=await s.game(),b=v.buttons.find(b=>match(b)&&!b.disabled);if(!b)throw Error('Missing action '+JSON.stringify(v.buttons));await s.tap(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2);await wait(550);}
try {
 await s.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:844,height:390});
 for(let i=0;i<120;i++){if(await s.evaluate('!!window.__localGameplayQA?.ready'))break;await wait(1000);}
 await s.game('prepare_region',{chapter_number:2});
 for(let i=0;i<100;i++){let v=await s.game();if(v.map?.ready)break;if(v.screen==='STORY')await tapMatch(b=>b.text==='다음');else await wait(600);}
 let v=await s.game();check(v.map?.ready&&v.map.natural_terrain,'CH02 retains natural terrain');
 const event=v.map.field_events.find(e=>e.id==='FIELD_CH02_ENTRY');check(event?.visible&&event.state==='DISCOVERED','entry clue is physically discovered');check(v.map.field_events.find(e=>e.id==='FIELD_CH02_EVIDENCE').state==='UNDISCOVERED','later evidence stays hidden');
 await s.tap(...event.screen);await wait(650);await s.checkpoint('field_detail');
 for(let i=0;i<5;i++){v=await s.game();if(v.buttons.some(b=>b.text.includes('훈련 노트')&&!b.disabled))break;await tapMatch(b=>b.text.includes('이동')&&!b.text.includes('지역'));await wait(1000);}
 v=await s.game();const before=v.map.training_notes;await tapMatch(b=>b.text.includes('훈련 노트'));await wait(650);
 v=await s.game();check(v.screen==='RESULT'||v.map?.field_events.find(e=>e.id==='FIELD_CH02_ENTRY').state==='RESOLVED','actual choice commits field reward');await s.checkpoint('field_reward');
 if(v.screen==='RESULT')await tapMatch(b=>b.text.includes('챕터 맵'));
 for(let i=0;i<60;i++){v=await s.game();if(v.map?.ready)break;await wait(500);}
 check(v.map.training_notes===before+2,'exact two notes persist on map return');
 await s.send('Page.reload',{ignoreCache:false});
 for(let i=0;i<120;i++){if(await s.evaluate('!!window.__localGameplayQA?.ready'))break;await wait(1000);}
 // Load the saved profile using the existing resume fixture, then return through the public header.
 await s.game('prepare_growth',{mode:'resume'});await s.checkpoint('saved_growth');
 v=await s.game();check(v.growth.inventory.TRAINING_NOTE_S===before+2,'reload retains the field reward');
 await s.game('prepare_region',{chapter_number:2});
 for(let i=0;i<100;i++){v=await s.game();if(v.map?.ready)break;if(v.screen==='STORY')await tapMatch(b=>b.text==='다음');else await wait(500);}
 await tapMatch(b=>b.text==='지역');await s.checkpoint('region_objectives');v=await s.game();
 check(v.modals.some(m=>m.name==='RegionTravelOverlay'&&m.labels.some(l=>l.text.includes('작전 완료'))),'region menu explains objective and progress');
 check(v.buttons.some(b=>b.name==='Travel_CH03'&&b.disabled),'locked region cannot be entered');
 check(!s.logs(10000).some(e=>e.type==='error'),'no runtime errors');
} catch(e){checks.push({pass:false,name:String(e)});console.error(e);await s.checkpoint('failure').catch(()=>{});process.exitCode=1;}
finally{await s.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks},null,2));}
