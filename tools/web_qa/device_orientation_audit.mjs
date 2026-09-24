import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [output,url]=process.argv.slice(2),s=new GameplaySession(output),checks=[];
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const desktop='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36';
function check(ok,name,state){checks.push({pass:!!ok,name,state});console.log(JSON.stringify(checks.at(-1)));if(!ok)throw Error(name);}
async function host(){return (await s.send('Runtime.evaluate',{expression:`(()=>{const f=document.getElementById('landscape-game');if(!f)return null;const r=f.getBoundingClientRect();return {rotated:f.dataset.rotated,deviceClass:f.dataset.deviceClass,width:f.clientWidth,height:f.clientHeight,rect:[r.x,r.y,r.width,r.height]};})()`,returnByValue:true})).result.value;}
async function setup(name,ua,platform,touch,width,height,rotated){
 await s.send('Network.setUserAgentOverride',{userAgent:ua,platform});
 await s.send('Emulation.setTouchEmulationEnabled',{enabled:touch>0,maxTouchPoints:Math.max(1,touch)});
 await s.resize(width,height);await s.send('Page.navigate',{url:url+'?orientation-qa='+encodeURIComponent(name)});
 let h;for(let i=0;i<80;i++){await wait(100);h=await host();if(h&&h.rotated===String(rotated))break;}
 check(h?.rotated===String(rotated),name+' rotation policy',h);
 check(h&&h.rect[0]>=-1&&h.rect[1]>=-1&&h.rect[0]+h.rect[2]<=width+1&&h.rect[1]+h.rect[3]<=height+1,name+' frame stays inside visible window',h);
 if(rotated)check(h.width===height&&h.height===width,name+' mobile frame fills portrait handset',h);
}
try{
 await s.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:'about:blank',port:9681,width:600,height:900});
 await setup('Windows narrow',desktop,'Win32',0,600,900,0);
 await setup('Windows touch narrow',desktop,'Win32',5,600,900,0);
 await setup('Android portrait','Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/128.0.0.0 Mobile Safari/537.36','Linux armv8l',5,390,844,1);
 // Rotate the same live phone frame without reloading it.
 const id=await s.evaluate('window.__orientationIdentity="retained";true');
 await s.resize(844,390);await wait(350);let h=await host();check(h.rotated==='0'&&h.width===844&&h.height===390,'Android landscape stays upright',h);check(await s.evaluate('window.__orientationIdentity==="retained"'),'phone orientation keeps live frame');
 await setup('iPhone portrait','Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1','iPhone',5,390,844,1);
 await setup('iPad desktop UA','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15','MacIntel',5,768,1024,1);
 await setup('Mac narrow','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15','MacIntel',0,600,900,0);
 await setup('Windows landscape',desktop,'Win32',0,1280,720,0);
 await wait(18000);await s.screenshot('desktop_landscape');
 await s.resize(600,900);await wait(700);h=await host();check(h.rotated==='0'&&h.deviceClass==='desktop'&&h.width===600&&Math.abs(h.rect[3]-600*9/16)<.1&&Math.abs(h.height-h.rect[3])<=.5,'live PC resize stays upright in a complete 16:9 frame',h);
 // Only landscape screenshots are presented; narrow-window geometry is in JSON.
 await s.resize(1280,720);await wait(700);
}catch(e){checks.push({pass:false,name:String(e)});process.exitCode=1;console.error(e);}
finally{await s.close();await writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,scope:'Actual Chrome host layout with explicit desktop/phone/tablet UA and touch profiles; OS-device testing not claimed.'},null,2));}
