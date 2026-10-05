import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
const report=JSON.parse(fs.readFileSync('reports/sites_update_20260920/staged_assets.json','utf8'));
const worker=fs.readFileSync('dist/server/index.js','utf8');
const routes=JSON.parse(worker.match(/^const FILES = (.+);\r?$/m)[1]);
let checked=0;
for(const [name,expected] of Object.entries(report.files)){
  const stagedExpected=report.staged_rewrites?.[name]??expected;
  const entry=routes['/'+name], digest=createHash('sha256');let bytes=0;
  const manifestFile=path.resolve('dist/client',name+'.chunks.json');
  let parts=entry?entry.parts:[name];
  if(fs.existsSync(manifestFile)){
    const manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8'));
    if(manifest.schema!=='godot-pck-chunks-v1'||manifest.original.file!==name
      ||manifest.original.size!==expected.bytes||manifest.original.sha256!==expected.sha256)
      throw Error('Invalid PCK chunk manifest: '+name);
    parts=manifest.chunks.map(chunk=>chunk.file);
    const html=fs.readFileSync('dist/client/index.html','utf8');
    const loader=fs.readFileSync('dist/client/index.js','utf8');
    if(!html.includes('GODOT_PCK_CHUNK_MANIFEST_V1')||!loader.includes('GODOT_PCK_CHUNK_STREAM_V1'))
      throw Error('Chunked Godot loader missing');
  }
  for(const part of parts){
    const file=path.resolve('dist/client',part.replace(/^\//,''));
    if(!file.startsWith(path.resolve('dist/client')+path.sep))throw Error('Invalid asset path');
    const content=fs.readFileSync(file);digest.update(content);bytes+=content.length;
  }
  if(bytes!==stagedExpected.bytes||digest.digest('hex')!==stagedExpected.sha256)throw Error('Release asset mismatch: '+name);
  checked++;
}
if(!fs.existsSync('dist/.openai/hosting.json'))throw Error('Missing hosting manifest');
console.log(`Verified ${checked} current LUMENBOUND release assets. Godot export is already built.`);
