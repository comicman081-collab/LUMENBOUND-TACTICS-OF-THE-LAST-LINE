import {writeFile,readdir,readFile} from 'node:fs/promises';
const [port,out,stateFolder,tapText]=process.argv.slice(2);
const tabs=await(await fetch(`http://127.0.0.1:${port}/json`)).json();
const ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
let id=0;const pending=new Map();
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){pending.get(m.id)?.(m.result);pending.delete(m.id);}});
const send=(method,params={})=>new Promise(r=>{const i=++id;pending.set(i,r);ws.send(JSON.stringify({id:i,method,params}));});
if(tapText){
 const files=(await readdir(stateFolder)).filter(f=>/^state_\d+.json$/.test(f)).sort();
 const s=JSON.parse(await readFile(`${stateFolder}/${files.at(-1)}`,'utf8'));
 const b=s.buttons.find(b=>!b.disabled&&b.text.includes(tapText));if(!b)throw Error('No observed button '+tapText);
 const x=b.rect[0]+b.rect[2]/2,y=b.rect[1]+b.rect[3]/2;
 const q=await send('Runtime.evaluate',{expression:`(()=>{const f=document.getElementById('landscape-game');const r=f?.getBoundingClientRect();return {x:${x}+(r?.left||0),y:${y}+(r?.top||0)}})()`,returnByValue:true});
 for(const type of ['mousePressed','mouseReleased'])await send('Input.dispatchMouseEvent',{type,button:'left',clickCount:1,...q.result.value});
}
const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(out,Buffer.from(shot.data,'base64'));ws.close();
