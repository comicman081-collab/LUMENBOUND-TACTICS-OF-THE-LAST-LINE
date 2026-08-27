"""R7 deterministic Blender 4.5 LTS chapter-map kit builder.

The script creates original low-poly hex terrain, props, markers and a squad
standard as one reproducible .blend/.glb lineage. Reference images are never
loaded or packaged.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector


GENERATOR_VERSION = "lanternline-chapter-map-1.4.0-r11"
SEED = 20260818


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def refuse(path: Path) -> None:
    if path.exists():
        raise RuntimeError(f"Refusing silent overwrite: {path}")


def material(name: str, color: tuple[float, float, float, float], metallic=0.0, roughness=0.8, emission=None):
    value = bpy.data.materials.new(name)
    value.diffuse_color = color
    value.use_nodes = True
    principled = value.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    if emission:
        principled.inputs["Emission Color"].default_value = emission
        principled.inputs["Emission Strength"].default_value = 2.0
    return value


def bevel(obj, amount=0.06, segments=2):
    modifier = obj.modifiers.new("EDGE_SOFTEN", "BEVEL")
    modifier.width = amount
    modifier.segments = segments


def add_hex(name: str, location: tuple[float, float, float], height: float, mat, radius=1.0, cliff_mat=None):
    """Add a selectable terrain cap with a materially distinct cliff face.

    The top and side cannot share the same mint material: that is what made
    elevation read as a stack of toy pieces instead of a landform.  The runtime
    still uses these meshes only as local caps over its connected terrain.
    """
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=radius, depth=height, location=location, rotation=(0, 0, math.radians(30)))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if cliff_mat is not None:
        obj.data.materials.append(cliff_mat)
        for polygon in obj.data.polygons:
            # Local +Z is the walkable top face.  The underside deliberately
            # shares the darker rock material with the exposed cliff walls.
            polygon.material_index = 0 if polygon.normal.z > 0.5 else 1
    bevel(obj, min(0.075, height * 0.14), 2)
    return obj


def add_contour_landmass(name: str, location, radii, depth, top_mat, cliff_mat):
    """Create a single authored island shelf below the gameplay hexes.

    Gameplay still uses axial hex coordinates; this is deliberately a visual
    under-layer.  It breaks the silhouette of a board made from detached,
    identical extrusions without changing tile adjacency or pathfinding.
    """
    count = len(radii)
    vertices = []
    for index, radius in enumerate(radii):
        angle = math.tau * float(index) / float(count)
        vertices.append((math.cos(angle) * radius, math.sin(angle) * radius, 0.0))
    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(vertices + [(x, y, -depth) for x, y, _z in vertices], [], [])
    faces = [tuple(range(count)), tuple(range(count, count * 2))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, nxt + count, index + count))
    mesh.clear_geometry()
    mesh.from_pydata(vertices + [(x, y, -depth) for x, y, _z in vertices], [], faces)
    mesh.materials.append(top_mat)
    mesh.materials.append(cliff_mat)
    for polygon in mesh.polygons:
        polygon.material_index = 0 if polygon.index == 0 else 1
    shelf = bpy.data.objects.new(name, mesh)
    shelf.location = location
    bpy.context.collection.objects.link(shelf)
    bevel(shelf, 0.08, 2)
    return shelf


def add_tide_field(name: str, location, radius_x, radius_y, mat):
    """A continuous tidal field; water must read as water, not a ring of tiles."""
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=1.0, fill_type="TRIFAN", location=location)
    field = bpy.context.object
    field.name = name
    field.scale = (radius_x, radius_y, 1.0)
    field.data.materials.append(mat)
    return field


def add_signal_spine(name: str, location, metal_mat, amber_mat, teal_mat, scale=1.0, angle=0.0):
    """Infrastructure language for a route, replacing the old peach rectangle."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(location[0], location[1], location[2] + 0.11 * scale), rotation=(0.0, 0.0, angle))
    rail = bpy.context.object
    rail.name = name + "_RAIL"
    rail.scale = (0.70 * scale, 0.115 * scale, 0.09 * scale)
    rail.data.materials.append(metal_mat)
    bevel(rail, 0.045 * scale, 2)
    for index, offset in enumerate((-0.36, 0.0, 0.36)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.065 * scale, depth=0.055 * scale, location=(location[0] + math.cos(angle) * offset * scale, location[1] + math.sin(angle) * offset * scale, location[2] + 0.21 * scale), rotation=(0.0, 0.0, angle + math.radians(30)))
        relay = bpy.context.object
        relay.name = f"{name}_RELAY_{index}"
        relay.data.materials.append(amber_mat if index != 1 else teal_mat)
    for side in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(location[0] + math.sin(angle) * side * 0.20 * scale, location[1] - math.cos(angle) * side * 0.20 * scale, location[2] + 0.15 * scale), rotation=(0.0, 0.0, angle))
        rib = bpy.context.object
        rib.name = f"{name}_RIB_{'L' if side < 0 else 'R'}"
        rib.scale = (0.48 * scale, 0.025 * scale, 0.045 * scale)
        rib.data.materials.append(amber_mat)
        bevel(rib, 0.018 * scale, 1)


