"""Render every inventory prop as 12-up proof sheets for visual QA."""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets/models/mysteries"
OUT = ROOT / "docs/screenshots/mystery-props"
MANIFEST = json.loads((ASSET_ROOT / "manifest.json").read_text())["models"]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def look(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def place_asset(entry, slot):
    row, col = divmod(slot, 4)
    # Assets use the project convention: X right, Y up, Z forward.  The
    # proof sheet is therefore laid out across X/Z, never X/Y.
    x, z = (col - 1.5) * 3.25, (1 - row) * 2.85
    bpy.ops.import_scene.gltf(filepath=str(ASSET_ROOT / entry["path"]))
    objects = list(bpy.context.selected_objects)
    if not objects:
        raise RuntimeError(entry["path"])
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    center = sum(corners, Vector()) / len(corners)
    span = max(max(point[i] for point in corners) - min(point[i] for point in corners) for i in range(3))
    bpy.ops.object.empty_add(type="PLAIN_AXES")
    group = bpy.context.object
    for obj in objects:
        obj.parent = group
        obj.matrix_parent_inverse = group.matrix_world.inverted()
    group.location = -center
    scale = 1.72 / max(span, 0.01)
    group.scale = (scale, scale, scale)
    group.location += Vector((x, 0.20, z))


def setup_scene():
    world = bpy.context.scene.world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.009, 0.014, 0.024, 1)
    background.inputs["Strength"].default_value = 0.18
    # Blender's primitive plane is XY by default; rotate it into the XZ
    # ground plane so its normal agrees with the project's +Y-up convention.
    bpy.ops.mesh.primitive_plane_add(size=22, location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    floor = bpy.context.object
    material = bpy.data.materials.new("proof floor")
    material.diffuse_color = (0.035, 0.05, 0.08, 1)
    floor.data.materials.append(material)
    for location, energy, size in [((-6, 9, -5), 1200, 5), ((6, 7, -2), 950, 4), ((0, 8, 5), 850, 4)]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        look(light, (0, 0, 0))
    # View from in front of the assets (-Z) and above them (+Y).  This keeps
    # upright props upright and exposes their bases, e.g. plants in pots.
    bpy.ops.object.camera_add(location=(0, 16.0, -16.5))
    camera = bpy.context.object
    look(camera, (0, 0, 0.7))
    bpy.context.scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 15.5
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1350
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"


OUT.mkdir(parents=True, exist_ok=True)
for batch_index, first in enumerate(range(0, len(MANIFEST), 12), 1):
    clear()
    setup_scene()
    for slot, entry in enumerate(MANIFEST[first:first + 12]):
        place_asset(entry, slot)
    bpy.context.scene.render.filepath = str(OUT / f"batch-{batch_index:02d}.png")
    bpy.ops.render.render(write_still=True)
    print(f"Rendered batch {batch_index:02d}: {first + 1}-{min(first + 12, len(MANIFEST))}")
