"""Project-authored deterministic environment geometry; no models or external assets."""
import bpy
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

out = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = .84
    return m

leaf = material('Sage canopy', (.15, .30, .19))
stone = material('Weathered slate', (.26, .32, .30))
bark = material('Warm bark', (.23, .17, .105))

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
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons: poly.material_index = 0
    return obj

parts=[]
# Rounded overlapping lobes, not one faceted ball. Same footprint as the old
# canopy family so the established blocked/open placement remains authoritative.
for i,(x,y,z,sx,sy,sz) in enumerate([
    (0,0,.035,.19,.17,.18),(-.11,.005,-.015,.135,.14,.12),
    (.095,.045,-.025,.15,.115,.14),(.02,-.105,-.02,.13,.14,.13),
    (-.06,.09,.015,.14,.115,.145),(.045,.015,.125,.13,.125,.095)]):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=5, radius=1, location=(x,y,z))
    obj=bpy.context.object;obj.scale=(sx,sy,sz)
    for p in obj.data.polygons:p.use_smooth=True
    parts.append(obj)
canopy=join(parts,'POLISH_CANOPY',leaf)

parts=[]
for i in range(3):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=((i-1)*.075, .025*math.sin(i*2),-.025))
    obj=bpy.context.object;obj.scale=(.13,.105,.105+(i%2)*.025);obj.rotation_euler.z=i*.64
    parts.append(obj)
rocks=join(parts,'POLISH_BOULDER',stone)

parts=[]
for i in range(3):
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=.055-i*.008, radius2=.04-i*.008, depth=.13, location=(i*.009,0,-.11+i*.115))
    obj=bpy.context.object;obj.rotation_euler.y=-.07+i*.07;parts.append(obj)
trunk=join(parts,'POLISH_TRUNK',bark)

kit=out/'environment_polish.glb'
bpy.ops.export_scene.gltf(filepath=str(kit),export_format='GLB',use_selection=False)
manifest={'status':'CANDIDATE_NOT_PROMOTED','provenance':'Deterministic project-authored Blender geometry; no external assets, local weights, or generation APIs.',
          'blender':bpy.app.version_string,'sha256':hashlib.sha256(kit.read_bytes()).hexdigest(),
          'meshes':[{'name':o.name,'vertices':len(o.data.vertices),'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)} for o in [canopy,rocks,trunk]]}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')

# Exploded studio preview is evidence only; GLB masters above remain at origin.
canopy.location=(-.45,0,.25);trunk.location=(-.45,0,0);rocks.location=(.30,0,-.12)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.23))
bpy.context.object.data.materials.append(material('Studio moss',(.085,.12,.10)))
bpy.ops.object.light_add(type='AREA',location=(-2,-3,5));bpy.context.object.data.energy=420;bpy.context.object.data.size=4
bpy.ops.object.camera_add(location=(1.9,-3,1.7))
cam=bpy.context.object;cam.rotation_euler=(Vector((-.12,0,.10))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=1.65
scene=bpy.context.scene;scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=900;scene.render.resolution_y=600;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Preview world')
scene.world.color=(.20,.20,.20);scene.render.filepath=str(out/'studio_preview.png')
bpy.ops.wm.save_as_mainfile(filepath=str(out/'preview_scene.blend'))
bpy.ops.render.render(write_still=True)
print('ENVIRONMENT_POLISH_CANDIDATE',json.dumps(manifest))