def add_strata_ring(name: str, location, cliff_mat, moss_mat, scale=1.0, angle=0.0):
    """Irregular shelf strata that makes elevation read as rock rather than a skirt."""
    for index, (dx, dy, size, tilt) in enumerate(((-0.64, -0.15, 0.30, -16), (-0.30, -0.62, 0.22, 12), (0.40, -0.53, 0.26, -9), (0.64, 0.12, 0.28, 15), (0.18, 0.62, 0.20, -12))):
        ca, sa = math.cos(angle), math.sin(angle)
        rx, ry = dx * ca - dy * sa, dx * sa + dy * ca
        bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=size * scale, radius2=size * 0.58 * scale, depth=0.35 * scale, location=(location[0] + rx * scale, location[1] + ry * scale, location[2] + 0.16 * scale), rotation=(math.radians(tilt), math.radians(tilt * 0.35), angle + index * 0.62))
        stratum = bpy.context.object
        stratum.name = f"{name}_STRATUM_{index}"
        stratum.scale = (1.15, 0.72, 1.0)
        stratum.data.materials.append(cliff_mat if index % 2 == 0 else moss_mat)
        bevel(stratum, 0.026, 1)


def add_cliff_facet(name: str, location, mat, scale=1.0, angle=0.0):
    """A deliberately irregular rock face used around elevated hex caps.

    The R4 kit treated elevation as only a taller cylinder. R5 adds authored
    faceted cliff silhouettes so height is legible at gameplay camera distance.
    """
    bpy.ops.mesh.primitive_cone_add(
        vertices=5,
        radius1=0.30 * scale,
        radius2=0.18 * scale,
        depth=0.72 * scale,
        location=(location[0], location[1], location[2] + 0.36 * scale),
        rotation=(0.12, 0.0, angle),
    )
    facet = bpy.context.object
    facet.name = name
    facet.scale = (1.0, 0.62, 1.0)
    facet.data.materials.append(mat)
    bevel(facet, 0.035, 1)
    return facet


def add_crystal_cluster(name: str, location, core_mat, glow_mat, scale=1.0):
    """Project-specific teal relay growth, not a generic forest prop."""
    for index, (dx, dy, height, lean) in enumerate(((-0.10, 0.02, 0.34, -12), (0.10, 0.05, 0.50, 10), (0.02, -0.12, 0.26, 4))):
        bpy.ops.mesh.primitive_cone_add(
            vertices=4,
            radius1=0.09 * scale,
            radius2=0.015 * scale,
            depth=height * scale,
            location=(location[0] + dx * scale, location[1] + dy * scale, location[2] + height * scale * 0.5),
            rotation=(math.radians(lean), math.radians(-lean * 0.4), math.radians(index * 38)),
        )
        shard = bpy.context.object
        shard.name = f"{name}_SHARD_{index}"
        shard.data.materials.append(glow_mat if index == 1 else core_mat)
        bevel(shard, 0.012, 1)


def add_relay_lamp(name: str, location, metal_mat, glow_mat, scale=1.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.07 * scale, depth=0.62 * scale, location=(location[0], location[1], location[2] + 0.31 * scale))
    stem = bpy.context.object
    stem.name = name + "_STEM"
    stem.data.materials.append(metal_mat)
    bevel(stem, 0.018, 1)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.14 * scale, location=(location[0], location[1], location[2] + 0.68 * scale))
    lantern = bpy.context.object
    lantern.name = name + "_LANTERN"
    lantern.scale.z = 1.16
    lantern.data.materials.append(glow_mat)


