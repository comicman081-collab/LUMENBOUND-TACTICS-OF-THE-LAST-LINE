"""Build original CH01 terrain-relief meshes without changing asset_share.

The resulting GLB is a small, reusable relief layer placed under the streamed
hex cells.  It deliberately uses wide irregular landforms rather than another
set of hex prisms, so the chapter reads as connected terrain at map scale.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Matrix


def material(name: str, rgba: tuple[float, float, float, float], roughness: float = 0.82):
    value = bpy.data.materials.new(name)
    value.use_nodes = True
    bsdf = value.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    return value


def landform(name: str, radii: list[tuple[float, float]], top_y: float, bottom_y: float, top_material, side_material):
    """Create one broad, bevelled, low-poly terrain form around local origin."""
    vertices: list[tuple[float, float, float]] = []
    count = len(radii)
    for x, z in radii:
        vertices.append((x, top_y, z))
    for x, z in radii:
        vertices.append((x * 1.05, bottom_y, z * 1.05))
    faces: list[tuple[int, ...]] = [tuple(range(count))]
    material_indices = [0]
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, next_index + count, index + count))
        material_indices.append(1)
    faces.append(tuple(range(count * 2 - 1, count - 1, -1)))
    material_indices.append(1)
    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(top_material)
    mesh.materials.append(side_material)
    for index, polygon in enumerate(mesh.polygons):
        polygon.material_index = material_indices[index]
        polygon.use_smooth = False
    object_value = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(object_value)
    bevel = object_value.modifiers.new("SOFTENED_STRATA", "BEVEL")
    bevel.width = 0.10
    bevel.segments = 2
    bpy.context.view_layer.objects.active = object_value
    object_value.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    object_value.select_set(False)
    return object_value


def ridge(name: str, placements: list[tuple[float, float, float, float]], material_value):
    """Join a sparse set of low-poly rock masses into a single reusable mesh."""
    pieces = []
    for index, (x, z, scale, tilt) in enumerate(placements):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=scale, location=(x, scale * 0.26, z))
        part = bpy.context.object
        part.name = f"{name}_PART_{index:02d}"
        part.scale = (1.45, 0.72, 0.82)
        part.rotation_euler = (0.12 * tilt, 0.18 * tilt, tilt)
        part.data.materials.append(material_value)
        pieces.append(part)
    bpy.ops.object.select_all(action="DESELECT")
    for part in pieces:
        part.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    # Export every reusable kit object around a zero origin. Godot instancing then
    # places the complete joined ridge at the requested map anchor.
    joined.data.transform(joined.matrix_world)
    joined.matrix_world = Matrix.Identity(4)
    return joined


def build(project_root: Path) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = project_root / "art_sources" / "chapter_map" / "R7"
    runtime = project_root / "godot" / "assets" / "art" / "chapter_map" / "R7"
    source.mkdir(parents=True, exist_ok=True)
    runtime.mkdir(parents=True, exist_ok=True)
    blend_path = source / "CH01_TERRAIN_RELIEF_R7.blend"
    glb_path = runtime / "CH01_TERRAIN_RELIEF_R7.glb"

    moss = material("RELIEF_MOSS_TOP", (0.12, 0.40, 0.28, 1.0))
    terrace = material("RELIEF_TERRACE_TOP", (0.29, 0.43, 0.31, 1.0))
    coast = material("RELIEF_COAST_TOP", (0.20, 0.38, 0.40, 1.0))
    earth = material("RELIEF_EARTH_SIDE", (0.095, 0.18, 0.16, 1.0))
    stone = material("RELIEF_STONE", (0.22, 0.29, 0.30, 1.0))

    landform(
        "RELIEF_FOREST_MESA_A",
        [(-3.2, -0.5), (-2.4, -1.8), (-0.6, -2.2), (1.3, -1.9), (3.1, -0.8), (3.3, 0.9), (1.7, 1.8), (-0.5, 2.15), (-2.8, 1.4), (-3.5, 0.3)],
        0.10,
        -0.62,
        moss,
        earth,
    )
    landform(
        "RELIEF_RUIN_TERRACE_B",
        [(-3.7, -0.7), (-2.2, -1.9), (0.2, -2.15), (2.8, -1.25), (3.8, 0.3), (2.2, 1.75), (-0.8, 1.92), (-3.4, 1.08)],
        0.14,
        -0.72,
        terrace,
        stone,
    )
    landform(
        "RELIEF_COAST_SHELF_C",
        [(-4.0, -0.42), (-2.8, -1.46), (-0.4, -1.72), (2.4, -1.30), (4.1, -0.25), (3.0, 1.15), (0.4, 1.54), (-2.6, 1.12)],
        0.06,
        -0.46,
        coast,
        stone,
    )
    ridge(
        "RELIEF_RIDGE_A",
        [(-1.8, -0.30, 0.52, -0.22), (-0.9, 0.18, 0.42, 0.18), (0.0, -0.10, 0.61, -0.12), (1.1, 0.22, 0.43, 0.26), (1.9, -0.22, 0.50, -0.16)],
        stone,
    )

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format="GLB", export_apply=True, export_cameras=False, export_lights=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[2]))
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
    build(Path(args.project_root))


if __name__ == "__main__":
    main()
