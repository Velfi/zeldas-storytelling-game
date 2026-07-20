"""Hand-built P0 hero props for the mystery campaigns.

This deliberately models the first reusable evidence kit as actual composed
objects rather than broad keyword-to-primitive stand-ins.  It writes into the
stable paths already declared by assets/models/mysteries/manifest.json.
"""

from __future__ import annotations

import math
import json
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mystery_prop_scale import target_max_span_m

ROOT = Path(__file__).resolve().parents[1]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for item in list(bpy.data.materials):
        bpy.data.materials.remove(item)


def material(name, color, metallic=0.0, roughness=0.45):
    item = bpy.data.materials.new(name)
    item.use_nodes = True
    shader = item.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return item


GOLD = lambda: material("Warm gold", (0.72, 0.37, 0.045, 1), 0.88, 0.18)
SILVER = lambda: material("Aged silver", (0.42, 0.46, 0.49, 1), 0.92, 0.24)
BRASS = lambda: material("Old brass", (0.52, 0.24, 0.025, 1), 0.75, 0.26)
STEEL = lambda: material("Blued steel", (0.09, 0.14, 0.18, 1), 0.88, 0.25)
IRON = lambda: material("Cast iron", (0.055, 0.065, 0.07, 1), 0.58, 0.48)
WOOD = lambda: material("Oiled walnut", (0.19, 0.062, 0.018, 1), 0.0, 0.33)
PALE_WOOD = lambda: material("Pale oak", (0.48, 0.25, 0.075, 1), 0.0, 0.42)
GLASS = lambda: material("Bottle green glass", (0.012, 0.18, 0.075, 1), 0.16, 0.13)
PAPER = lambda: material("Cream paper", (0.69, 0.58, 0.36, 1), 0.0, 0.72)
BLACK = lambda: material("Ebony", (0.01, 0.015, 0.02, 1), 0.06, 0.30)
RED = lambda: material("Wax red", (0.43, 0.012, 0.008, 1), 0.0, 0.34)
LEAF = lambda: material("Leaf green", (0.015, 0.28, 0.055, 1), 0.0, 0.5)
PETAL = lambda: material("Orchid petal", (0.61, 0.17, 0.42, 1), 0.0, 0.42)


def finish(obj, mat, bevel=0.0, smooth=False):
    obj.data.materials.append(mat)
    if bevel and obj.type == "MESH":
        mod = obj.modifiers.new("edge softness", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth and obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def cube(name, pos, dimensions, mat, bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, bevel)


def cylinder(name, pos, radius, depth, mat, vertices=24, rotation=None, bevel=0.01):
    base = Euler((math.pi / 2, 0, 0))
    adjustment = Euler(rotation or (0, 0, 0))
    final_rotation = (adjustment.to_matrix() @ base.to_matrix()).to_euler()
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos, rotation=final_rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, mat, bevel, True)


def cone(name, pos, r1, r2, depth, mat, vertices=24, rotation=None):
    base = Euler((math.pi / 2, 0, 0))
    adjustment = Euler(rotation or (0, 0, 0))
    final_rotation = (adjustment.to_matrix() @ base.to_matrix()).to_euler()
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=pos, rotation=final_rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, mat, 0.01, True)


def uv(name, pos, radius, mat, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, 0.0, True)


def torus(name, pos, major, minor, mat, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=10, location=pos, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, mat, 0.0, True)


