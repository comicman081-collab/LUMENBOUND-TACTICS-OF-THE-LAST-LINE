import http from 'node:http';
import {readFile, stat} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {Readable} from 'node:stream';
const site=path.resolve(process.argv[2]), port=Number(process.argv[3]||8788);
const worker=(await import(pathToFileURL(path.join(site,'dist/server/index.js')))).default;
const root=path.join(site,'dist/client');
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png','.wasm':'application/wasm','.mp3':'audio/mpeg','.wav':'audio/wav','.mp4':'video/mp4'};
const env={ASSETS:{async fetch(request){
  const url=new URL(request.url),relative=decodeURIComponent(url.pathname).replace(/^\/+/, '')||'index.html';
  const file=path.resolve(root,relative);
  if(!file.startsWith(root+path.sep))return new Response(null,{status:403});
  try{await stat(file);const bytes=await readFile(file);return new Response(bytes,{headers:{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Content-Length':String(bytes.length)}});}
  catch{return new Response('Not found',{status:404});}
}}};
http.createServer(async(req,res)=>{try{
  const request=new Request(`http://127.0.0.1:${port}${req.url}`,{method:req.method,headers:req.headers});
  const response=await worker.fetch(request,env);
  res.writeHead(response.status,Object.fromEntries(response.headers));
  if(response.body)Readable.fromWeb(response.body).pipe(res);else res.end();
}catch(e){res.writeHead(500);res.end(String(e));}}).listen(port,'127.0.0.1',()=>console.log(`READY http://127.0.0.1:${port}`));
