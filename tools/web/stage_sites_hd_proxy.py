"""Serve verified HD pages from the same owner's Pages release through Sites.

Sites' 256 MiB archive cannot also hold the reviewed HD atlases. Only the
declared public PNG paths are proxied, without credentials or user headers.
The original Godot page hash checks remain authoritative in the client.
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
site, release = (Path(x).resolve() for x in sys.argv[1:])
assert site.is_relative_to(ROOT / 'work') and release.is_relative_to(ROOT / 'builds')
origin = 'https://comicman081-collab.github.io/LUMENBOUND-TACTICS-OF-THE-LAST-LINE/'
manifest = json.loads((release / 'density_sidecars.json').read_text(encoding='utf-8'))
pages = {('/' + n): r for n, r in manifest['pages'].items()
         if not n.startswith('_hd/full_density/r2/BOSS')}
for name, record in pages.items():
    assert name.startswith('/_hd/') and name.endswith('.png') and '..' not in name
    file = release / name.removeprefix('/')
    assert file.stat().st_size == record['bytes']
    assert hashlib.sha256(file.read_bytes()).hexdigest() == record['sha256']
worker = site / 'dist/server/index.js'
text = worker.read_text(encoding='utf-8')
needle = '  if(!entry)return env.ASSETS.fetch(request);'
assert text.count(needle) == 1
code = '''  const hd=HD_PAGES[decodeURIComponent(url.pathname)];
  if(hd){
   if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405});
   const upstream=new URL(url.pathname.slice(1),HD_ORIGIN);
   upstream.searchParams.set('v',hd.sha256);
   const response=await fetch(upstream,{method:request.method,redirect:'manual',headers:{Accept:'image/png'}});
   const length=response.headers.get('Content-Length');
   if(!response.ok||(length&&Number(length)!==hd.bytes))return new Response('Reviewed HD page unavailable',{status:502});
   return new Response(request.method==='HEAD'?null:response.body,{status:200,headers:{
    'Content-Type':'image/png','Content-Length':String(hd.bytes),'Cache-Control':'public, max-age=3600','ETag':'"'+hd.sha256+'"'
   }});
  }
'''
text = text.replace(needle, code + needle)
text = "const HD_ORIGIN = " + json.dumps(origin) + ";\nconst HD_PAGES = " + json.dumps(pages,separators=(',',':')) + ";\n" + text
worker.write_text(text,encoding='utf-8',newline='\n')
evidence = {'origin':origin,'pages':len(pages),'bytes':sum(r['bytes'] for r in pages.values()),
            'worker_sha256':hashlib.sha256(worker.read_bytes()).hexdigest(),
            'policy':'Current reviewed HD only; no old r2 boss pages, no credentials, no arbitrary proxy URLs',
            'pages_manifest':pages}
out=site/'reports/reviewed_hd_proxy.json'
out.write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in evidence.items() if k!='pages_manifest'}))
