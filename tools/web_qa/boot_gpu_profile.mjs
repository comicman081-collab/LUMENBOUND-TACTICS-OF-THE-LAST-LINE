import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
const [out, url, port='9350'] = process.argv.slice(2);
const session = new GameplaySession(out);
try {
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url,port:Number(port),profileGPU:true});
  const started=Date.now();
  while(Date.now()-started<120000) {
    await new Promise(resolve=>setTimeout(resolve,2000));
    if(await session.evaluate(`!!window.__localGameplayQA?.ready`)) break;
  }
  await new Promise(resolve=>setTimeout(resolve,3000));
  const data=await session.evaluate(`({gpu:window.__localGPUProfile,ready:!!window.__localGameplayQA?.ready,resources:performance.getEntriesByType('resource').map(e=>({name:e.name,duration:e.duration,size:e.transferSize}))})`);
  await writeFile(path.join(out,'gpu_profile.json'),JSON.stringify(data,null,2)+'\n');
  console.log(JSON.stringify({ready:data.ready,contexts:data.gpu.contexts,costliest:data.gpu.calls.sort((a,b)=>b.duration-a.duration).slice(0,15),logs:session.logs(10)},null,2));
  await session.screenshot('boot');
} finally {await session.close();}
