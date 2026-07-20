"""Render a quick visual QA sheet for representative generated mystery props."""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/screenshots/mystery-prop-sheet.png"
SAMPLES = [
    "assets/models/mysteries/bellwether-mysteries/the-last-garden-prize/exhibition-plant-cart.glb",
    "assets/models/mysteries/bellwether-mysteries/the-last-garden-prize/silver-garden-prize-cup.glb",
    "assets/models/mysteries/bellwether-mysteries/a-recipe-for-silence/engraved-tasting-spoon.glb",
    "assets/models/mysteries/one-more-question/the-final-cut/film-projector.glb",
    "assets/models/mysteries/one-more-question/a-private-performance/violin-bow-and-fitted-case.glb",
    "assets/models/mysteries/the-blackthorn-papers/the-empty-carriage/inspection-rail-carriage.glb",
]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def look(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


clear()
world = bpy.context.scene.world
world.color = (0.018, 0.024, 0.035)
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.018, 0.028, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22

for idx, rel in enumerate(SAMPLES):
    row, col = divmod(idx, 3)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / rel))
    selected = list(bpy.context.selected_objects)
    if not selected:
        raise RuntimeError(rel)
    corners = [obj.matrix_world @ Vector(corner) for obj in selected for corner in obj.bound_box]
    size = max(max(p[i] for p in corners) - min(p[i] for p in corners) for i in range(3))
    center = sum(corners, Vector()) / len(corners)
    bpy.ops.object.empty_add(type="PLAIN_AXES")
    group = bpy.context.object
    for obj in selected:
        obj.parent = group
        obj.matrix_parent_inverse = group.matrix_world.inverted()
    group.location = -center
    group.scale = (1.75 / max(size, 0.01),) * 3
    group.location += Vector(((col - 1) * 3.2, (0.7 - row) * 2.7, 0.28))

bpy.ops.mesh.primitive_plane_add(size=18, location=(0, 0, 0))
floor = bpy.context.object
mat = bpy.data.materials.new("floor")
mat.diffuse_color = (0.025, 0.035, 0.055, 1)
floor.data.materials.append(mat)

for location, energy, size in [((-4, -4, 7), 1100, 5), ((5, -1, 5), 800, 4), ((0, 5, 4), 700, 3)]:
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    look(light, (0, 0, 0))

bpy.ops.object.camera_add(location=(0, -11.5, 9.5))
camera = bpy.context.object
look(camera, (0, 0, 1.0))
bpy.context.scene.camera = camera
camera.data.lens = 50
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT)
scene.render.film_transparent = False
bpy.ops.render.render(write_still=True)
