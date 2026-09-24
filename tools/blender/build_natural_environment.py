"""Original Blender 5.x grove kit and corridor-constrained river meshes."""
import bpy
import hashlib
import json
import math
import random
import sys
from pathlib import Path
from mathutils import Vector

if bpy.app.version[0] != 5:
    raise RuntimeError('BLENDER_5_X_REQUIRED_BY_PROJECT')
ROOT = Path(__file__).resolve().parents[2]
args = sys.argv[sys.argv.index('--')+1:]
mode, output = args[0], Path(args[-1]).resolve()
if not output.is_relative_to(ROOT) or output.exists():
    raise RuntimeError('FRESH_PROJECT_OUTPUT_REQUIRED')
output.mkdir(parents=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng = random.Random(520908)

def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = .94
    return m

def join(parts, name, mat):
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = parts[0]
    obj.name = name
    bpy.context.scene.cursor.location = (0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.clear(); obj.data.materials.append(mat)
    for p in obj.data.polygons: p.material_index = 0
    return obj

def branch(a,b,r1,r2):
    a,b = Vector(a),Vector(b)
    delta = b-a
    bpy.ops.mesh.primitive_cone_add(vertices=7,radius1=r1,radius2=r2,depth=delta.length,location=(a+b)*.5)
    obj=bpy.context.object;obj.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    return obj

objects=[]
extra={}
if mode == 'kit':
    leaf=material('Muted living foliage',(.25,.40,.28))
    bark=material('Weathered branching bark',(.25,.20,.15))
    stone=material('River-worn rock',(.40,.44,.41))
    for variant in range(2):
        parts=[]
        for i in range(6):
            angle=i*2.399+variant*.7
            radius=.125 if i else 0
            loc=(math.cos(angle)*radius,math.sin(angle)*radius,(i%3)*.055-.045)
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=.12 if i else .135,location=loc)
            obj=bpy.context.object
            obj.scale=(1.0+variant*.14,.90-variant*.12,.82+variant*.16)
            for v in obj.data.vertices:
                v.co *= 1.0 + .085*math.sin(v.co.x*42+v.co.z*31+i)
            parts.append(obj)
        obj=join(parts,'POLISH_CANOPY' if variant==0 else 'POLISH_CANOPY_ALT',leaf)
        # Merge intersecting lobes into a coherent crown, retaining an uneven
        # outer silhouette without hundreds of detached triangular leaf spikes.
        remesh=obj.modifiers.new('Joined organic crown','REMESH')
        remesh.mode='VOXEL';remesh.voxel_size=.018;remesh.use_smooth_shade=True
        bpy.ops.object.modifier_apply(modifier=remesh.name)
        smooth=obj.modifiers.new('Crown surface relaxation','SMOOTH');smooth.factor=.38;smooth.iterations=1
        bpy.ops.object.modifier_apply(modifier=smooth.name)
        dec=obj.modifiers.new('Shared mobile crown budget','DECIMATE')
        triangles=sum(len(p.vertices)-2 for p in obj.data.polygons)
        dec.ratio=min(1.0,640/max(triangles,1))
        bpy.ops.object.modifier_apply(modifier=dec.name)
        for p in obj.data.polygons:p.use_smooth=True
        objects.append(obj)
    parts=[branch((0,0,-.175),(.009,-.005,.12),.040,.022)]
    for i in range(4):
        angle=i*2.399
        parts.append(branch((.005,0,-.005),(.105*math.cos(angle),.105*math.sin(angle),.19+(i%2)*.04),.018,.006))
    objects.append(join(parts,'POLISH_TRUNK',bark))
    for variant in range(2):
        parts=[]
        for i in range(3):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=((i-1)*.072,math.sin(i+variant)*.036,-.025))
            obj=bpy.context.object;obj.scale=(.13,.095,.105+(i%2)*.025)
            for v in obj.data.vertices:
                v.co*=1+.13*math.sin(v.co.x*4+v.co.y*7+variant+i)
                if v.co.z<-.65:v.co.z=-.65
            for p in obj.data.polygons:p.use_smooth=True
            parts.append(obj)
        objects.append(join(parts,'POLISH_BOULDER' if variant==0 else 'POLISH_BOULDER_ALT',stone))
    filename='environment.glb'
