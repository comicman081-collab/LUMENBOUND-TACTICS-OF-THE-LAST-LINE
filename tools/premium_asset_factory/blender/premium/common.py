from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Iterable

import bpy
from mathutils import Vector


FACTORY_VERSION = "premium-pilot-0.1.0"
BLENDER_VERSION = bpy.app.version_string


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.materials, bpy.data.curves, bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def material(name: str, color: tuple[float, float, float, float], *, metallic: float = 0.0,
             roughness: float = 0.65, emission: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.18 if metallic else 0.04
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> bpy.types.Object:
    if hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)
    return obj


def smooth(obj: bpy.types.Object) -> bpy.types.Object:
    if obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def bevel(obj: bpy.types.Object, width: float = 0.04, segments: int = 3) -> bpy.types.Object:
    modifier = obj.modifiers.new("authored_soft_bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    return obj


def uv(name: str, location, scale, mat, segments: int = 32, rings: int = 16) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return assign(smooth(obj), mat)


def stylized_head(name: str, location, scale, mat, segments: int = 32) -> bpy.types.Object:
    """Original tapered anime head mesh with cheek and jaw planes."""
    ring_spec = (
        (-1.00, 0.20, 0.24),
        (-0.82, 0.46, 0.42),
        (-0.48, 0.78, 0.68),
        (-0.06, 0.98, 0.88),
        (0.42, 1.00, 0.96),
        (0.78, 0.78, 0.82),
        (1.00, 0.20, 0.24),
    )
    vertices = []
    for z_factor, x_radius, y_radius in ring_spec:
        for index in range(segments):
            angle = (index / segments) * math.tau
            vertices.append((math.cos(angle) * x_radius * scale[0],
                             math.sin(angle) * y_radius * scale[1],
                             z_factor * scale[2]))
    faces = []
    ring_count = len(ring_spec)
    for ring in range(ring_count - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            a = ring * segments + index
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + index
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    bevel(obj, min(scale) * 0.035, 2)
    return assign(smooth(obj), mat)


def cube(name: str, location, scale, mat, rotation=(0.0, 0.0, 0.0), bevel_width=0.06) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel(obj, bevel_width)
    return assign(obj, mat)


def cone(name: str, location, radius1: float, radius2: float, depth: float, mat,
         rotation=(0.0, 0.0, 0.0), vertices=32) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2,
                                   depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    bevel(obj, 0.035)
    return assign(smooth(obj), mat)


def front_prism(name: str, location, width: float, height: float, depth: float, mat,
                vertices: int = 8, rotation_z: float = 0.0) -> bpy.types.Object:
    """Extruded front-facing authored plate; avoids a generic rounded rectangle."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=1.0, depth=2.0,
                                        location=location,
                                        rotation=(math.pi / 2.0, 0.0, rotation_z))
    obj = bpy.context.object
    obj.name = name
    # Local X/Y become the visible X/Z plane after the X rotation; local Z is depth.
    obj.scale = (width, height, depth)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel(obj, min(width, height) * 0.06, 3)
    return assign(obj, mat)


def torus(name: str, location, major_radius: float, minor_radius: float, mat,
          rotation=(math.pi / 2.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(major_radius=major_radius, minor_radius=minor_radius,
                                    major_segments=48, minor_segments=12,
                                    location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    return assign(smooth(obj), mat)


def capsule(name: str, start, end, radius: float, mat) -> list[bpy.types.Object]:
    a, b = Vector(start), Vector(end)
    direction = b - a
    length = direction.length
    midpoint = (a + b) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=max(0.01, length), location=midpoint)
    body = bpy.context.object
    body.name = name + "_body"
    body.rotation_mode = "QUATERNION"
    body.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    assign(smooth(body), mat)
    return [body, uv(name + "_a", a, (radius, radius, radius), mat, 20, 12),
            uv(name + "_b", b, (radius, radius, radius), mat, 20, 12)]


def curve_line(name: str, points: Iterable[tuple[float, float, float]], bevel_depth: float, mat) -> bpy.types.Object:
    curve_data = bpy.data.curves.new(name + "_curve", "CURVE")
    curve_data.dimensions = "3D"
    curve_data.bevel_depth = bevel_depth
    curve_data.bevel_resolution = 3
    spline = curve_data.splines.new("BEZIER")
    pts = list(points)
    spline.bezier_points.add(len(pts) - 1)
    for point, co in zip(spline.bezier_points, pts):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    return assign(obj, mat)


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_render(width: int, height: int, *, transparent: bool, camera_location=(8.4, -13.0, 5.7),
                 camera_target=(0.0, 0.0, 3.0), ortho_scale=8.2, samples=24,
                 world=(0.018, 0.035, 0.065)) -> bpy.types.Scene:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.film_transparent = transparent
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_percentage = 100
    scene.render.use_file_extension = True
    scene.render.film_transparent = transparent
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.image_settings.compression = 18
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.resolution_percentage = 100
    scene.render.fps = 12
    scene.world.color = world
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass

    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.name = "authored_camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    look_at(camera, camera_target)
    scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-4.5, -5.5, 9.0))
    key = bpy.context.object
    key.name = "warm_key"
    key.data.energy = 950
    key.data.shape = "DISK"
    key.data.size = 5.5
    key.data.color = (1.0, 0.72, 0.48)
    look_at(key, (0.0, 0.0, 3.0))

    bpy.ops.object.light_add(type="AREA", location=(5.5, -1.0, 6.0))
    rim = bpy.context.object
    rim.name = "cyan_rim"
    rim.data.energy = 780
    rim.data.size = 4.0
    rim.data.color = (0.28, 0.78, 1.0)
    look_at(rim, (0.0, 0.0, 3.1))

    bpy.ops.object.light_add(type="AREA", location=(0.0, 4.0, 4.0))
    fill = bpy.context.object
    fill.name = "back_fill"
    fill.data.energy = 520
    fill.data.size = 3.0
    fill.data.color = (0.55, 0.42, 1.0)
    look_at(fill, (0.0, 0.0, 3.2))
    return scene


def render(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_character(character: str, *, sd: bool = False, variant: int = 1,
                    expression: str = "neutral", pose: dict | None = None,
                    silhouette: bool = False) -> dict[str, bpy.types.Object]:
    pose = pose or {}
    k = 0.67 if sd else 1.0
    head_k = 1.25 if sd else 1.0
    palette = {
        "skin": material("skin", (0.78, 0.47, 0.35, 1.0), roughness=0.78),
        "eye_white": material("eye_white", (0.96, 0.97, 0.92, 1.0), roughness=0.3),
        "dark": material("graphite", (0.025, 0.055, 0.075, 1.0), metallic=0.15, roughness=0.5),
        "cloth": material("cloth", (0.06, 0.16, 0.22, 1.0), roughness=0.8),
        "cream": material("cream", (0.72, 0.68, 0.52, 1.0), roughness=0.78),
        "amber": material("amber", (1.0, 0.38, 0.055, 1.0), metallic=0.15, roughness=0.3, emission=2.3),
        "cyan": material("cyan", (0.08, 0.58, 0.82, 1.0), metallic=0.12, roughness=0.28, emission=1.8),
        "mint": material("mint", (0.18, 0.78, 0.55, 1.0), metallic=0.05, roughness=0.28, emission=1.3),
        "plum": material("plum", (0.24, 0.055, 0.20, 1.0), roughness=0.72),
        "silver": material("silver_hair", (0.54, 0.58, 0.58, 1.0), metallic=0.02, roughness=0.5),
        "hair_dark": material("charcoal_hair", (0.035, 0.045, 0.055, 1.0), roughness=0.45),
        "black": material("silhouette_black", (0.002, 0.002, 0.003, 1.0), roughness=1.0),
    }
    if silhouette:
        for key in list(palette):
            palette[key] = palette["black"]

    is_maeru = character == "CHR001"
    cloth = palette["dark"] if is_maeru else palette["cloth"]
    accent = palette["amber"] if is_maeru else palette["mint"]
    inner = palette["cream"] if is_maeru else palette["plum"]
    hair = palette["hair_dark"] if is_maeru else palette["silver"]
    iris = palette["amber"] if is_maeru else palette["mint"]

    height_scale = 0.70 if sd else 1.0
    z = lambda value: value * height_scale
    objects: dict[str, bpy.types.Object] = {}

    # Boots, legs, layered coat and torso establish an adult profession-first silhouette.
    leg_spread = 0.44 * k + float(pose.get("leg_spread", 0.0))
    for side, sx in (("L", -leg_spread), ("R", leg_spread)):
        stride = float(pose.get("stride", 0.0)) * (-1 if side == "L" else 1)
        knee_x = sx + stride * 0.10
        knee_y = stride * 0.16 - abs(stride) * 0.10
        capsule(f"{side}_shin", (sx, stride * 0.34, z(0.40)), (knee_x, knee_y, z(1.48)), 0.18 * k, cloth)
        capsule(f"{side}_thigh", (knee_x, knee_y, z(1.48)), (sx * 0.70, 0.0, z(2.55)), 0.22 * k, inner)
        boot = cube(f"{side}_boot", (sx, -0.16 + stride * 0.32, z(0.18)), (0.31 * k, 0.48 * k, z(0.19)), palette["dark"], bevel_width=0.10 * k)
        objects[f"boot_{side}"] = boot

    cone("hip_armor", (0.0, 0.0, z(2.62)), 0.76 * k, 0.54 * k, z(0.72), cloth)
    cone("coat_skirt", (0.0, 0.08, z(2.88)), 0.84 * k, 0.53 * k, z(1.05), cloth)
    cone("torso_outer", (0.0, 0.02, z(3.78)), 0.49 * k, 0.82 * k, z(1.46), cloth)
    cone("torso_inner", (0.0, -0.25, z(3.75)), 0.29 * k, 0.43 * k, z(1.22), inner)
    capsule("shoulder_mantle", (-0.72 * k, 0.04, z(4.33)), (0.72 * k, 0.04, z(4.33)), 0.17 * k, cloth)
    cube("chest_module", (0.0, -0.56 * k, z(3.72)), (0.34 * k, 0.10 * k, z(0.24)), accent, bevel_width=0.08 * k)

    tail_width = (0.58 + 0.16 * variant) * k
    for side in (-1, 1):
        cone("coat_tail", (side * tail_width * 0.50, 0.18, z(2.30)),
             tail_width * 0.48, tail_width * 0.29, z(1.28), cloth,
             rotation=(0.0, side * (0.09 + 0.04 * variant), side * 0.08), vertices=4)

    shoulder_z = z(4.23)
    arm_raise = float(pose.get("arm_raise", 0.0))
    for side, sx in (("L", -1), ("R", 1)):
        side_key = side.lower()
        side_raise = float(pose.get("arm_raise_" + side_key, arm_raise))
        side_out = float(pose.get("hand_out_" + side_key, 0.0))
        shoulder = (sx * 0.70 * k, 0.0, shoulder_z)
        elbow = (sx * (0.98 + 0.10 * side_raise + side_out * 0.18) * k,
                 -0.12 - side_out * 0.10, z(3.50 + side_raise * 0.40))
        hand = (sx * (0.76 - 0.14 * side_raise + side_out) * k,
                -0.47 - side_out * 0.28, z(2.83 + side_raise * 1.08))
        capsule(f"{side}_upper_arm", shoulder, elbow, 0.22 * k, cloth)
        capsule(f"{side}_forearm", elbow, hand, 0.19 * k, inner)
        uv(f"{side}_hand", hand, (0.24 * k, 0.15 * k, z(0.28)), palette["skin"], 24, 12)
        # Thumb opposition prevents the hero-frame hand from reading as a mitten.
        capsule(f"{side}_thumb", (hand[0], hand[1] - 0.05, hand[2]),
                (hand[0] + sx * 0.18 * k, hand[1] - 0.10, hand[2] - z(0.10)), 0.055 * k, palette["skin"])

    neck_z = z(4.70)
    capsule("neck", (0.0, 0.0, neck_z - z(0.18)), (0.0, 0.0, neck_z + z(0.18)), 0.20 * k, palette["skin"])
    head_center = Vector((0.0, -0.06, z(5.43 if not sd else 5.05)))
    if sd:
        head_scale = (0.61 * k * head_k, 0.54 * k * head_k, z(0.76) * head_k)
        objects["head"] = uv("face", head_center, head_scale, palette["skin"], 40, 24)
    else:
        head_scale = (0.52, 0.47, 0.55)
        objects["head"] = stylized_head("face", head_center, head_scale, palette["skin"], 40)

    eye_z = head_center.z + z(0.10)
    eye_x = 0.23 * k * head_k
    for side, sx in (("L", -1), ("R", 1)):
        uv(f"eye_white_{side}", (sx * eye_x, -0.61 * k * head_k, eye_z),
           (0.15 * k * head_k, 0.055 * k, z(0.18) * head_k), palette["eye_white"], 24, 12)
        uv(f"iris_{side}", (sx * eye_x, -0.665 * k * head_k, eye_z),
           (0.075 * k * head_k, 0.026 * k, z(0.105) * head_k), iris, 20, 10)
        uv(f"pupil_{side}", (sx * eye_x, -0.688 * k * head_k, eye_z),
           (0.026 * k * head_k, 0.014 * k, z(0.055) * head_k), palette["dark"], 16, 8)
        uv(f"catchlight_{side}", (sx * eye_x - 0.022 * k, -0.706 * k * head_k, eye_z + z(0.047)),
           (0.018 * k, 0.010 * k, z(0.025)), palette["eye_white"], 12, 6)

    brow_delta = {"concern": 0.10, "alarm": -0.12, "resolve": -0.08, "stern": -0.10,
                  "surprise": 0.16, "analysis": -0.04}.get(expression, 0.0)
    for side, sx in (("L", -1), ("R", 1)):
        curve_line(f"brow_{side}", [(sx * 0.40 * k, -0.708 * k, eye_z + z(0.27 - sx * brow_delta)),
                                     (sx * 0.18 * k, -0.72 * k, eye_z + z(0.24 + sx * brow_delta))],
                   0.035 * k, hair)
    uv("nose", (0.0, -0.67 * k * head_k, head_center.z - z(0.05)),
       (0.065 * k, 0.06 * k, z(0.12)), palette["skin"], 20, 10)
    smile = expression in {"smile", "reassuring", "relief", "warmth", "victory"}
    mouth_z = head_center.z - z(0.28)
    mouth_points = [(-0.13 * k, -0.704 * k, mouth_z + (z(0.02) if smile else 0.0)),
                    (0.0, -0.72 * k, mouth_z - (z(0.06) if smile else z(0.01))),
                    (0.13 * k, -0.704 * k, mouth_z + (z(0.02) if smile else 0.0))]
    curve_line("mouth", mouth_points, 0.028 * k, palette["plum"])

    # Layered authored hair: scalp, directional locks, and flyaways.
    hair_scale = ((0.57, 0.51, 0.55) if not sd else
                  (0.67 * k * head_k, 0.58 * k * head_k, z(0.71) * head_k))
    uv("hair_cap", (0.0, 0.04, head_center.z + (0.13 if not sd else z(0.20))),
       hair_scale, hair, 36, 20)
    # Distinct side/back masses keep the silhouette readable before individual locks.
    if is_maeru:
        cone("hair_back_mass", (0.22 * k, 0.20, head_center.z - z(0.12)), 0.42 * k, 0.30 * k, z(1.18), hair,
             rotation=(0.07, -0.13, -0.10), vertices=12)
    else:
        cone("hair_left_mass", (-0.44 * k, 0.05, head_center.z - z(0.10)), 0.31 * k, 0.22 * k, z(1.34), hair,
             rotation=(0.08, 0.16, 0.10), vertices=12)
        cone("hair_right_mass", (0.44 * k, 0.05, head_center.z - z(0.10)), 0.31 * k, 0.22 * k, z(1.34), hair,
             rotation=(0.08, -0.16, -0.10), vertices=12)
    lock_count = 5 if is_maeru else 6
    for index in range(lock_count):
        angle = -1.0 + index * (2.0 / max(1, lock_count - 1))
        x = angle * 0.58 * k * head_k
        length = z((0.62 if is_maeru else 0.82) + 0.10 * math.cos(index)) * head_k
        curve_line(f"hair_lock_{index}", [(x * 0.72, -0.46 * k, head_center.z + z(0.58) * head_k),
                                           (x, -0.66 * k, head_center.z + z(0.20) * head_k),
                                           (x * 1.12, -0.45 * k, head_center.z + z(0.58) * head_k - length)],
                   0.060 * k * head_k, hair)
    curve_line("hair_flyaway", [(0.18 * k, 0.0, head_center.z + z(0.87) * head_k),
                                 (0.50 * k, -0.08, head_center.z + z(1.14) * head_k),
                                 (0.66 * k, -0.15, head_center.z + z(0.91) * head_k)],
               0.055 * k, hair)

    if is_maeru:
        # Offset lantern shield and rivet tool define the guardian silhouette.
        shield_x = (-1.38 - 0.12 * variant) * k
        front_prism("shield_plate", (shield_x, -0.28, z(2.78)), 0.62 * k,
                    z(1.10 + 0.10 * variant), 0.14 * k, palette["dark"], vertices=8, rotation_z=-0.05)
        torus("shield_core_ring", (shield_x, -0.42, z(2.85)), 0.34 * k, 0.075 * k, accent)
        uv("shield_core", (shield_x, -0.48, z(2.85)), (0.21 * k, 0.07 * k, z(0.30)), accent, 24, 12)
        cube("rivet_driver", (0.92 * k, -0.40, z(2.78)), (0.20 * k, 0.22 * k, z(0.48)), palette["dark"], bevel_width=0.08 * k)
        cube("copper_hair_clip", (-0.56 * k, -0.52, head_center.z + z(0.48)), (0.08 * k, 0.035, z(0.22)), accent, bevel_width=0.025)
    else:
        ring_x = (0.92 + 0.12 * variant) * k
        torus("diagnostic_frame", (ring_x, 0.22, z(3.82)), (0.74 + 0.07 * variant) * k, 0.075 * k, accent)
        cube("diagnostic_bridge", (ring_x - 0.42 * k, 0.20, z(3.82)), (0.42 * k, 0.06 * k, z(0.055)), accent,
             rotation=(0.0, 0.0, -0.18), bevel_width=0.04 * k)
        for node_index, node_angle in enumerate((-0.75, 0.0, 0.75)):
            uv(f"diagnostic_node_{node_index}",
               (ring_x + math.sin(node_angle) * (0.80 + 0.06 * variant) * k,
                0.18, z(3.82) + math.cos(node_angle) * z((0.80 + 0.06 * variant) * k)),
               (0.11 * k, 0.08 * k, z(0.11)), accent, 18, 10)
        for side in (-1, 1):
            capsule("medicine_capsule", (side * 0.76 * k, 0.04, z(2.60)), (side * 0.82 * k, -0.06, z(2.03)), 0.11 * k, accent)
        cube("support_device", (0.76 * k, -0.38, z(2.90)), (0.22 * k, 0.16 * k, z(0.48)), palette["cream"], bevel_width=0.09 * k)
    return objects
