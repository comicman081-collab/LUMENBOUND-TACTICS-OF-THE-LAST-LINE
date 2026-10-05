// Measure the actual first painted, interactive release screen from navigation.
// Fresh profile, fixed 1080p, real GPU; screenshots and clicks occur after timing.
import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output,url,port='9541',gate='require',target='10']=process.argv.slice(2);
const session=new GameplaySession(output),checks=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const initScript=`(()=>{
 const p=window.__startupAudit={readyAt:0,firstReadyAt:0,stableFrames:0,longTasks:[]};
 new PerformanceObserver(l=>p.longTasks.push(...l.getEntries().map(e=>({at:e.startTime,ms:e.duration})))).observe({type:'longtask',buffered:true});
 function frame(t){
  const ready=window.__lanternRenderReady===true&&!document.getElementById('lantern-render-loading')&&!document.getElementById('status')&&document.getElementById('canvas')?.width===1920;
  if(ready){if(!p.firstReadyAt)p.firstReadyAt=t;p.stableFrames++;}else{p.firstReadyAt=0;p.stableFrames=0;}
  if(p.stableFrames>=2){p.readyAt=t;p.totalMs=performance.timeOrigin+t-top.performance.timeOrigin;return;}
  requestAnimationFrame(frame);
 }requestAnimationFrame(frame);
})();`;
function check(pass,name,details,required=true){
 checks.push({pass:!!pass,name,details});console.log(JSON.stringify(checks.at(-1)));
 if(!pass&&required)throw Error(name);
}
try{
 await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1920,height:1080,initScript});
 const started=Date.now();let timing;
 while(Date.now()-started<60000){
  timing=await session.evaluate('window.__startupAudit');
  if(timing?.readyAt)break;
  await delay(100);
 }
 check(timing?.readyAt>0,'First screen painted and startup input gate removed');
 const data=await session.evaluate(`(()=>{
  const canvas=document.getElementById('canvas'),gl=canvas.getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');
  return {timing:window.__startupAudit,renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),canvas:[canvas.width,canvas.height],resources:performance.getEntriesByType('resource').map(e=>({name:e.name,start:e.startTime,end:e.responseEnd,ms:e.duration,bytes:e.transferSize})),ready:window.__lanternRenderReady,loadingGatePresent:!!document.getElementById('lantern-render-loading')};
 })()`);
 check(data.canvas[0]===1920&&data.canvas[1]===1080,'Actual canvas is 1920x1080');
 check(/NVIDIA|RTX/i.test(data.renderer),'Hardware GPU active',data.renderer);
 check(data.timing.totalMs<Number(target)*1000,'Navigation to interactive screen strictly under '+target+' seconds',{seconds:data.timing.totalMs/1000},gate==='require');
 check(!data.resources.some(r=>r.name.includes('/_hd/')),'No battle/map HD image downloads during startup');
 await session.screenshot('first_interactive_screen');
 const clicked=Date.now();await session.click(480,871.5);
 let video;
 while(Date.now()-clicked<5000){
  video=await session.evaluate(`(()=>{const v=window.__lumenIntro?.video;return v?{time:v.currentTime,width:v.videoWidth,height:v.videoHeight,paused:v.paused,error:window.__lumenIntro.error}:null})()`);
  if(video?.time>.2)break;
  await delay(100);
 }
 check(video?.time>.2&&!video.error&&video.width===1920&&video.height===1080,'Actual start click begins decoded 1080p intro',video);
 check(session.events.filter(e=>e.method==='Runtime.exceptionThrown'||e.method==='Network.loadingFailed'||e.method==='Network.responseReceived').length===0,'No browser exception or failed resource response');
 await writeFile(path.join(output,'startup_summary.json'),JSON.stringify({passed:checks.every(c=>c.pass),url,checks,...data},null,2)+'\n');
}catch(error){
 console.error(String(error));process.exitCode=1;
 await writeFile(path.join(output,'startup_summary.json'),JSON.stringify({passed:false,url,checks,error:String(error)},null,2)+'\n').catch(()=>{});
}finally{await session.close();}