elif mode == 'river':
    source=Path(args[1]).resolve();terrain=Path(args[2]).resolve()
    if not source.is_relative_to(ROOT) or not terrain.is_relative_to(ROOT):raise RuntimeError('PROJECT_INPUT_REQUIRED')
    data=json.loads(source.read_text(encoding='utf-8'))
    land=json.loads(terrain.read_text(encoding='utf-8'))
    tiles={(t['q'],t['r']):t for t in land['tiles']}
    original=[Vector(p) for p in data['river_points']]
    def ground(p):
        q=(math.sqrt(3)/3*p.x-p.z/3)/1.08;r=(2/3*p.z)/1.08
        iq,ir=math.floor(q),math.floor(r);fq,fr=q-iq,r-ir
        if fq+fr<=1:cs=[(iq,ir),(iq+1,ir),(iq,ir+1)];ws=[1-fq-fr,fq,fr]
        else:cs=[(iq+1,ir+1),(iq,ir+1),(iq+1,ir)];ws=[fq+fr-1,1-fq,1-fr]
        def h(c):
            t=tiles.get(c,{'elevation':0,'terrain':'FOREST'})
            return t['elevation']*.86+.018-(.32 if t['terrain'] in ('SHALLOW_WATER','DEEP_WATER') else 0)
        return sum(h(c)*w for c,w in zip(cs,ws))
    points=[];max_offset=0
    # Quadratic corner cuts remain within a 0.20 world-unit envelope of the
    # authoritative river. The existing 1.08 bank clearance remains reserved.
    for i,p in enumerate(original):
        if i==0 or i==len(original)-1:points.append(p);continue
        a=p.lerp(original[i-1],.14);b=p.lerp(original[i+1],.14)
        for j in range(4):
            t=j/3
            v=a*((1-t)**2)+p*(2*(1-t)*t)+b*t*t
            closest=[]
            for start,end in [(original[i-1],p),(p,original[i+1])]:
                d=end-start;d.y=0;delta=v-start;delta.y=0
                w=max(0,min(1,delta.dot(d)/max(d.length_squared,1e-9)))
                foot=start.lerp(end,w);diff=v-foot;diff.y=0
                closest.append((diff.length,foot))
            distance,foot=min(closest,key=lambda row:row[0])
            if distance>.20:
                ratio=.20/distance;v.x=foot.x+(v.x-foot.x)*ratio;v.z=foot.z+(v.z-foot.z)*ratio
            max_offset=max(max_offset,min(distance,.20))
            v.y=max(v.y,ground(v)+.035)
            if not points or (v-points[-1]).length>.001:points.append(v)
    parts={};length=0;positions=[]
    def convert(v):return (v.x,-v.z,v.y)
    def quad(kind,owner,ps,uv):
        key=(kind,owner);row=parts.setdefault(key,{'v':[],'f':[],'uv':[]})
        n=len(row['v']);row['v'].extend(map(convert,ps));row['uv'].extend(uv)
        row['f'].extend([(n,n+2,n+1),(n,n+3,n+2)])
    for i,p in enumerate(points):
        if i:length+=(p-points[i-1]).length
        d=points[min(i+4,len(points)-1)]-points[max(i-4,0)];d.y=0;d.normalize()
        side=Vector((-d.z,0,d.x))
        width=.66+.045*math.sin(length*.67)
        outer=width+.25+.09*math.sin(length*.42+1.7)
        cross=[]
        for sign in (-1,1):
            edge=p+side*width*sign
            mid=p+side*(width+.10)*sign;mid.y=max(ground(mid)+.016,p.y+.025)
            end=p+side*outer*sign;end.y=ground(end)+.018
            cross.append([edge,mid,end])
        positions.append((cross,length))
    for i in range(len(points)-1):
        a,la=positions[i];b,lb=positions[i+1]
        owner=(math.floor(points[i].x/24),math.floor(points[i].z/24))
        quad('WATER',owner,[a[0][0],b[0][0],b[1][0],a[1][0]],[(la,0),(lb,0),(lb,1),(la,1)])
        for sign in range(2):
            for strip in range(2):
                ps=[a[sign][strip],b[sign][strip],b[sign][strip+1],a[sign][strip+1]]
                uv=[(la,strip*.5),(lb,strip*.5),(lb,(strip+1)*.5),(la,(strip+1)*.5)]
                if sign==0:ps.reverse();uv.reverse()
                quad('BANK',owner,ps,uv)
    # One plank direction per connected crossing. Boards are clipped to the
    # union of its actual bridge cells instead of stacking oversized rectangles.
    bridges={c for c,t in tiles.items() if t['terrain']=='BRIDGE'}
    pending=set(bridges)
    def world(c):return Vector((1.08*math.sqrt(3)*(c[0]+c[1]*.5),0,1.62*c[1]))
    def clip(poly,axis,bound,keep_above):
        result=[]
        for a,b in zip(poly,poly[1:]+poly[:1]):
            da=a.dot(axis)-bound;db=b.dot(axis)-bound
            inside_a=da>=-1e-8 if keep_above else da<=1e-8
            inside_b=db>=-1e-8 if keep_above else db<=1e-8
            if inside_a:result.append(a)
            if inside_a!=inside_b:result.append(a.lerp(b,da/(da-db)))
        return result
    while pending:
        group=[];queue=[min(pending)]
        while queue:
            c=queue.pop()
            if c not in pending:continue
            pending.remove(c);group.append(c)
            queue.extend((c[0]+a,c[1]+b) for a,b in [(1,0),(0,1),(-1,1),(-1,0),(0,-1),(1,-1)])
        centers=[world(c) for c in group];mean=sum(centers,Vector())/len(centers)
        xx=sum((c.x-mean.x)**2 for c in centers);zz=sum((c.z-mean.z)**2 for c in centers)
        xz=sum((c.x-mean.x)*(c.z-mean.z) for c in centers)
        angle=.5*math.atan2(2*xz,xx-zz) if len(centers)>1 else math.pi/6
        axis=Vector((math.cos(angle),0,math.sin(angle)))
        for c,center in zip(group,centers):
            polygon=[center+Vector((math.cos(math.radians(30+j*60))*1.055,0,math.sin(math.radians(30+j*60))*1.055)) for j in range(6)]
            low=math.floor(min(p.dot(axis) for p in polygon)/.23)
            high=math.ceil(max(p.dot(axis) for p in polygon)/.23)
            owner=(math.floor(center.x/24),math.floor(center.z/24))
            row=parts.setdefault(('TIMBER',owner),{'v':[],'f':[],'uv':[]})
            for plank in range(low,high+1):
                poly=clip(clip(polygon,axis,plank*.23,True),axis,plank*.23+.205,False)
                if len(poly)<3:continue
                n=len(row['v'])
                for p in poly:
                    p.y=ground(p)+.075
                    row['v'].append(convert(p));row['uv'].append((p.dot(axis),float(plank%5)/5))
                for j in range(1,len(poly)-1):row['f'].append((n,n+j+1,n+j))
    mats={'WATER':material('River surface',(.055,.25,.26)),'BANK':material('Wet earthen riverbank',(.28,.33,.25)),'TIMBER':material('Weathered crossing boards',(.33,.27,.19))}
    for (kind,owner),row in sorted(parts.items()):
        mesh=bpy.data.meshes.new(f'{kind}_{owner[0]}_{owner[1]}')
        mesh.from_pydata(row['v'],[],row['f']);mesh.update();mesh.materials.append(mats[kind])
        uv=mesh.uv_layers.new(name='RiverFlow')
        for loop in mesh.loops:uv.data[loop.index].uv=row['uv'][loop.vertex_index]
        for p in mesh.polygons:p.use_smooth=True
        obj=bpy.data.objects.new(mesh.name,mesh);bpy.context.collection.objects.link(obj);objects.append(obj)
    extra={'map_id':data['map_id'],'tile_fingerprint':data['tile_fingerprint'],'canonical_points':len(original),'smoothed_points':len(points),'centerline_max_offset':max_offset,'water_half_width_max':.705,'bridge_tiles':len(bridges),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
    filename='river.glb'
else:raise RuntimeError('UNKNOWN_ENVIRONMENT_MODE')

glb=output/filename
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',export_apply=True)
bpy.ops.wm.save_as_mainfile(filepath=str(output/'environment_master.blend'))
rows=[{'name':o.name,'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)} for o in objects]
manifest={'status':'LOCAL_QA_CANDIDATE','blender':bpy.app.version_string,'provenance':'Original project geometry; no third-party assets or model weights','generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'bytes':glb.stat().st_size,'meshes':rows,**extra}
(output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('NATURAL_ENVIRONMENT_COMPLETE',mode,filename,glb.stat().st_size)
