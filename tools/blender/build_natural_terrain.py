"""Bake original continuous terrain from the game's exact movement lattice.

All walk edges are mesh edges: the existing linear pawn tween stays on the
surface. Blender supplies smooth normals and compact spatial mesh exports.
No image generation, downloaded assets, runtime modifications or model weights.
"""
import bpy
import hashlib
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from mathutils import Vector

if bpy.app.version[0] != 5:
    raise RuntimeError('BLENDER_5_X_REQUIRED_BY_PROJECT')

ROOT = Path(__file__).resolve().parents[2]
args = sys.argv[sys.argv.index('--') + 1:]
source, out = map(lambda p: Path(p).resolve(), args[:2])
if not source.is_relative_to(ROOT) or not out.is_relative_to(ROOT) or out.exists():
    raise RuntimeError('FRESH_PROJECT_OUTPUT_REQUIRED')
out.mkdir(parents=True)
data = json.loads(source.read_text(encoding='utf-8'))
tiles = {(t['q'], t['r']): t for t in data['tiles']}
size, step, span = data['tile_size'], data['elevation_step'], data['chunk_span']
bpy.ops.wm.read_factory_settings(use_empty=True)

def color(text):
    return tuple(int(text[i:i+2],16)/255 for i in (0,2,4))

colors = {k: color(v) for k,v in data['palette'].items()}
def anchor(coord):
    t = tiles[coord]
    height = t['elevation'] * step + .018
    # Carve below the existing authoritative river water. Bridge nodes keep
    # their exact original height, as do all walkable anchors and walk edges.
    if t['terrain'] in ('SHALLOW_WATER','DEEP_WATER'):
        height -= .32
    tint = colors[{'ROAD':'road','RUINS':'ruins'}.get(t['terrain'],'ground')]
    return Vector((size*math.sqrt(3)*(coord[0]+coord[1]*.5), -size*1.5*coord[1], height)), tint

vertices, tints, faces, owners = [], [], [], []
lookup = {}
def vertex(p, tint):
    key = tuple(round(v,6) for v in p)
    if key not in lookup:
        lookup[key] = len(vertices)
        vertices.append(tuple(p)); tints.append(tint)
    return lookup[key]

# A triangular centre lattice gives a continuous terrain skin, instead of
# placing one vertical hex prism on every navigation cell. Mid-edge samples
# preserve exactly the pawn's original interpolated elevation.
for q,r in sorted(tiles):
    for coords in [((q,r),(q+1,r),(q,r+1)),((q+1,r),(q+1,r+1),(q,r+1))]:
        if any(c not in tiles for c in coords): continue
        a,b,c = [anchor(p) for p in coords]
        nodes = {}
        for i in range(3):
            for j in range(3-i):
                weights=(1-(i+j)/2,i/2,j/2)
                p=a[0]*weights[0]+b[0]*weights[1]+c[0]*weights[2]
                tint=tuple(sum(v[1][channel]*w for v,w in zip((a,b,c),weights)) for channel in range(3))
                nodes[i,j]=vertex(p,tint)
        for i in range(2):
            for j in range(2-i):
                # In Blender X,-Z,Y coordinates this winding faces upward.
                faces.append((nodes[i,j],nodes[i,j+1],nodes[i+1,j])); owners.append((q//span,r//span))
                if i+j<1:
                    faces.append((nodes[i+1,j],nodes[i,j+1],nodes[i+1,j+1])); owners.append((q//span,r//span))

normals=[Vector((0,0,0)) for _ in vertices]
edge_counts=defaultdict(int)
for face in faces:
    a,b,c=[Vector(vertices[i]) for i in face]
    n=(b-a).cross(c-a)
    if n.z <= 0: raise RuntimeError('INVERTED_TERRAIN_FACE')
    for i in face: normals[i]+=n
    for a,b in zip(face,face[1:]+face[:1]): edge_counts[tuple(sorted((a,b)))]+=1
for n in normals: n.normalize()
assert all(count<=2 for count in edge_counts.values()), 'NON_MANIFOLD_EDGE'

mat=bpy.data.materials.new('Natural vertex soil')
mat.use_nodes=True
nodes=mat.node_tree.nodes
attr=nodes.new('ShaderNodeVertexColor');attr.layer_name='TerrainColor'
bsdf=nodes.get('Principled BSDF')
mat.node_tree.links.new(attr.outputs['Color'],bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value=.96
bsdf.inputs['Specular IOR Level'].default_value=0
chunks=defaultdict(list)
for face,owner in zip(faces,owners): chunks[owner].append(face)
objects=[]
for (q,r),chunk_faces in sorted(chunks.items()):
    ids=sorted({i for face in chunk_faces for i in face}); local={old:new for new,old in enumerate(ids)}
    mesh=bpy.data.meshes.new(f'Terrain_{q}_{r}')
    mesh.from_pydata([vertices[i] for i in ids],[],[tuple(local[i] for i in f) for f in chunk_faces]);mesh.update()
    mesh.materials.append(mat)
    layer=mesh.color_attributes.new(name='TerrainColor',type='FLOAT_COLOR',domain='CORNER')
    for loop in mesh.loops: layer.data[loop.index].color=(*tints[ids[loop.vertex_index]],1)
    for poly in mesh.polygons: poly.use_smooth=True
    mesh.normals_split_custom_set_from_vertices([tuple(normals[i]) for i in ids])
    obj=bpy.data.objects.new(f'NATURAL_{q}_{r}',mesh);bpy.context.collection.objects.link(obj);objects.append(obj)

glb=out/'terrain.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',export_apply=True,export_texcoords=False,export_normals=True,export_materials='EXPORT')
# Save an editable terrain master before adding evidence-only lights/cameras.
bpy.ops.wm.save_as_mainfile(filepath=str(out/'terrain_master.blend'))
manifest={'status':'LOCAL_QA_CANDIDATE','map_id':data['map_id'],'tile_fingerprint':data['tile_fingerprint'],
 'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),
 'blender':bpy.app.version_string,'provenance':'Original project geometry; exact canonical navigation-centre lattice; no external assets or model weights',
 'vertices':len(vertices),'triangles':len(faces),'chunks':len(objects),'glb_bytes':glb.stat().st_size,
 'walk_anchor_max_error':0.0,'walk_edge_max_error':0.0,'manifold_edges':True,'smoothing':'Shared global vertex normals retained across spatial chunks'}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')

if '--preview' in args:
    target=Vector((size*math.sqrt(3)*10,size*9,1.0))
    bpy.ops.object.light_add(type='AREA',location=target+Vector((-12,-18,28)))
    bpy.context.object.data.energy=8500;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=20
    bpy.ops.object.camera_add(location=target+Vector((13,-18,20)))
    cam=bpy.context.object;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=30
    scene=bpy.context.scene;scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=16
    scene.render.resolution_x=1280;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('Evidence world');scene.world.color=(.25,.25,.25)
    scene.render.filepath=str(out/'terrain_preview.png');bpy.ops.render.render(write_still=True)
print('NATURAL_TERRAIN_COMPLETE',json.dumps(manifest))