def add_route_plinth(name: str, location, stone_mat, trim_mat, scale=1.0):
    """Raised signal-road language shared by map and battle transition."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.58 * scale, depth=0.13 * scale, location=(location[0], location[1], location[2] + 0.065 * scale), rotation=(0, 0, math.radians(30)))
    base = bpy.context.object
    base.name = name + "_BASE"
    base.data.materials.append(stone_mat)
    bevel(base, 0.03, 1)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.36 * scale, minor_radius=0.035 * scale, major_segments=6, minor_segments=5, location=(location[0], location[1], location[2] + 0.145 * scale), rotation=(0, 0, math.radians(30)))
    trim = bpy.context.object
    trim.name = name + "_TRIM"
    trim.data.materials.append(trim_mat)


def add_tree(name: str, location, trunk_mat, crown_mat, scale=1.0):
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=0.16 * scale, radius2=0.085 * scale, depth=0.84 * scale, location=(location[0], location[1], location[2] + 0.42 * scale))
    trunk = bpy.context.object
    trunk.name = name + "_TRUNK"
    trunk.data.materials.append(trunk_mat)
    bevel(trunk, 0.025, 1)
    # Three directional canopy masses give the tree a readable silhouette without
    # becoming the single-sphere placeholder used by the rejected R4 view.
    for index, (offset, size, twist) in enumerate([((0, 0, 0.96), 0.43, 0), ((0.24, -0.10, 1.03), 0.30, 27), ((-0.22, 0.11, 1.09), 0.28, -24)]):
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=size * scale, radius2=size * 0.46 * scale, depth=size * 1.18 * scale, location=(location[0] + offset[0] * scale, location[1] + offset[1] * scale, location[2] + offset[2] * scale), rotation=(math.radians(7), math.radians(-5), math.radians(twist)))
        crown = bpy.context.object
        crown.name = f"{name}_CROWN_{index}"
        crown.data.materials.append(crown_mat)
        bevel(crown, 0.045, 1)
    return trunk


def add_ruin(name: str, location, stone_mat, scale=1.0):
    for index, (offset, size, angle) in enumerate([
        ((-0.18, 0.00, 0.22), (0.20, 0.30, 0.44), -8),
        ((0.16, 0.03, 0.16), (0.24, 0.25, 0.32), 12),
        ((0.00, -0.16, 0.08), (0.52, 0.18, 0.16), 5),
    ]):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(location[0] + offset[0] * scale, location[1] + offset[1] * scale, location[2] + offset[2] * scale), rotation=(0, math.radians(angle), math.radians(angle * 0.6)))
        piece = bpy.context.object
        piece.name = f"{name}_{index}"
        piece.scale = Vector(size) * scale
        piece.data.materials.append(stone_mat)
        bevel(piece, 0.045, 2)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.20 * scale, minor_radius=0.045 * scale, major_segments=8, minor_segments=5, location=(location[0] - 0.04 * scale, location[1] - 0.04 * scale, location[2] + 0.42 * scale), rotation=(math.radians(90), 0, math.radians(15)))
    arch = bpy.context.object
    arch.name = f"{name}_ARCH"
    arch.data.materials.append(stone_mat)


def add_marker(name: str, location, base_mat, glow_mat, shape="NORMAL"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.54, depth=0.10, location=(location[0], location[1], location[2] + 0.16), rotation=(0, 0, math.radians(30)))
    base = bpy.context.object
    base.name = name + "_BASE"
    base.data.materials.append(base_mat)
    bevel(base, 0.035, 2)
    if shape == "BOSS":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.065, major_segments=12, minor_segments=6, location=(location[0], location[1], location[2] + 0.58), rotation=(math.radians(90), 0, 0))
    elif shape == "ELITE":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.25, location=(location[0], location[1], location[2] + 0.58))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.24, radius2=0.08, depth=0.45, location=(location[0], location[1], location[2] + 0.56))
    symbol = bpy.context.object
    symbol.name = name + "_SYMBOL"
    symbol.data.materials.append(glow_mat)
    return base


def add_terrain_cluster(name: str, location, top_mat, cliff_mat, accent_mat, scale=1.0, variant=0):
    """An authored visual land mass spanning several logical hexes.

    The map's axial hexes remain invisible navigation data.  These overlapping,
    irregular shelves are the visible ground so the chapter never reads as a
    chess board made from individual cylinders.
    """
    profiles = (
        [1.72, 1.43, 1.88, 1.51, 1.78, 1.46, 1.91, 1.57, 1.69, 1.48],
        [1.56, 1.86, 1.48, 1.77, 1.50, 1.92, 1.43, 1.72, 1.58, 1.83],
    )
    radii = [radius * scale for radius in profiles[variant % len(profiles)]]
    shelf = add_contour_landmass(name + "_BED", location, radii, 0.46 * scale, top_mat, cliff_mat)
    shelf.rotation_euler.z = math.radians(17 + variant * 19)
    for index, (dx, dy, rock_scale) in enumerate(((-0.98, -0.36, 0.78), (0.72, -0.58, 0.60), (0.98, 0.42, 0.67), (-0.48, 0.75, 0.55))):
        add_rock_cluster(
            f"{name}_ROCK_{index}",
            (location[0] + dx * scale, location[1] + dy * scale, location[2] + 0.10 * scale),
            cliff_mat,
            rock_scale * scale,
        )
    for index, (dx, dy) in enumerate(((-0.34, -0.52), (0.30, 0.45), (0.66, 0.02))):
        add_ground_detail(
            f"{name}_ACCENT_{index}",
            (location[0] + dx * scale, location[1] + dy * scale, location[2] + 0.22 * scale),
            top_mat,
            accent_mat,
            1.18 * scale,
        )
    return shelf


def add_signal_tower(name: str, location, stone_mat, metal_mat, glow_mat, scale=1.0, damaged=True):
    """A tall, broken route relay: the chapter's long-distance visual motif."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.44 * scale, depth=0.24 * scale, location=(location[0], location[1], location[2] + 0.12 * scale))
    base = bpy.context.object
    base.name = name + "_BASE"
    base.data.materials.append(stone_mat)
    bevel(base, 0.04 * scale, 2)
    for index, (dx, dy, height, lean) in enumerate(((-0.14, 0.0, 2.02, -8), (0.16, 0.02, 1.70, 10), (0.0, -0.12, 2.28 if not damaged else 1.48, 3))):
        bpy.ops.mesh.primitive_cone_add(
            vertices=5,
            radius1=0.10 * scale,
            radius2=0.045 * scale,
            depth=height * scale,
            location=(location[0] + dx * scale, location[1] + dy * scale, location[2] + 0.24 * scale + height * scale * 0.5),
            rotation=(math.radians(lean), math.radians(-lean * 0.25), math.radians(index * 27)),
        )
        mast = bpy.context.object
        mast.name = f"{name}_MAST_{index}"
        mast.data.materials.append(metal_mat)
        bevel(mast, 0.018 * scale, 1)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.42 * scale, minor_radius=0.052 * scale, major_segments=12, minor_segments=5, location=(location[0], location[1], location[2] + 1.54 * scale), rotation=(math.radians(90), 0.0, math.radians(20)))
    broken_ring = bpy.context.object
    broken_ring.name = name + "_BROKEN_RING"
    broken_ring.data.materials.append(glow_mat)
    for index, (dx, dy, dz, length, angle) in enumerate(((-0.56, -0.18, 1.35, 1.15, -24), (0.52, 0.20, 1.12, 0.92, 31))):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(location[0] + dx * scale, location[1] + dy * scale, location[2] + dz * scale), rotation=(math.radians(62), math.radians(0), math.radians(angle)))
        cable = bpy.context.object
        cable.name = f"{name}_SEVERED_CABLE_{index}"
        cable.scale = (0.024 * scale, 0.024 * scale, length * scale)
        cable.data.materials.append(metal_mat)
        bevel(cable, 0.008 * scale, 1)
    return base


