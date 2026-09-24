"""R18 project-authored folded foliage; no downloaded art or model weights."""
import bpy
import hashlib
import json
import math
import random
import sys
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(sys.argv[sys.argv.index('--')+1]).resolve()
if not OUT.is_relative_to(ROOT) or OUT.exists(): raise RuntimeError('FRESH_PROJECT_OUTPUT_REQUIRED')
OUT.mkdir(parents=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng=random.Random(180907)
rounded='--round-leaves' in sys.argv

def mat(name,color):
    value=bpy.data.materials.new(name)
    value.diffuse_color=(*color,1)
    value.use_nodes=True
    value.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1)
    value.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.93
    return value

def joined(parts,name,material):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts: obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    obj=parts[0]; obj.name=name
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.materials.clear();obj.data.materials.append(material)
    for face in obj.data.polygons: face.material_index=0
    return obj

leaf=mat('Botanical sage',(.19,.34,.21))
bark=mat('Weathered branching bark',(.23,.18,.12))
stone=mat('Moss slate',(.29,.33,.29))
lobes=[(0,0,.045,.145),(-.12,.03,-.014,.092),(.11,.045,-.012,.10),(.025,-.115,-.028,.095),(-.065,.11,.018,.085),(.028,.01,.16,.075)]
if rounded:
    lobes=[(0,0,.035,.18),(-.11,.005,-.015,.13),(.095,.045,-.025,.135),(.02,-.105,-.02,.13),(-.06,.09,.015,.125),(.045,.015,.125,.11)]
parts=[]
for x,y,z,radius in lobes:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=radius,location=(x,y,z))
    obj=bpy.context.object;obj.scale=(1,.91,.80)
    for face in obj.data.polygons: face.use_smooth=True
    parts.append(obj)

# Folded six-point lance leaves form the outer silhouette. They are geometry,
# not alpha cards, so no new bitmap/matte or transparent sorting pass is needed.
vertices=[];faces=[]
for center in lobes:
    x,y,z,radius=center
    for index in range(22):
        angle=(index/22)*math.tau+rng.uniform(-.12,.12)
        elevation=rng.uniform(-.5,.95)
        direction=Vector((math.cos(angle),math.sin(angle),elevation)).normalized()
        origin=Vector((x,y,z))+direction*radius*.74
        along=direction*rng.uniform(.019,.029) if rounded else direction*rng.uniform(.043,.070)
        across=direction.cross(Vector((0,0,1))).normalized()*rng.uniform(.012,.020)
        ridge=origin+Vector((0,0,.009))
        start=len(vertices)
        vertices.extend([origin-along*.45,origin+across,ridge,origin-across,origin+along])
        faces.extend([(start,start+1,start+2),(start,start+2,start+3),(start+2,start+1,start+4),(start+3,start+2,start+4)])
mesh=bpy.data.meshes.new('Folded_leaf_mesh');mesh.from_pydata(vertices,[],faces);mesh.update()
obj=bpy.data.objects.new('Folded_leaves',mesh);bpy.context.collection.objects.link(obj);parts.append(obj)
canopy=joined(parts,'POLISH_CANOPY',leaf)

def branch(start,end,r1,r2):
    a,b=Vector(start),Vector(end);vector=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=6,radius1=r1,radius2=r2,depth=vector.length,location=(a+b)*.5)
    obj=bpy.context.object;obj.rotation_euler=vector.to_track_quat('Z','Y').to_euler();return obj

parts=[branch((0,0,-.175),(.012,0,.10),.052,.029)]
for angle in (0.3,2.5,4.6):
    parts.append(branch((.01,0,-.015),(.09*math.cos(angle),.09*math.sin(angle),.165),.021,.008))
trunk=joined(parts,'POLISH_TRUNK',bark)
parts=[]
for i in range(3):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=((i-1)*.075,.025*math.sin(i*2),-.025))
    obj=bpy.context.object;obj.scale=(.13,.105,.105+(i%2)*.025);obj.rotation_euler.z=i*.64;parts.append(obj)
rock=joined(parts,'POLISH_BOULDER',stone)
kit=OUT/'environment_polish.glb'
bpy.ops.export_scene.gltf(filepath=str(kit),export_format='GLB',use_selection=False)
rows=[{'name':o.name,'vertices':len(o.data.vertices),'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)} for o in (canopy,trunk,rock)]
if rows[0]['triangles']>900: raise RuntimeError('CANOPY_TRIANGLE_BUDGET_EXCEEDED')
manifest={'status':'CANDIDATE_NOT_PROMOTED','variant':'r19-rounded' if rounded else 'r18-lance','blender':bpy.app.version_string,'source':'tools/blender/build_web_botanical_canopy.py','source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'provenance':'Original deterministic project geometry; no models or external assets','meshes':rows,'glb_sha256':hashlib.sha256(kit.read_bytes()).hexdigest(),'size_bytes':kit.stat().st_size}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'geometry_master.blend'))
print('BOTANICAL_CANOPY_CANDIDATE',json.dumps(manifest))