def tube(name, points, radius, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, location in zip(spline.bezier_points, points):
        point.co = location
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def wheel(pos, radius=0.18, width=0.07):
    tire = cylinder("rubber wheel", pos, radius, width, BLACK(), 24, (math.pi / 2, 0, 0), 0.008)
    cylinder("brass wheel hub", (pos[0], pos[1], pos[2] - width / 2 - 0.005), radius * 0.32, width * 1.2, BRASS(), 16, (math.pi / 2, 0, 0))
    for angle in range(0, 360, 45):
        a = math.radians(angle)
        spoke = cube("wheel spoke", (pos[0] + math.cos(a) * radius * 0.45, pos[1] + math.sin(a) * radius * 0.45, pos[2] - width / 2 - 0.012), (radius * 0.85, 0.025, 0.018), BRASS(), 0.004)
        spoke.rotation_euler[2] = a


def trophy():
    gold = GOLD()
    black = BLACK()
    cylinder("ebony plinth", (0, 0.07, 0), 0.42, 0.14, black, 32, bevel=0.02)
    torus("plinth trim", (0, 0.14, 0), 0.34, 0.025, gold)
    cone("cup foot", (0, 0.25, 0), 0.20, 0.10, 0.17, gold)
    cylinder("cup stem", (0, 0.43, 0), 0.07, 0.24, gold, 20)
    cone("silver trophy bowl", (0, 0.72, 0), 0.42, 0.25, 0.47, SILVER(), 32)
    torus("trophy rim", (0, 0.955, 0), 0.42, 0.035, gold)
    for side in (-1, 1):
        tube("trophy handle", [(side * 0.30, 0.86, 0), (side * 0.55, 0.82, 0), (side * 0.54, 0.60, 0), (side * 0.34, 0.57, 0)], 0.035, gold)
    cube("engraved plaque", (0, 0.075, -0.425), (0.42, 0.07, 0.018), gold, 0.004)


def hose_guide():
    iron = IRON()
    brass = BRASS()
    cube("mounting plate", (0, 0.07, 0), (0.88, 0.14, 0.52), iron, 0.04)
    for x in (-0.30, 0.30):
        cylinder("mounting screw", (x, 0.15, -0.13), 0.045, 0.04, brass, 16)
    tube("arched hose guide", [(-0.33, 0.15, 0), (-0.37, 0.55, 0), (0, 0.72, 0), (0.37, 0.55, 0), (0.33, 0.15, 0)], 0.072, iron)
    torus("guide collar", (0, 0.54, 0), 0.17, 0.025, brass, (math.pi / 2, 0, 0))


def plant_cart():
    oak, steel = PALE_WOOD(), STEEL()
    cube("slatted cart bed", (0, 0.45, 0), (1.70, 0.12, 0.95), oak, 0.025)
    for x in (-0.58, -0.19, 0.19, 0.58):
        cube("individual slat", (x, 0.525, 0), (0.24, 0.035, 0.86), WOOD(), 0.008)
    for x in (-0.65, 0.65):
        for z in (-0.34, 0.34):
            wheel((x, 0.20, z))
    for z in (-0.38, 0.38):
        tube("cart handle", [(0.72, 0.50, z), (0.96, 0.76, z), (1.20, 0.78, z)], 0.034, steel)
    for x in (-0.75, 0.75):
        cube("end rail", (x, 0.70, 0), (0.045, 0.50, 0.92), steel, 0.012)
    for x in (-0.38, 0, 0.38):
        cone("display pot", (x, 0.67, 0), 0.16, 0.12, 0.22, material("terracotta", (0.36, 0.09, 0.025, 1), 0, 0.54), 20)


def orchid():
    pot = material("white ceramic", (0.64, 0.58, 0.48, 1), 0, 0.35)
    cone("pot/orchid pot", (0, 0.16, 0), 0.27, 0.20, 0.32, pot, 24)
    cylinder("pot/dark soil", (0, 0.325, 0), 0.20, 0.035, material("potting soil", (0.055, 0.020, 0.006, 1), 0, 0.92), 24)
    tube("plant/orchid stem", [(0, 0.32, 0), (0.02, 0.78, 0.02), (0.10, 1.10, 0.02)], 0.022, LEAF())
    for offset, y in [((-0.13, 0.52, 0), 0.52), ((0.12, 0.63, 0), 0.63), ((-0.08, 0.86, 0), 0.86)]:
        leaf = uv("plant/orchid leaf", offset, 0.18, LEAF(), (1.4, 0.18, 0.55))
        leaf.rotation_euler[1] = math.radians(25)
    for y in (0.84, 1.02, 1.18):
        for a in range(0, 360, 72):
            angle = math.radians(a)
            # Blooms face toward -Z: X/Y form the flower face and Z is its
            # thin axis.  Rotating around Z keeps every petal in that upright
            # plane in the project's Y-up basis.
            petal = uv("plant/orchid bloom", (0.10 + math.cos(angle) * 0.12, y + math.sin(angle) * 0.08, -0.02), 0.10, PETAL(), (1.0, 0.65, 0.18))
            petal.rotation_euler[2] = angle
        uv("plant/orchid center", (0.10, y, -0.02), 0.04, GOLD())


def spoon():
    silver = SILVER()
    uv("spoon bowl", (0.25, 0.06, 0), 0.23, silver, (0.85, 0.18, 1.18))
    cube("spoon handle", (-0.34, 0.055, 0), (0.84, 0.075, 0.10), silver, 0.035)
    torus("engraved ring", (-0.34, 0.10, 0), 0.065, 0.012, GOLD(), (math.pi / 2, 0, 0))
    uv("engraved monogram", (-0.34, 0.105, -0.01), 0.025, GOLD(), (1.0, 0.15, 1.0))


def herb_jar():
    glass, paper, red = GLASS(), PAPER(), RED()
    cylinder("faceted herb jar", (0, 0.31, 0), 0.22, 0.55, glass, 12, bevel=0.012)
    cylinder("jar lid", (0, 0.61, 0), 0.24, 0.08, BRASS(), 20, bevel=0.01)
    cube("handwritten label", (0, 0.32, -0.225), (0.24, 0.22, 0.012), paper, 0.003)
    cylinder("wax seal", (0.13, 0.56, -0.15), 0.05, 0.015, red, 16, (math.pi / 2, 0, 0))
    for x in (-0.10, 0, 0.10):
        uv("dried herb", (x, 0.30, 0), 0.07, LEAF(), (0.55, 1.0, 0.55))


def metronome():
    wood, brass, black = WOOD(), BRASS(), BLACK()
    cone("metronome case", (0, 0.46, 0), 0.40, 0.18, 0.88, wood, 4)
    cube("scale plate", (0, 0.52, -0.205), (0.23, 0.47, 0.015), PAPER(), 0.003)
    cylinder("pivot", (0, 0.57, -0.23), 0.045, 0.035, brass, 16, (math.pi / 2, 0, 0))
    tube("pendulum arm", [(0, 0.58, -0.25), (0.18, 1.02, -0.25)], 0.018, brass)
    cube("sliding weight", (0.14, 0.90, -0.25), (0.10, 0.06, 0.045), black, 0.01)
    cylinder("winding key", (-0.14, 0.26, -0.23), 0.04, 0.08, brass, 12, (math.pi / 2, 0, 0))


def projector():
    black, steel, brass = BLACK(), STEEL(), BRASS()
    cube("projector chassis", (0, 0.42, 0), (0.94, 0.43, 0.56), black, 0.06)
    cube("projector top", (0, 0.66, 0), (0.68, 0.08, 0.42), steel, 0.025)
    for x in (-0.25, 0.16):
        torus("spoked film reel", (x, 0.96, 0), 0.24, 0.025, steel, (math.pi / 2, 0, 0))
        cylinder("reel hub", (x, 0.96, -0.03), 0.05, 0.07, brass, 16, (math.pi / 2, 0, 0))
        for a in range(0, 360, 60):
            spoke = cube("reel spoke", (x + math.cos(math.radians(a)) * 0.115, 0.96 + math.sin(math.radians(a)) * 0.115, -0.035), (0.22, 0.018, 0.018), steel, 0.002)
            spoke.rotation_euler[2] = math.radians(a)
    for radius, length in ((0.17, 0.22), (0.13, 0.18), (0.095, 0.12)):
        cylinder("stepped lens", (0.54 + length / 2, 0.44, 0), radius, length, steel, 24, (0, math.pi / 2, 0), 0.008)
    for x in (-0.31, 0.31):
        cube("projector foot", (x, 0.15, 0), (0.12, 0.18, 0.17), brass, 0.02)
    cylinder("focus knob", (0.18, 0.54, -0.33), 0.06, 0.05, brass, 16, (math.pi / 2, 0, 0))


def violin():
    wood, black, steel = material("violin maple", (0.42, 0.12, 0.018, 1), 0, 0.25), BLACK(), STEEL()
    uv("lower violin bout", (0, 0.30, 0), 0.25, wood, (1.05, 1.35, 0.32))
    uv("upper violin bout", (0, 0.62, 0), 0.19, wood, (1.05, 1.22, 0.32))
    cube("violin waist", (0, 0.46, 0), (0.22, 0.18, 0.10), wood, 0.07)
    cube("violin neck", (0, 1.02, 0), (0.08, 0.66, 0.06), black, 0.015)
    uv("scroll", (0, 1.37, 0), 0.075, wood, (1.1, 0.85, 0.8))
    cube("fingerboard", (0, 0.88, -0.045), (0.10, 0.83, 0.025), black, 0.004)
    cube("bridge", (0, 0.56, -0.055), (0.19, 0.09, 0.025), material("bridge", (0.73, 0.47, 0.14, 1), 0, 0.45), 0.004)
    for x in (-0.024, -0.008, 0.008, 0.024):
        tube("violin string", [(x, 0.24, -0.07), (x, 1.38, -0.07)], 0.003, steel)
    for side in (-1, 1):
        tube("f hole", [(side * 0.11, 0.32, -0.085), (side * 0.14, 0.44, -0.085), (side * 0.10, 0.56, -0.085)], 0.010, black)


def wine_bottle():
    glass, paper, gold = material("wine glass", (0.01, 0.075, 0.028, 1), 0.15, 0.18), PAPER(), GOLD()
    cylinder("wine bottle body", (0, 0.46, 0), 0.26, 0.82, glass, 32, bevel=0.018)
    cone("wine shoulder", (0, 0.94, 0), 0.26, 0.085, 0.22, glass, 32)
    cylinder("wine neck", (0, 1.15, 0), 0.085, 0.26, glass, 24)
    cylinder("foil capsule", (0, 1.29, 0), 0.10, 0.07, gold, 24, bevel=0.008)
    cube("wine label", (0, 0.49, -0.265), (0.28, 0.42, 0.01), paper, 0.002)
    torus("bottle punt", (0, 0.05, 0), 0.12, 0.018, glass)


def divider():
    brass, black = BRASS(), BLACK()
    cylinder("divider pivot", (0, 0.56, 0), 0.055, 0.09, brass, 16, (math.pi / 2, 0, 0))
    for side in (-1, 1):
        leg = cube("divider leg", (side * 0.21, 0.30, 0), (0.055, 0.64, 0.05), brass, 0.01)
        leg.rotation_euler[2] = side * math.radians(26)
        cone("divider point", (side * 0.38, 0.02, 0), 0.035, 0.002, 0.18, steel:=STEEL(), 16)
    cube("divider adjustment", (0, 0.56, -0.06), (0.24, 0.045, 0.035), black, 0.008)


def scale_model():
    concrete, brass, glass = material("model concrete", (0.38, 0.39, 0.36, 1), 0, 0.55), BRASS(), material("model glazing", (0.16, 0.42, 0.48, 1), 0.1, 0.18)
    cube("architectural base", (0, 0.07, 0), (1.45, 0.14, 1.15), material("model base", (0.08, 0.09, 0.10, 1), 0.1, 0.35), 0.03)
    for index, (x, z, floors) in enumerate([(-0.33, -0.16, 4), (0.28, 0.12, 6), (0.16, -0.34, 3)]):
        height = floors * 0.14
        cube("model tower", (x, 0.14 + height / 2, z), (0.34, height, 0.30), concrete, 0.012)
        for y in range(floors):
            cube("model window band", (x, 0.24 + y * 0.14, z - 0.156), (0.25, 0.055, 0.006), glass, 0.001)
    cube("removable barrier", (-0.02, 0.20, 0.38), (0.62, 0.14, 0.05), brass, 0.01)
    for x in (-0.27, -0.09, 0.09, 0.27):
        cylinder("barrier post", (x, 0.26, 0.38), 0.012, 0.18, brass, 12)


def rail_carriage():
    rail, brass, glass = material("railway blue", (0.045, 0.10, 0.14, 1), 0.32, 0.27), BRASS(), material("window glass", (0.07, 0.25, 0.31, 1), 0.12, 0.18)
    cube("carriage body", (0, 1.05, 0), (3.8, 1.65, 1.12), rail, 0.08)
    cube("roof", (0, 1.91, 0), (3.96, 0.20, 1.23), material("carriage roof", (0.025, 0.034, 0.042, 1), 0.2, 0.32), 0.06)
    for x in (-1.34, -0.67, 0, 0.67, 1.34):
        cube("carriage window", (x, 1.20, -0.568), (0.48, 0.62, 0.018), glass, 0.01)
        cube("window frame top", (x, 1.54, -0.59), (0.52, 0.04, 0.025), brass, 0.004)
    for x in (-1.28, 1.28):
        for z in (-0.40, 0.40):
            wheel((x, 0.29, z), 0.30, 0.13)
    cube("bogie beam", (0, 0.50, 0), (3.20, 0.16, 0.74), material("bogie", (0.03, 0.04, 0.05, 1), 0.5, 0.35), 0.02)
    cube("coupler", (2.12, 0.50, 0), (0.50, 0.12, 0.22), brass, 0.02)


ASSETS = {
    "assets/models/mysteries/bellwether-mysteries/the-last-garden-prize/silver-garden-prize-cup.glb": trophy,
    "assets/models/mysteries/bellwether-mysteries/the-last-garden-prize/cast-iron-hose-guide.glb": hose_guide,
    "assets/models/mysteries/bellwether-mysteries/the-last-garden-prize/exhibition-plant-cart.glb": plant_cart,
    "assets/models/mysteries/bellwether-mysteries/the-last-garden-prize/prize-orchid-and-display-pot.glb": orchid,
    "assets/models/mysteries/bellwether-mysteries/a-recipe-for-silence/engraved-tasting-spoon.glb": spoon,
    "assets/models/mysteries/bellwether-mysteries/a-recipe-for-silence/herb-jars.glb": herb_jar,
    "assets/models/mysteries/one-more-question/a-private-performance/heavy-mechanical-metronome.glb": metronome,
    "assets/models/mysteries/one-more-question/the-final-cut/film-projector.glb": projector,
    "assets/models/mysteries/one-more-question/a-private-performance/violin-bow-and-fitted-case.glb": violin,
    "assets/models/mysteries/one-more-question/the-perfect-vintage/rare-hero-bottle.glb": wine_bottle,
    "assets/models/mysteries/the-blackthorn-papers/the-ashes-of-blackthorn-lane/brass-cartographer-s-divider.glb": divider,
    "assets/models/mysteries/one-more-question/the-architect-s-model/modular-tower-scale-model.glb": scale_model,
    "assets/models/mysteries/the-blackthorn-papers/the-empty-carriage/inspection-rail-carriage.glb": rail_carriage,
}


def export(path, build):
    clear()
    build()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.convert(target="MESH")
    name = next(item for item in json.loads((ROOT / "assets/models/mysteries/manifest.json").read_text())["models"] if f"assets/models/mysteries/{item['path']}" == path)["name"]
    objects = [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "CURVE"}]
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    factor = target_max_span_m(name) / max(high - low)
    for obj in objects:
        obj.location *= factor
        obj.scale *= factor
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for obj in bpy.context.scene.objects:
        obj["asset_tier"] = "P0 hero"
        obj["generator"] = "blender_build_p0_mystery_heroes.py"
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True, export_apply=True, export_yup=False, export_extras=True, export_materials="EXPORT")


requested = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set()
for asset_path, builder in ASSETS.items():
    if requested and asset_path not in requested:
        continue
    export(asset_path, builder)
    print(f"P0 hero: {asset_path}")