def add_dormant_rail(name: str, location, metal_mat, glow_mat, scale=1.0):
    """A visible broken signal rail, not a coloured hex route."""
    for side in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(location[0] + side * 0.18 * scale, location[1], location[2] + 0.09 * scale))
        rail = bpy.context.object
        rail.name = f"{name}_RAIL_{'L' if side < 0 else 'R'}"
        rail.scale = (0.075 * scale, 0.86 * scale, 0.055 * scale)
        rail.data.materials.append(metal_mat)
        bevel(rail, 0.018 * scale, 1)
    for index, offset in enumerate((-0.56, -0.18, 0.21, 0.59)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(location[0], location[1] + offset * scale, location[2] + 0.055 * scale))
        tie = bpy.context.object
        tie.name = f"{name}_TIE_{index}"
        tie.scale = (0.54 * scale, 0.065 * scale, 0.05 * scale)
        tie.data.materials.append(glow_mat if index == 2 else metal_mat)
        bevel(tie, 0.014 * scale, 1)


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("WORLD_CH01_MAP")
    scene.world.color = (0.012, 0.03, 0.055)
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.018, 0.055, 0.085, 1.0)
    background.inputs["Strength"].default_value = 0.34
    scene.view_settings.look = "AgX - Medium High Contrast"
    return scene


def setup_camera():
    bpy.ops.object.camera_add(location=(10.8, -13.4, 13.0))
    camera = bpy.context.object
    camera.name = "CAMERA_CH01_MAP"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 12.6
    direction = Vector((1.8, 0.4, 0.0)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(1.5, -2.0, 11.0))
    key = bpy.context.object
    key.name = "KEY_WARM"
    key.data.energy = 1300
    key.data.shape = "DISK"
    key.data.size = 8.0
    key.data.color = (1.0, 0.82, 0.63)
    bpy.ops.object.light_add(type="AREA", location=(-7.0, 4.0, 7.0))
    fill = bpy.context.object
    fill.name = "FILL_TEAL"
    fill.data.energy = 850
    fill.data.size = 7.0
    fill.data.color = (0.28, 0.72, 0.70)
    return camera


def aim_camera(camera, target: tuple[float, float, float], ortho_scale: float):
    offset = Vector((10.8, -13.4, 13.0))
    center = Vector(target)
    camera.location = center + offset
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = ortho_scale


def add_rock_cluster(name, location, mat, scale=1.0):
    for index, offset in enumerate(((-0.16, 0.02, 0.10), (0.12, 0.04, 0.08), (0.02, -0.13, 0.06))):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=(0.13 - index * 0.02) * scale, location=(location[0] + offset[0] * scale, location[1] + offset[1] * scale, location[2] + offset[2] * scale))
        rock = bpy.context.object
        rock.name = f"{name}_{index}"
        rock.scale = (1.2, 0.82, 0.72)
        rock.data.materials.append(mat)


