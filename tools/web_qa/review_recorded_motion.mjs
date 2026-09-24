import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const [output,video]=process.argv.slice(2),s=new GameplaySession(output);
const html=path.join(path.resolve(output),'video_review.html');
await writeFile(html,`<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#101820}video{width:1280px;height:720px}</style><video muted preload="auto" src="${pathToFileURL(path.resolve(video)).href}"></video>`);
try{
 await s.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:pathToFileURL(html).href,port:9487,width:1280,height:720,allowFileAccess:true});
 const metadata=await s.evaluate(`new Promise(resolve=>{const v=document.querySelector('video');const done=()=>resolve({width:v.videoWidth,height:v.videoHeight,duration:v.duration});if(v.readyState>=2)done();else v.onloadeddata=done})`);
 for(const t of [0.5,1,1.5,2,2.5,3,6,9,12,14,16,18]){
  await s.evaluate(`new Promise(resolve=>{const v=document.querySelector('video');v.onseeked=()=>requestAnimationFrame(()=>resolve(v.currentTime));v.currentTime=${t}})`);
  await s.screenshot('video_'+String(t).replace('.','_'));
 }
 await writeFile(path.join(output,'metadata.json'),JSON.stringify(metadata,null,2));
}finally{await s.close();}
