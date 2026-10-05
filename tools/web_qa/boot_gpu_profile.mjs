import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [out, url, port='9350'] = process.argv.slice(2);
const session = new GameplaySession(out);
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),width:1920,height:1080,profileGPU:true,
    initScript:`window.__bootLongTasks=[];new PerformanceObserver(l=>window.__bootLongTasks.push(...l.getEntries().map(e=>({start:e.startTime,duration:e.duration})))).observe({type:'longtask',buffered:true});`});
  const started=Date.now();
  while(Date.now()-started<120000) {
    await new Promise(resolve=>setTimeout(resolve,2000));
    if(await session.evaluate(`!!window.__lanternRenderReady`)) break;
  }
  await new Promise(resolve=>setTimeout(resolve,3000));
  const data=await session.evaluate(`({gpu:window.__localGPUProfile,ready:!!window.__lanternRenderReady,elapsed:performance.now(),longTasks:window.__bootLongTasks,resources:performance.getEntriesByType('resource').map(e=>({name:e.name,start:e.startTime,end:e.responseEnd,duration:e.duration,size:e.transferSize,decoded:e.decodedBodySize}))})`);
  await writeFile(path.join(out,'gpu_profile.json'),JSON.stringify(data,null,2)+'\n');
  console.log(JSON.stringify({ready:data.ready,contexts:data.gpu.contexts,costliest:data.gpu.calls.sort((a,b)=>b.duration-a.duration).slice(0,15),logs:session.logs(10)},null,2));
  await session.screenshot('boot');
} finally {await session.close();}