def add_ground_detail(name, location, moss_mat, glow_mat, scale=1.0):
    """Small layered ground accents that survive the isometric camera distance."""
    for index, (dx, dy, radius) in enumerate(((-0.20, 0.08, 0.10), (0.16, 0.16, 0.075), (0.05, -0.19, 0.06))):
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1,
            radius=radius * scale,
            location=(location[0] + dx * scale, location[1] + dy * scale, location[2] + radius * 0.38),
        )
        tuft = bpy.context.object
        tuft.name = f"{name}_MOSS_{index}"
        tuft.scale.z = 0.32
        tuft.data.materials.append(moss_mat)
    for index, (dx, dy) in enumerate(((0.27, -0.06), (-0.08, -0.27))):
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1,
            radius=0.038 * scale,
            location=(location[0] + dx * scale, location[1] + dy * scale, location[2] + 0.055),
        )
        bloom = bpy.context.object
        bloom.name = f"{name}_BLOOM_{index}"
        bloom.data.materials.append(glow_mat)


def add_coast_foam(name, location, foam_mat, scale=1.0):
    for index, (dx, dy, radius, angle) in enumerate(((-0.24, -0.20, 0.22, 22), (0.08, -0.30, 0.18, -8), (0.30, -0.15, 0.16, -28))):
        bpy.ops.mesh.primitive_torus_add(major_radius=radius * scale, minor_radius=0.017 * scale, major_segments=12, minor_segments=4, location=(location[0] + dx * scale, location[1] + dy * scale, location[2] + 0.032), rotation=(0, 0, math.radians(angle)))
        foam = bpy.context.object
        foam.name = f"{name}_ARC_{index}"
        foam.scale.y = 0.42
        foam.data.materials.append(foam_mat)


def add_full_map_preview(mats, center_y=18.0):
    """Render an authored coast, not a ring of repeated blue hexes.

    The navigable surface remains hex-based.  A continuous tide field and an
    irregular island shelf make the kit read as a place first, and a grid only
    after the player needs to make a move.
    """
    route = {(0, 0), (1, 0), (2, 0), (2, -1), (1, -1), (0, -1), (-1, 0), (-2, 1)}
    radius = 3
    add_tide_field("MAP_CONTINUOUS_TIDE", (0.0, center_y, -0.18), 7.8, 6.7, mats["deep"])
    add_contour_landmass(
        "MAP_AUTHORED_ISLAND_SHELF", (0.0, center_y, 0.22),
        [5.0, 5.6, 4.8, 5.35, 4.9, 5.8, 5.1, 5.45, 4.7, 5.25, 5.65, 4.95],
        0.78, mats["moss"], mats["cliff"],
    )
    for q in range(-radius, radius + 1):
        for r in range(-radius, radius + 1):
            if max(abs(q), abs(r), abs(q + r)) > radius:
                continue
            # The coast is a continuous backdrop.  Only author purposeful land
            # tiles above it rather than turning water into a detached hex ring.
            if max(abs(q), abs(r), abs(q + r)) == radius:
                continue
            x = math.sqrt(3.0) * (q + r * 0.5) * 1.03
            y = center_y + 1.5 * r * 1.03
            terrain = "road" if (q, r) in route else ("ruin" if (q * 7 + r * 5) % 8 == 0 else "forest")
            elevation = 0.86 if (q + 2 * r) % 7 == 0 else (0.64 if terrain == "ruin" else 0.52)
            add_hex(f"MAP_{q}_{r}_{terrain.upper()}", (x, y, elevation * 0.5), elevation, mats[terrain], cliff_mat=mats["cliff"])
            if elevation >= 0.80:
                add_strata_ring(f"MAP_STRATA_{q}_{r}", (x, y, elevation * 0.42), mats["cliff"], mats["moss"], 0.92, (q-r) * 0.18)
            if terrain == "forest":
                add_ground_detail(f"MAP_DETAIL_{q}_{r}", (x, y, elevation), mats["moss"], mats["teal"], 0.82)
                if (q * 3 + r) % 3 != 1:
                    add_tree(f"MAP_TREE_{q}_{r}_A", (x - 0.34, y + 0.18, elevation), mats["trunk"], mats["crown"], 0.62 + 0.06 * ((q-r) % 3))
                if (q - 2 * r) % 5 == 0:
                    add_tree(f"MAP_TREE_{q}_{r}_B", (x + 0.32, y - 0.12, elevation), mats["trunk"], mats["crown_light"], 0.48)
                if (q + r) % 4 == 0:
                    add_crystal_cluster(f"MAP_CRYSTAL_{q}_{r}", (x + 0.28, y - 0.22, elevation), mats["forest_light"], mats["teal"], 0.58)
            elif terrain == "ruin":
                add_ruin(f"MAP_RUIN_{q}_{r}", (x + 0.10, y, elevation), mats["stone"], 0.70)
                add_relay_lamp(f"MAP_RELAY_{q}_{r}", (x - 0.36, y - 0.20, elevation), mats["stone"], mats["teal"], 0.68)
            elif terrain == "road":
                add_route_plinth(f"MAP_ROUTE_PLINTH_{q}_{r}", (x, y, elevation), mats["road"], mats["amber"], 0.82)
                add_signal_spine(f"MAP_SIGNAL_SPINE_{q}_{r}", (x, y, elevation + 0.13), mats["stone"], mats["amber"], mats["teal"], 0.82, math.radians(30 if (q + r) % 2 else -30))
    # Sparse shoreline language: reefs and foam appear along the island coast,
    # not once-per-hex as a visibly repeated prefab.
    for index, (dx, dy, scale, angle) in enumerate(((-4.3, -2.4, 1.1, 18), (4.5, -1.8, 0.82, -22), (-3.5, 2.75, 0.92, 38), (3.7, 2.9, 1.18, -34))):
        add_rock_cluster(f"MAP_COAST_REEF_{index}", (dx, center_y + dy, 0.04), mats["cliff"], scale)
        add_coast_foam(f"MAP_COAST_FOAM_{index}", (dx, center_y + dy, 0.04), mats["foam"], scale)
    add_marker("MAP_START", (0.0, center_y, 0.60), mats["teal"], mats["teal"], "NORMAL")
    add_marker("MAP_ELITE", (math.sqrt(3.0) * 2.0 * 1.03, center_y, 0.60), mats["teal"], mats["amber"], "ELITE")
    add_marker("MAP_BOSS", (-math.sqrt(3.0) * 1.5 * 1.03, center_y + 1.5 * 1.03, 0.60), mats["violet"], mats["amber"], "BOSS")


