"""Check exported Blender water stays in the canonical reserved corridor."""
import hashlib
import json
import struct
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
rows=[]
for source in sorted((ROOT/'data_source/art_source/natural_environment_r1/candidate_03').glob('CH*/river.glb')):
    data=source.read_bytes()
    assert data[:4]==b'glTF'
    length,kind=struct.unpack_from('<II',data,12)
    document=json.loads(data[20:20+length])
    binary_start=20+length+8
    binary=data[binary_start:]
    original=json.loads((ROOT/'data_source/art_source/natural_environment_r1/inputs'/f'{source.parent.name}.json').read_text(encoding='utf-8'))
    path=np.asarray(original['river_points'],dtype=np.float64)[:,[0,2]]
    a,b=path[:-1],path[1:];delta=b-a
    denominator=np.maximum(np.sum(delta*delta,axis=1),1e-12)
    maximum=0;count=0
    for mesh in document['meshes']:
        if not mesh['name'].startswith('WATER'):continue
        for primitive in mesh['primitives']:
            accessor=document['accessors'][primitive['attributes']['POSITION']]
            assert accessor['componentType']==5126 and accessor['type']=='VEC3'
            view=document['bufferViews'][accessor['bufferView']]
            offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
            stride=view.get('byteStride',12)
            points=np.ndarray((accessor['count'],3),dtype='<f4',buffer=binary,offset=offset,strides=(stride,4))[:,[0,2]].astype(np.float64)
            assert np.isfinite(points).all()
            for start in range(0,len(points),512):
                p=points[start:start+512]
                weights=np.clip(np.sum((p[:,None,:]-a)*delta,axis=2)/denominator,0,1)
                closest=a+delta*weights[:,:,None]
                distance=np.sqrt(np.sum((p[:,None,:]-closest)**2,axis=2)).min(axis=1)
                maximum=max(maximum,float(distance.max()))
            count+=len(points)
    manifest=json.loads(source.with_name('manifest.json').read_text(encoding='utf-8'))
    digest=hashlib.sha256(data).hexdigest()
    assert digest==manifest['glb_sha256'] and manifest['blender'].startswith('5.')
    assert count>0 and maximum<=.906, (source,maximum)
    rows.append({'map':source.parent.name,'water_vertices':count,'max_distance_to_canonical_centerline':maximum,'reserved_half_width':1.82,'sha256':digest})
assert len(rows)==20,len(rows)
out=ROOT/'reports/gameplay_qa/20260908_environment46_corridors.json'
out.write_text(json.dumps({'pass':True,'maps':rows,'contract':'Actual GLB water vertices stay within 0.906 of the canonical centerline; existing rasterizer reserves 1.82. Gameplay rasterization remains unchanged.'},indent=2),encoding='utf-8')
print('NATURAL_ENV_CORRIDORS maps=20 max_distance=',max(r['max_distance_to_canonical_centerline'] for r in rows))