def build_kit(project_root: Path, revision: str, factory_root: Path):
    source_dir = factory_root / "blender_sources" / "chapter_map" / f"CH01_MAP_KIT_{revision}"
    export_dir = factory_root / "exports" / "premium" / "chapter_map" / revision
    runtime_dir = project_root / "godot" / "assets" / "art" / "chapter_map" / revision
    report_dir = project_root / "reports" / "r7_srpg_map" / "contact_sheets" / "revisions" / revision
    for directory in (source_dir, export_dir, runtime_dir, report_dir):
        directory.mkdir(parents=True, exist_ok=True)
    blend_path = source_dir / f"CH01_MAP_KIT_{revision}.blend"
    glb_path = export_dir / f"CH01_MAP_KIT_{revision}.glb"
    render_path = report_dir / "CH01_TILE_LIBRARY.png"
    full_map_path = report_dir / "CH01_FULL_MAP.png"
    manifest_path = export_dir / "map_asset_manifest.json"
    for path in (blend_path, glb_path, render_path, full_map_path, manifest_path):
        refuse(path)

    scene = setup_scene()
    mats = {
        # R10 explicitly rejects the lingering all-teal grade.  Material roles
        # must remain legible after the Web environment pass: mossy olive land,
        # burnished ochre routes, cool slate ruins, cobalt water and blue-grey
        # cliff strata—not five values of the same cyan-green.
        "forest": material("MAT_FOREST_MOSS", (0.060, 0.205, 0.065, 1), 0.0, 0.80),
        "forest_light": material("MAT_FOREST_LICHEN", (0.190, 0.285, 0.070, 1), 0.0, 0.74),
        "road": material("MAT_RELAY_ROAD", (0.390, 0.200, 0.055, 1), 0.0, 0.68),
        "ruin": material("MAT_SIGNAL_RUIN", (0.180, 0.220, 0.285, 1), 0.06, 0.74),
        "water": material("MAT_TIDAL_GLASS", (0.018, 0.160, 0.500, 1), 0.12, 0.20),
        "deep": material("MAT_DEEP_TIDE", (0.008, 0.036, 0.145, 1), 0.16, 0.28),
        "cliff": material("MAT_CLIFF_EDGE", (0.060, 0.095, 0.115, 1), 0.0, 0.88),
        "trunk": material("MAT_BARK", (0.155, 0.070, 0.030, 1)),
        "crown": material("MAT_LANTERN_CANOPY", (0.025, 0.115, 0.050, 1), 0.0, 0.82),
        "crown_light": material("MAT_LANTERN_CANOPY_LIGHT", (0.120, 0.255, 0.070, 1), 0.0, 0.76),
        "moss": material("MAT_GROUND_MOSS", (0.080, 0.165, 0.040, 1), 0.0, 0.88),
        "foam": material("MAT_TIDAL_FOAM", (0.50, 0.88, 0.95, 1), 0.0, 0.30, (0.08, 0.36, 0.54, 1)),
        "stone": material("MAT_RUIN_STONE", (0.36, 0.39, 0.46, 1), 0.06, 0.64),
        "teal": material("MAT_SIGNAL_TEAL", (0.08, 0.57, 0.62, 1), 0.18, 0.26, (0.03, 0.66, 0.76, 1)),
        "amber": material("MAT_SIGNAL_AMBER", (0.90, 0.42, 0.08, 1), 0.18, 0.24, (1.0, 0.18, 0.02, 1)),
        "violet": material("MAT_HARD_VIOLET", (0.42, 0.22, 0.64, 1), 0.2, 0.28, (0.50, 0.16, 0.9, 1)),
    }

    positions = []
    terrains = ["forest", "forest_light", "road", "ruin", "water", "deep"]
    for index, terrain in enumerate(terrains):
        x = (index % 3) * 2.25 - 2.25
        y = (index // 3) * 2.15 - 1.0
        height = 0.52 if terrain not in ("water", "deep") else 0.24
        tile = add_hex(f"HEX_{terrain.upper()}_{index:02d}", (x, y, height * 0.5), height, mats[terrain], cliff_mat=mats["cliff"])
        positions.append(tile)
        if terrain.startswith("forest"):
            add_tree(f"TREE_{index:02d}", (x - 0.28, y + 0.12, height), mats["trunk"], mats["crown"], 0.78)
            add_ground_detail(f"GROUND_DETAIL_{index:02d}", (x + 0.18, y - 0.12, height), mats["moss"], mats["teal"], 0.9)
        elif terrain == "ruin":
            add_ruin("RUIN_SET", (x, y, height), mats["stone"], 0.86)
        elif terrain == "road":
            add_route_plinth("ROAD_RELAY_PLINTH", (x, y, height), mats["road"], mats["amber"], 0.88)
            add_signal_spine("ROAD_SIGNAL_SPINE", (x, y, height + 0.12), mats["stone"], mats["amber"], mats["teal"], 0.88, math.radians(-30))
        elif terrain in ("water", "deep"):
            add_coast_foam(f"COAST_FOAM_{index:02d}", (x, y, height), mats["foam"], 0.9)

    add_marker("MARKER_NORMAL", (-2.25, -1.0, 0.52), mats["teal"], mats["teal"], "NORMAL")
    add_marker("MARKER_ELITE", (0.0, -1.0, 0.52), mats["teal"], mats["amber"], "ELITE")
    add_marker("MARKER_BOSS", (2.25, -1.0, 0.52), mats["violet"], mats["amber"], "BOSS")
    add_marker("MARKER_HARD_GATE", (0.0, 1.15, 0.52), mats["violet"], mats["violet"], "BOSS")

    # Runtime component rack. Objects live outside the contact-sheet framing but
    # retain reproducible Blender geometry/materials for Godot to instantiate.
    rack = (22.0, -18.0, 0.0)
    add_tree("PROP_TREE_A", rack, mats["trunk"], mats["crown"], 1.0)
    add_tree("PROP_TREE_B", (rack[0] + 2.0, rack[1], 0.0), mats["trunk"], mats["crown_light"], 0.74)
    add_ruin("PROP_RUIN_RELAY", (rack[0] + 4.0, rack[1], 0.0), mats["stone"], 1.0)
    add_relay_lamp("PROP_RELAY_LAMP", (rack[0] + 6.0, rack[1], 0.0), mats["stone"], mats["teal"], 1.0)
    add_crystal_cluster("PROP_CRYSTAL", (rack[0] + 8.0, rack[1], 0.0), mats["forest_light"], mats["teal"], 1.0)
    add_route_plinth("PROP_ROUTE_PLINTH", (rack[0] + 10.0, rack[1], 0.0), mats["road"], mats["amber"], 1.0)
    add_cliff_facet("PROP_CLIFF_FACET_A", (rack[0] + 12.0, rack[1], 0.0), mats["cliff"], 1.0, 0.32)
    add_cliff_facet("PROP_CLIFF_FACET_B", (rack[0] + 13.0, rack[1] + 0.20, 0.0), mats["cliff"], 0.72, -0.48)
    add_coast_foam("PROP_COAST_FOAM", (rack[0] + 15.0, rack[1], 0.0), mats["foam"], 1.0)
    add_signal_spine("PROP_SIGNAL_SPINE", (rack[0] + 17.0, rack[1], 0.0), mats["stone"], mats["amber"], mats["teal"], 1.0, math.radians(30))
    add_strata_ring("PROP_STRATA_RING", (rack[0] + 19.0, rack[1], 0.0), mats["cliff"], mats["moss"], 1.0, 0.0)
    # R7 visible-world components.  These intentionally span multiple logical
    # hexes and give the player a genuine terrain silhouette before the route
    # overlay appears.  They are kept on the runtime rack, outside render view.
    add_terrain_cluster("PROP_TERRAIN_FOREST", (rack[0] + 23.0, rack[1], 0.0), mats["forest"], mats["cliff"], mats["teal"], 1.0, 0)
    add_terrain_cluster("PROP_TERRAIN_RUIN", (rack[0] + 27.0, rack[1], 0.0), mats["ruin"], mats["cliff"], mats["amber"], 1.0, 1)
    add_dormant_rail("PROP_DORMANT_RAIL", (rack[0] + 31.0, rack[1], 0.0), mats["stone"], mats["amber"], 1.0)
    add_signal_tower("PROP_SIGNAL_TOWER", (rack[0] + 34.0, rack[1], 0.0), mats["stone"], mats["cliff"], mats["teal"], 1.0, True)
    add_signal_tower("PROP_SIGNAL_BEACON", (rack[0] + 37.5, rack[1], 0.0), mats["stone"], mats["cliff"], mats["amber"], 0.78, False)

    # Original squad-standard token: layered octagonal relay crest.
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.48, depth=0.20, location=(4.0, 0.0, 0.45))
    standard = bpy.context.object
    standard.name = "SQUAD_STANDARD_RELAY_CREST"
    standard.data.materials.append(mats["teal"])
    bevel(standard, 0.055, 2)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.28, minor_radius=0.055, major_segments=16, minor_segments=6, location=(4.0, 0.0, 0.62))
    crest_ring = bpy.context.object
    crest_ring.name = "SQUAD_STANDARD_SIGNAL_RING"
    crest_ring.data.materials.append(mats["amber"])

    camera = setup_camera()
    scene.render.filepath = str(render_path)
    bpy.ops.render.render(write_still=True)
    add_full_map_preview(mats)
    aim_camera(camera, (0.0, 18.0, 0.0), 14.5)
    bpy.data.objects["KEY_WARM"].location.y = 16.0
    bpy.data.objects["FILL_TEAL"].location.y = 20.0
    bpy.ops.object.light_add(type="SUN", location=(0.0, 18.0, 12.0), rotation=(math.radians(28), math.radians(-18), math.radians(22)))
    sun = bpy.context.object
    sun.name = "MAP_SUN_SOFT"
    sun.data.energy = 1.8
    sun.data.color = (1.0, 0.84, 0.66)
    scene.render.filepath = str(full_map_path)
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format="GLB", export_apply=True, export_cameras=False, export_lights=False)
    runtime_glb = runtime_dir / glb_path.name
    shutil.copy2(glb_path, runtime_glb)

    manifest = {
        "asset_id": f"CH01_MAP_KIT_{revision}",
        "category": "chapter_map",
        "subtype": "hex_terrain_prop_marker_library",
        "biome": "LANTERN_FOREST_COAST",
        "source_blend": str(blend_path),
        "source_script": str(Path(__file__).resolve()),
        "blender_version": bpy.app.version_string,
        "generator_version": GENERATOR_VERSION,
        "seed": SEED,
        "mesh_path": str(glb_path),
        "runtime_path": str(runtime_glb),
        "material_count": len(mats),
        "object_count": len([obj for obj in bpy.data.objects if obj.type == "MESH"]),
        "triangle_count": sum(len(obj.data.polygons) for obj in bpy.data.objects if obj.type == "MESH"),
        "bounds": {"contact_sheet": [1920, 1080]},
        "contact_sheets": [str(render_path), str(full_map_path)],
        "pivot": "hex_center_ground",
        "license": "Original internal project asset",
        "commercial_use": True,
        "ownership_status": "ORIGINAL_INTERNAL",
        "sha256": sha256(glb_path),
        "qa_status": "ART_QA_CANDIDATE",
        "production_approved": False,
        "revision": revision,
        "runtime_components": [
            "PROP_TREE_A", "PROP_TREE_B", "PROP_RUIN_RELAY", "PROP_RELAY_LAMP",
            "PROP_CRYSTAL", "PROP_ROUTE_PLINTH", "PROP_CLIFF_FACET_A",
            "PROP_CLIFF_FACET_B", "PROP_COAST_FOAM", "PROP_SIGNAL_SPINE",
            "PROP_STRATA_RING", "PROP_TERRAIN_FOREST", "PROP_TERRAIN_RUIN",
            "PROP_DORMANT_RAIL", "PROP_SIGNAL_TOWER", "PROP_SIGNAL_BEACON",
            "MARKER_NORMAL", "MARKER_ELITE", "MARKER_BOSS", "MARKER_HARD_GATE",
            "SQUAD_STANDARD_RELAY_CREST", "SQUAD_STANDARD_SIGNAL_RING"
        ],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    shutil.copy2(manifest_path, runtime_dir / manifest_path.name)
    return manifest, render_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--revision", default="R1")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
    factory_root = Path(__file__).resolve().parents[3]
    manifest, render_path = build_kit(Path(args.project_root), args.revision, factory_root)
    print(f"R7_MAP_KIT_COMPLETE asset={manifest['asset_id']} render={render_path} sha256={manifest['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
